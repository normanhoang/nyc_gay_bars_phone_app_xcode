import Foundation
import CloudKit
import Combine

/// Friends-feature state: own profile, friends, requests, and the Tonight
/// feed, all backed by the CloudKit public database via `CloudKitSocial`.
/// Own profile + friends are cached in UserDefaults so relaunches don't
/// block on the network; everything else is fetched on demand.
@MainActor
final class SocialStore: ObservableObject {
    /// Single instance shared between the SwiftUI environment and AppDelegate
    /// push callbacks.
    static let shared = SocialStore()

    enum AccountState: Equatable {
        case unknown
        /// Device has no iCloud account (or iCloud is restricted) — feature disabled.
        case unavailable
        case ready
    }

    private static let profileKey = "@gaybars/socialProfile"
    private static let friendsKey = "@gaybars/socialFriends"
    private static let prefsKey = "@gaybars/socialPrefs"

    @Published private(set) var accountState: AccountState = .unknown
    /// Nil until the user completes friends onboarding (picks a display name).
    @Published private(set) var profile: FriendProfile?
    @Published private(set) var friends: [FriendProfile] = []
    @Published private(set) var incomingRequests: [FriendRequestItem] = []
    @Published private(set) var outgoingRequests: [FriendRequestItem] = []
    @Published private(set) var tonight: [FriendCheckIn] = []
    /// Per-friend send/get toggles (device-local; new friends default on).
    @Published private(set) var prefs = SocialPrefs()
    @Published private(set) var busy = false
    /// Last operation error, for inline display in FriendsView.
    @Published var errorMessage: String?
    /// Bar to open from a tapped check-in notification (consumed by RootTabView).
    @Published var deepLinkBarId: String?
    /// Friend code from an add-friend link/QR, held until the store can act
    /// on it (also cues RootTabView to switch to the Friends tab).
    @Published var pendingAddCode: String?
    /// Transient success feedback (e.g. auto-sent friend request).
    @Published var infoMessage: String?

    private let ck = CloudKitSocial()
    private let defaults = UserDefaults.standard
    private var userID: String?
    /// When each friend first looked like a removal candidate — debounces the
    /// mirror-removal so a fresh acceptance's consistency blip isn't acted on.
    private var removalCandidateSince: [String: Date] = [:]
    /// When each cached friend first went missing from the own-Friendship
    /// query — retains them through non-monotonic replica blips (a stale read
    /// dropping a friend is what made accepted friends toggle back to an
    /// Accept row). See `Social.retainedFriendIDs`.
    private var friendMissingSince: [String: Date] = [:]
    /// Incoming requests shown from a tapped push payload before the record is
    /// queryable; merged through refresh() until CloudKit catches up.
    private var optimisticIncoming: [(item: FriendRequestItem, at: Date)] = []
    /// Own check-ins removed moments ago. CloudKit queries are eventually
    /// consistent and non-monotonic, so the delete may not be reflected in the
    /// next fetch — suppress those stamps locally until it is.
    private var checkInTombstones: [Social.CheckInTombstone] = []
    /// Own check-ins shared moments ago, shown before CloudKit's query index
    /// catches up so the row is in Tonight the instant the write succeeds.
    private var optimisticOwnCheckIns: [(checkIn: FriendCheckIn, at: Date)] = []
    /// Record names of the check-in fan-outs shared this launch, so a removal
    /// deletes by id. The query-based delete can't be used inside the same
    /// index-lag window the share just opened — it would match nothing and
    /// report success. See `Social.CheckInFanOut`.
    private var ownFanOuts: [Social.CheckInFanOut] = []
    /// Friends accepted moments ago, kept in the list until the Friendship
    /// write becomes queryable — a refresh inside CloudKit's index lag would
    /// otherwise drop the friend and resurrect the Accept row.
    private var optimisticFriends: [(profile: FriendProfile, at: Date)] = []
    /// Set when a friend-request notification is tapped, so RootTabView switches
    /// to the Friends tab. Reset by RootTabView after navigating.
    @Published var focusFriendsTab = false

    init() {
        if let data = defaults.data(forKey: Self.profileKey),
           let cached = try? JSONDecoder().decode(FriendProfile.self, from: data) {
            profile = cached
            userID = cached.id
        }
        if let data = defaults.data(forKey: Self.friendsKey),
           let cached = try? JSONDecoder().decode([FriendProfile].self, from: data) {
            friends = cached
        }
        if let data = defaults.data(forKey: Self.prefsKey),
           let cached = try? JSONDecoder().decode(SocialPrefs.self, from: data) {
            prefs = cached
        }
    }

    var onboarded: Bool { profile != nil }

    /// At least one friend is send-enabled. Drives the share button's
    /// visibility; recomputed live as friends/prefs change.
    var canShareCheckIns: Bool {
        onboarded && !prefs.recipients(of: friends.map(\.id)).isEmpty
    }

    // MARK: - Lifecycle

    /// Check iCloud, then pull everything fresh. Call on appear of FriendsView
    /// and from push handlers.
    func start() async {
        do {
            let status = try await ck.accountStatus()
            guard status == .available else {
                accountState = .unavailable
                return
            }
            accountState = .ready
            userID = try await ck.myUserID()
            // A different iCloud account signed in since the caches were
            // written: acting as the old identity would send requests the
            // recipients' creator check rejects. Drop everything cached.
            if let cached = profile, cached.id != userID {
                resetForAccountChange()
            }
            if profile == nil {
                profile = try await ck.fetchProfile(userID: userID!)
                persistProfile()
            }
            guard onboarded else { return }
            await refresh()
            await consumePendingAddCode()
            try? await ck.deleteExpiredCheckIns(authorID: userID!)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Add-friend links

    /// Entry point for nycgaybars://addfriend?code=X (onOpenURL).
    func handleAddFriendLink(_ url: URL) {
        guard let code = Social.parseAddFriendURL(url) else { return }
        pendingAddCode = code
        Task { await consumePendingAddCode() }
    }

    /// Auto-send the held request once signed in + onboarded. A cold launch
    /// holds the code until start() finishes; a not-yet-onboarded user keeps
    /// it through onboarding.
    private func consumePendingAddCode() async {
        guard accountState == .ready, onboarded, let code = pendingAddCode else { return }
        pendingAddCode = nil
        let friendsBefore = friends.count
        await addFriend(code: code)
        guard errorMessage == nil else { return }
        infoMessage = friends.count > friendsBefore
            ? "Friend added!"
            : "Friend request sent — they'll need to accept."
    }

    /// In-flight refresh, joined by concurrent callers. refresh() is called
    /// from overlapping sources (12s poll, push reconcile retries, scenePhase,
    /// pull-to-refresh); unserialized, an older run holding stale fetch
    /// results could assign published state *after* a newer one, flapping the
    /// UI — and two runs could double-write the handshake mirror, re-stamping
    /// the Friendship creationDate that the acceptance gates compare against.
    private var activeRefresh: Task<Void, Never>?

    /// Re-fetch requests, friendships (completing any accepted handshakes),
    /// subscriptions, and the Tonight feed. Single-flight: a call made while
    /// a refresh is running joins it instead of starting another (callers are
    /// all retry structures, so a marginally-stale join self-corrects on
    /// their next tick). The unstructured Task keeps a cancelled caller
    /// (e.g. pull-to-refresh) from aborting a refresh mid-server-write.
    func refresh() async {
        if let running = activeRefresh { await running.value; return }
        let task = Task { await performRefresh() }
        activeRefresh = task
        await task.value
        activeRefresh = nil
    }

    private func performRefresh() async {
        guard let me = userID, onboarded else { return }
        do {
            // The four base queries are independent — fetch concurrently.
            async let incomingFetch = ck.incomingRequests(userID: me)
            async let outgoingFetch = ck.outgoingRequests(userID: me)
            async let idsFetch = ck.friendIDs(ownerID: me)
            async let friendedByFetch = ck.friendedByIDs(userID: me)
            var incoming = try await incomingFetch
            var outgoing = try await outgoingFetch
            let ownDates = try await idsFetch
            let friendedByDates = try await friendedByFetch
            var ids = Array(ownDates.keys)
            let friendedBy = Set(friendedByDates.keys)

            // Stale relics of a dead friendship: my own Friendship{me→X}
            // predates a fresh request from X and X doesn't friend me back
            // (unfriending only deletes one's own direction). Left alone the
            // relic hides X's Accept row (X reads as "already a friend") and
            // the pending request shields it from mirror-removal — delete it
            // so the request can surface.
            // Ids this refresh deletes on purpose — they must not be retained
            // through the missing-friend grace below.
            var deliberateRemovals = Set<String>()
            for id in Social.staleOwnFriendships(incoming: incoming, ownFriendDates: ownDates,
                                                 friendedBy: friendedBy) {
                try await ck.removeFriendship(ownerID: me, friendID: id)
                ids.removeAll { $0 == id }
                deliberateRemovals.insert(id)
            }

            // Someone I sent a request to created their Friendship{them→me}
            // *after* the request (server timestamps — a pre-existing record is
            // a relic, not consent): finish the handshake by creating the
            // mirror and dropping the request. Only mirrors users I actually
            // requested — a stranger creating a Friendship pointing at me is
            // ignored.
            for request in Social.acceptedOutgoing(outgoing, friendedByDates: friendedByDates) {
                try await ck.createFriendship(ownerID: me, friendID: request.toID)
                try await ck.deleteRequest(recordName: request.id)
                if !ids.contains(request.toID) { ids.append(request.toID) }
                outgoing.removeAll { $0.id == request.id }
            }

            // Mirror removals: a friend whose own Friendship{them→me} record is
            // gone has unfriended me — delete my record too so removal takes
            // effect on both sides, and retract my check-ins addressed to them.
            // Debounced: a just-accepted friendship can momentarily look
            // one-sided during CloudKit's consistency window, so only act on a
            // candidate that has persisted past Social.removalGrace.
            let candidates = Social.removedFriendIDs(friends: ids, friendedBy: friendedBy,
                                                     pendingIn: Set(incoming.map(\.fromID)),
                                                     pendingOut: Set(outgoing.map(\.toID)))
            let removedBy = Social.confirmedRemovals(candidates: candidates,
                                                     since: &removalCandidateSince, now: Date())
            for id in removedBy {
                try await ck.removeFriendship(ownerID: me, friendID: id)
                try? await ck.deleteCheckIns(authorID: me, recipientID: id)
            }
            ids.removeAll(where: removedBy.contains)
            deliberateRemovals.formUnion(removedBy)

            // Own Friendship records are only ever deleted by this device, so
            // a cached friend missing from the (eventually-consistent,
            // non-monotonic) query is a replica blip unless deleted above —
            // retain them through the grace so a stale read can't drop the
            // friend row and resurface their accepted request.
            ids.append(contentsOf: Social.retainedFriendIDs(
                fetched: Set(ids), cached: friends.map(\.id),
                excluded: deliberateRemovals,
                missingSince: &friendMissingSince, now: Date()))

            // Ignored requests stay hidden (only the sender can delete the
            // record); prune once the record is gone — or replaced by a newer
            // re-request — so the map can't grow or hide fresh requests.
            // Entries ignored moments ago survive a fetch that missed them.
            prefs.ignored = Social.prunedIgnored(prefs.ignored, fetched: incoming, now: Date())
            incoming.removeAll { Social.isHidden($0, ignored: prefs.ignored) }
            // A request from someone who's already a friend is stale — the
            // sender deletes their record only when their device next syncs.
            // Just-accepted friends count too (their Friendship write may not
            // be queryable yet) so the accepted request can't resurface.
            let friendIDSet = Set(ids).union(optimisticFriends.map(\.profile.id))
            incoming.removeAll { friendIDSet.contains($0.fromID) }
            // Keep any push-payload request the server hasn't made queryable yet
            // so this refresh doesn't drop the Accept row it just showed.
            optimisticIncoming.removeAll { friendIDSet.contains($0.item.fromID) || Social.isHidden($0.item, ignored: prefs.ignored) }
            let (mergedIncoming, keepIDs) = Social.mergedIncoming(
                fetched: incoming, optimistic: optimisticIncoming, now: Date())
            optimisticIncoming.removeAll { !keepIDs.contains($0.item.id) }
            incomingRequests = mergedIncoming
            outgoingRequests = outgoing

            async let profilesFetch = ck.profiles(userIDs: ids)
            async let tonightFetch = ck.tonightCheckIns(userID: me)
            let fetchedProfiles = try await profilesFetch
            // Overlay just-accepted friends, reading optimisticFriends *after*
            // every await: an accept() that lands while this refresh's queries
            // were in flight still survives the rebuild (main-actor ordering).
            let (mergedFriends, keepFriendIDs) = Social.mergedFriends(
                fetched: fetchedProfiles, optimistic: optimisticFriends,
                fetchedIDs: Set(ids), now: Date())
            optimisticFriends.removeAll { !keepFriendIDs.contains($0.profile.id) }
            friends = mergedFriends.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            persistFriends()
            prefs.prune(keeping: mergedFriends.map(\.id))
            persistPrefs()
            // Drop check-ins from anyone no longer a friend (their unexpired
            // records can outlive the friendship by up to the Tonight window).
            tonight = rebuildTonight(try await tonightFetch, friendIDs: friendIDSet, me: me)
            try await syncSubscriptionsIfNeeded(me: me, friendIDs: ids)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Wanted subscription IDs as of the last successful server sync; skips
    /// the fetch-all-subscriptions round trip when nothing changed.
    private var syncedSubIDs: Set<String>?

    private func syncSubscriptionsIfNeeded(me: String, friendIDs: [String]) async throws {
        // Check-in pushes are gated off (Social.checkInPushEnabled). With no
        // wanted check-in subs, syncSubscriptions also deletes any that already
        // exist server-side, so devices stop receiving check-in alerts — the
        // Tonight feed (a query) is unaffected. Request/friendship subs stay.
        let wanted = Social.checkInPushEnabled ? Set(prefs.subscribed(of: friendIDs)) : []
        guard wanted != syncedSubIDs else { return }
        try await ck.syncSubscriptions(userID: me, subscribedFriendIDs: Array(wanted))
        syncedSubIDs = wanted
    }

    // MARK: - Onboarding

    func createProfile(displayName rawName: String) async {
        // Cap length: no server enforces this, and the name is shown in other
        // users' push alerts and friend UI.
        let name = String(rawName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Social.maxDisplayNameLength))
        guard !name.isEmpty, let me = userID else { return }
        busy = true
        defer { busy = false }
        do {
            profile = try await ck.createProfile(userID: me, displayName: name)
            persistProfile()
            await refresh()
            await consumePendingAddCode()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Rename yourself: update the CloudKit Profile in place (code preserved) and
    /// rewrite the name copies you own so friends stop seeing the old one. Local
    /// name updates instantly; friends' cached copy refreshes on their next sync.
    func updateDisplayName(_ rawName: String) async {
        let name = String(rawName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Social.maxDisplayNameLength))
        guard !name.isEmpty, let me = userID, let current = profile, current.displayName != name else { return }
        let previous = current
        profile = FriendProfile(id: current.id, displayName: name, code: current.code)
        persistProfile()
        busy = true
        defer { busy = false }
        do {
            profile = try await ck.updateProfileName(userID: me, displayName: name)
            persistProfile()
            // Best-effort: leftover old-name copies expire on their own (24h for
            // check-ins) and don't block the rename.
            try? await ck.renameOutgoingRequests(fromID: me, newName: name)
            try? await ck.renameCheckIns(authorID: me, newName: name)
        } catch {
            errorMessage = friendlyError(error)
            profile = previous
            persistProfile()
        }
    }

    // MARK: - Friend groups (device-local; bulk send/get)

    func createGroup(name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Social.maxDisplayNameLength))
        guard !trimmed.isEmpty else { return }
        prefs.groups.append(FriendGroup(name: trimmed))
        persistPrefs()
    }

    func renameGroup(_ group: FriendGroup, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Social.maxDisplayNameLength))
        guard !trimmed.isEmpty, let i = prefs.groups.firstIndex(where: { $0.id == group.id }) else { return }
        prefs.groups[i].name = trimmed
        persistPrefs()
    }

    func deleteGroup(_ group: FriendGroup) {
        prefs.groups.removeAll { $0.id == group.id }
        persistPrefs()
    }

    func setMembership(_ friend: FriendProfile, in group: FriendGroup, member: Bool) {
        guard let i = prefs.groups.firstIndex(where: { $0.id == group.id }) else { return }
        if member { prefs.groups[i].members.insert(friend.id) }
        else { prefs.groups[i].members.remove(friend.id) }
        persistPrefs()
    }

    /// Bulk-flip send for every member of a group.
    func setGroupSend(_ group: FriendGroup, on: Bool) {
        prefs.setSend(group.members, on: on)
        persistPrefs()
    }

    /// Bulk-flip get for every member, then reconcile subscriptions once.
    func setGroupGet(_ group: FriendGroup, on: Bool) async {
        prefs.setGet(group.members, on: on)
        persistPrefs()
        guard let me = userID else { return }
        try? await syncSubscriptionsIfNeeded(me: me, friendIDs: friends.map(\.id))
    }

    // MARK: - Friends

    /// Send a request by invite code. If that user already requested me,
    /// this accepts instead of sending a duplicate crossing request.
    func addFriend(code rawCode: String) async {
        errorMessage = nil
        guard let me = profile else { return }
        guard let code = Social.normalizeCode(rawCode) else {
            errorMessage = "That doesn't look like a friend code."
            return
        }
        busy = true
        defer { busy = false }
        do {
            guard let other = try await ck.lookupProfile(code: code) else {
                errorMessage = "No one has that code."
                return
            }
            guard other.id != me.id else {
                errorMessage = "That's your own code."
                return
            }
            guard !friends.contains(where: { $0.id == other.id }) else {
                errorMessage = "\(other.displayName) is already your friend."
                return
            }
            if let crossing = incomingRequests.first(where: { $0.fromID == other.id }) {
                await accept(crossing)
                return
            }
            try await ck.sendRequest(from: me, to: other)
            outgoingRequests = try await ck.outgoingRequests(userID: me.id)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func accept(_ request: FriendRequestItem) async {
        guard let me = userID else { return }
        // Optimistic: drop the request and show the new friend immediately so
        // the tap feels instant. A full refresh() here would re-fetch from
        // CloudKit before it's consistent — re-adding the still-present request
        // record and missing the just-written friendship — which is what makes
        // the row flicker out and back. Reconcile the real profile narrowly.
        incomingRequests.removeAll { $0.id == request.id }
        optimisticIncoming.removeAll { $0.item.id == request.id }
        let placeholder = FriendProfile(id: request.fromID, displayName: request.fromName, code: "")
        if !friends.contains(where: { $0.id == request.fromID }) {
            friends.append(placeholder)
            friends.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            persistFriends()
        }
        // Overlay entry keeps the friend through refreshes until the Friendship
        // write becomes queryable (CloudKit index lag).
        optimisticFriends.removeAll { $0.profile.id == request.fromID }
        optimisticFriends.append((placeholder, Date()))
        do {
            try await ck.createFriendship(ownerID: me, friendID: request.fromID)
        } catch {
            // Roll back only when the friendship write itself failed.
            errorMessage = friendlyError(error)
            friends.removeAll { $0.id == request.fromID }
            optimisticFriends.removeAll { $0.profile.id == request.fromID }
            persistFriends()
            return
        }
        // Persistently hide the accepted request: the sender's record stays on
        // the server until their device completes the handshake (hours if
        // they're offline), and a stale replica read in that window would
        // resurface the Accept row. Stamped only after the friendship write
        // succeeds so a failed accept can still be retried. `acceptStamp`
        // outruns the request's server creationDate (device clock may trail);
        // a genuine later re-request gets a newer date and surfaces normally.
        prefs.ignored[request.id] = Social.acceptStamp(for: request, now: Date())
        persistPrefs()
        // Best-effort from here: subscriptions re-reconcile at the end of every
        // refresh(), and the canonical profile lands via the overlay's
        // takeover — neither failure may un-friend the accepted row.
        try? await syncSubscriptionsIfNeeded(me: me, friendIDs: friends.map(\.id))
        // Fill in the real profile (proper code, canonical name) without a
        // broad refresh that could clobber the optimistic row.
        if let real = try? await ck.profiles(userIDs: [request.fromID]).first {
            if let idx = friends.firstIndex(where: { $0.id == real.id }) {
                friends[idx] = real
                persistFriends()
            }
            if let oidx = optimisticFriends.firstIndex(where: { $0.profile.id == real.id }) {
                optimisticFriends[oidx].profile = real
            }
        }
    }

    /// Hide an incoming request (we can't delete the sender's record, so the
    /// ID is persisted and filtered out of every refresh until it's gone).
    func ignore(_ request: FriendRequestItem) {
        incomingRequests.removeAll { $0.id == request.id }
        optimisticIncoming.removeAll { $0.item.id == request.id }
        prefs.ignored[request.id] = Date()
        persistPrefs()
    }

    func removeFriend(_ friend: FriendProfile) async {
        guard let me = userID else { return }
        do {
            try await ck.removeFriendship(ownerID: me, friendID: friend.id)
            // Best effort: retract already-sent check-ins so nothing lingers
            // in their feed. Leftovers expire at the 24h TTL anyway.
            try? await ck.deleteCheckIns(authorID: me, recipientID: friend.id)
            // Clear any lingering request between us (e.g. removed mid-handshake)
            // so re-adding later starts clean: drop my outgoing to them, and
            // hide their incoming to me until it disappears server-side.
            try? await ck.deleteRequest(from: me, to: friend.id)
            prefs.ignored["request-\(friend.id)-\(me)"] = Date()
            friends.removeAll { $0.id == friend.id }
            // Also drop any overlay entry, or it would resurrect the removed
            // friend on the next refresh for up to the overlay grace.
            optimisticFriends.removeAll { $0.profile.id == friend.id }
            persistFriends()
            prefs.prune(keeping: friends.map(\.id))
            persistPrefs()
            try await syncSubscriptionsIfNeeded(me: me, friendIDs: friends.map(\.id))
            tonight.removeAll { $0.authorID == friend.id }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Notification prefs

    /// "Send to" toggle: unchecked friends get no record addressed to them —
    /// no push and nothing in their Tonight feed.
    func toggleSend(_ friend: FriendProfile) {
        prefs.toggleSend(friend.id)
        persistPrefs()
    }

    /// "Get from" toggle: mutes their pushes by dropping the subscription.
    /// Their check-ins still appear in the Tonight feed.
    func toggleGet(_ friend: FriendProfile) async {
        prefs.toggleGet(friend.id)
        persistPrefs()
        guard let me = userID else { return }
        try? await syncSubscriptionsIfNeeded(me: me, friendIDs: friends.map(\.id))
    }

    // MARK: - Check-ins

    /// My CloudKit user record name once known — the identity every own-row
    /// check (feed filtering, the "YOU" badge, removal) is made against.
    var myID: String? { userID }

    /// Check-ins by friends only — the "who's out" surfaces (map pins, the
    /// friends-out count) exclude my own row.
    var friendsTonight: [FriendCheckIn] { Social.friendsOnly(tonight, me: myID) }

    /// Broadcast presence at a bar to send-enabled friends. Returns true on success.
    /// A copy addressed to myself rides along so the check-in also lands in my
    /// own Tonight feed (the feed query is `recipientID == me`).
    @discardableResult
    func shareCheckIn(bar: Bar) async -> Bool {
        guard let me = profile else { return false }
        let recipients = prefs.recipients(of: friends.map(\.id))
        guard !recipients.isEmpty else {
            errorMessage = friends.isEmpty
                ? "Add friends first to share check-ins."
                : "Sharing is switched off for all your friends."
            return false
        }
        busy = true
        defer { busy = false }
        // One stamp for every copy and for the local row: the retained fan-out,
        // the delete-by-timestamp fallback and the optimistic merge all match
        // on it.
        let ts = Date()
        do {
            let (saved, failure) = try await ck.createCheckIn(author: me, bar: bar,
                                                              recipients: recipients + [me.id], now: ts)
            // Retain the ids first even when the batch was partial: the copies
            // that did land are live in those friends' feeds, and this is the
            // only handle on them until the 24h TTL.
            retainFanOut(ts: ts, ids: saved)
            if let failure {
                errorMessage = friendlyError(failure)
                return false
            }
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
        // Show it in Tonight now rather than when the record becomes queryable
        // (CloudKit index lag is seconds). The canonical copy takes over on a
        // later refresh; tonightFeed's author|bar dedupe keeps it to one row.
        let row = FriendCheckIn(id: "own-\(bar.id)-\(Int(ts.timeIntervalSince1970))",
                                authorID: me.id, authorName: me.displayName,
                                barId: bar.id, barName: bar.name, date: ts)
        optimisticOwnCheckIns.removeAll { $0.checkIn.barId == bar.id }
        optimisticOwnCheckIns.append((row, Date()))
        // Append to the published feed directly rather than re-running the
        // rebuild over it: the rebuild treats its input as a fetch, so feeding
        // the current feed back in would read the overlay rows already in it as
        // "canonical arrived" and retire them before CloudKit can serve them.
        tonight = Social.tonightFeed(tonight + [row], now: Date())
        return true
    }

    /// Retain a shared fan-out's record names so its removal can delete by id.
    private func retainFanOut(ts: Date, ids: [CKRecord.ID]) {
        guard !ids.isEmpty else { return }
        ownFanOuts = Social.prunedFanOuts(ownFanOuts, now: Date())
        ownFanOuts.append(.init(ts: ts, recordNames: ids.map(\.recordName)))
    }

    /// Retract one of my own check-ins: deletes every recipient copy, so it
    /// leaves friends' Tonight feeds too, plus my own copy. Deletes by the
    /// record names retained at share time when we still hold them — a
    /// query-based delete right after a share matches nothing (CloudKit's
    /// query index lags the write by seconds) and would silently leave every
    /// copy live. Fan-outs from an earlier launch fall back to the
    /// timestamp query, which retries and throws rather than reporting a
    /// no-op as success. The row goes immediately and is tombstoned so an
    /// eventually-consistent query can't resurrect it; a failed delete rolls
    /// both back.
    func removeOwnCheckIn(_ checkIn: FriendCheckIn) async {
        guard let me = userID, checkIn.authorID == me else { return }
        let previous = tonight
        let previousOptimistic = optimisticOwnCheckIns
        checkInTombstones.append(.init(ts: checkIn.date, at: Date()))
        // Drop the overlay entry too, or the next rebuild re-adds the row that
        // was just removed.
        optimisticOwnCheckIns.removeAll { Social.isSameCheckIn($0.checkIn.date, checkIn.date) }
        tonight = Social.withoutTombstoned(tonight, me: me, tombstones: checkInTombstones)
        let retained = Social.fanOut(matching: checkIn.date, in: ownFanOuts)
        do {
            if let retained {
                try await ck.deleteCheckIns(recordNames: retained.recordNames)
                ownFanOuts.removeAll { $0 == retained }
            } else {
                try await ck.deleteCheckIns(authorID: me, at: checkIn.date)
            }
        } catch {
            errorMessage = friendlyError(error)
            checkInTombstones.removeAll { $0.ts == checkIn.date }
            optimisticOwnCheckIns = previousOptimistic
            tonight = previous
        }
    }

    func refreshTonight() async {
        guard let me = userID, onboarded else { return }
        do {
            tonight = rebuildTonight(try await ck.tonightCheckIns(userID: me),
                                     friendIDs: Set(friends.map(\.id)), me: me)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Feed rebuild shared by both fetch paths: keep current friends' check-ins
    /// plus my own self-addressed copies, drop anything a just-issued removal
    /// already deleted, then apply the 6h window + per-author/bar dedupe.
    ///
    /// `fetched` must be a fresh server read — the overlay and tombstone lists
    /// are pruned against it as a side effect, so passing the current feed back
    /// in would retire overlay rows that CloudKit hasn't actually served yet.
    private func rebuildTonight(_ fetched: [FriendCheckIn], friendIDs: Set<String>,
                                me: String) -> [FriendCheckIn] {
        let now = Date()
        checkInTombstones = Social.prunedTombstones(checkInTombstones, now: now)
        let kept = fetched.filter { friendIDs.contains($0.authorID) || $0.authorID == me }
        let (merged, keepIDs) = Social.mergedOwnCheckIns(
            fetched: kept, optimistic: optimisticOwnCheckIns, now: now)
        optimisticOwnCheckIns.removeAll { !keepIDs.contains($0.checkIn.id) }
        return Social.tonightFeed(
            Social.withoutTombstoned(merged, me: me, tombstones: checkInTombstones), now: now)
    }

    // MARK: - Push

    /// Route a CloudKit remote notification: friendship (silent) pushes finish
    /// handshakes; request/check-in alerts refresh the relevant state.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return }
        switch note.subscriptionID {
        case CloudKitSocial.friendshipSubID:
            // Someone created a Friendship pointing at me — almost always an
            // acceptance. Retry through CloudKit's consistency lag so the new
            // friend lands even if the push beat the record becoming queryable.
            await reconcilePendingAcceptances()
        case CloudKitSocial.requestSubID:
            // Show the Accept row instantly from the push payload, then retry a
            // few refreshes so the canonical record lands (the payload's fields
            // ride via the subscription's desiredKeys).
            if let q = note as? CKQueryNotification { insertRequestFromPayload(q) }
            await reconcileIncomingRequests()
        case .some(let id) where id.hasPrefix("sub-checkin-"):
            await refreshTonight()
        default:
            break
        }
    }

    /// Insert an incoming request straight from a tapped push's payload so the
    /// Accept row is there before the record is queryable. Deduped and gated the
    /// same way refresh() gates incoming requests.
    private func insertRequestFromPayload(_ q: CKQueryNotification) {
        guard let fields = q.recordFields,
              let fromID = fields["fromID"] as? String,
              let fromName = fields["fromName"] as? String,
              let toID = fields["toID"] as? String,
              toID == userID,
              !friends.contains(where: { $0.id == fromID }) else { return }
        let id = q.recordID?.recordName ?? "request-\(fromID)-\(toID)"
        guard !incomingRequests.contains(where: { $0.id == id }) else { return }
        // The push payload carries no server creation stamp; the record was
        // just created, so "now" is within seconds of the real one. Only the
        // outgoing side's dates feed the handshake gate anyway. Being new, the
        // row also clears any old ignore entry under the same deterministic
        // record name (a push means a fresh request exists).
        let item = FriendRequestItem(id: id, fromID: fromID, fromName: fromName, toID: toID, created: Date())
        guard !Social.isHidden(item, ignored: prefs.ignored) else { return }
        optimisticIncoming.removeAll { $0.item.id == id }
        optimisticIncoming.append((item, Date()))
        incomingRequests.append(item)
    }

    /// Retry backstop for a request push: refresh a few times over ~4s so the
    /// canonical record lands promptly. refresh() merges the optimistic row, so
    /// it isn't dropped while CloudKit catches up.
    private func reconcileIncomingRequests() async {
        if userID == nil { await start(); return }
        guard onboarded else { return }
        for attempt in 0..<4 {
            await refresh()
            if optimisticIncoming.isEmpty { return }   // canonical caught up
            if attempt < 3 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
    }

    /// Complete accepted handshakes, retrying against CloudKit eventual
    /// consistency. A friendship push (or app foreground) can arrive before the
    /// accepter's `Friendship{them→me}` is queryable via `friendedByIDs`; a
    /// single refresh would miss it and never try again, so poll briefly until
    /// an outgoing request resolves. Safe to call with nothing pending.
    func reconcilePendingAcceptances() async {
        if userID == nil { await start() }
        guard onboarded, !outgoingRequests.isEmpty else {
            await refresh(); return
        }
        for attempt in 0..<4 {
            let before = outgoingRequests.count
            await refresh()
            // A resolved acceptance shrinks the outgoing list (mirror created,
            // request deleted). Stop as soon as that happens or nothing's left.
            if outgoingRequests.count < before || outgoingRequests.isEmpty { return }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
        }
    }

    // MARK: - Helpers

    /// Wipe the previous account's cached identity and per-friend state.
    private func resetForAccountChange() {
        profile = nil
        friends = []
        incomingRequests = []
        outgoingRequests = []
        tonight = []
        prefs = SocialPrefs()
        optimisticIncoming = []
        optimisticFriends = []
        removalCandidateSince = [:]
        friendMissingSince = [:]
        checkInTombstones = []
        optimisticOwnCheckIns = []
        ownFanOuts = []
        syncedSubIDs = nil
        defaults.removeObject(forKey: Self.profileKey)
        defaults.removeObject(forKey: Self.friendsKey)
        defaults.removeObject(forKey: Self.prefsKey)
    }

    private func persistProfile() {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    private func persistFriends() {
        if let data = try? JSONEncoder().encode(friends) {
            defaults.set(data, forKey: Self.friendsKey)
        }
    }

    private func persistPrefs() {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: Self.prefsKey)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if error is CloudKitSocial.CheckInRemovalFailed {
            return "Couldn't remove that check-in — try again."
        }
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "No connection — try again."
            case .notAuthenticated: return "Sign in to iCloud in Settings to use Friends."
            case .requestRateLimited, .zoneBusy, .serviceUnavailable: return "iCloud is busy — try again in a moment."
            default: break
            }
        }
        return "Something went wrong — try again."
    }
}
