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

    /// Re-fetch requests, friendships (completing any accepted handshakes),
    /// subscriptions, and the Tonight feed.
    func refresh() async {
        guard let me = userID, onboarded else { return }
        do {
            // The four base queries are independent — fetch concurrently.
            async let incomingFetch = ck.incomingRequests(userID: me)
            async let outgoingFetch = ck.outgoingRequests(userID: me)
            async let idsFetch = ck.friendIDs(ownerID: me)
            async let friendedByFetch = ck.friendedByIDs(userID: me)
            var incoming = try await incomingFetch
            var outgoing = try await outgoingFetch
            var ids = try await idsFetch
            let friendedBy = Set(try await friendedByFetch)

            // Someone I sent a request to created their Friendship{them→me}:
            // finish the handshake by creating the mirror and dropping the
            // request. Only mirrors users I actually requested — a stranger
            // creating a Friendship pointing at me is ignored.
            for request in outgoing where friendedBy.contains(request.toID) {
                try await ck.createFriendship(ownerID: me, friendID: request.toID)
                try await ck.deleteRequest(recordName: request.id)
                if !ids.contains(request.toID) { ids.append(request.toID) }
                outgoing.removeAll { $0.id == request.id }
            }

            // Mirror removals: a friend whose own Friendship{them→me} record is
            // gone has unfriended me — delete my record too so removal takes
            // effect on both sides, and retract my check-ins addressed to them.
            let removedBy = Social.removedFriendIDs(friends: ids, friendedBy: friendedBy,
                                                    pendingIn: Set(incoming.map(\.fromID)),
                                                    pendingOut: Set(outgoing.map(\.toID)))
            for id in removedBy {
                try await ck.removeFriendship(ownerID: me, friendID: id)
                try? await ck.deleteCheckIns(authorID: me, recipientID: id)
            }
            ids.removeAll(where: removedBy.contains)

            // Ignored requests stay hidden (only the sender can delete the
            // record); prune once the record is gone so the set can't grow.
            prefs.ignored.formIntersection(incoming.map(\.id))
            incoming.removeAll { prefs.ignored.contains($0.id) }
            // A request from someone who's already a friend is stale — the
            // sender deletes their record only when their device next syncs.
            let friendIDSet = Set(ids)
            incoming.removeAll { friendIDSet.contains($0.fromID) }
            incomingRequests = incoming
            outgoingRequests = outgoing

            async let profilesFetch = ck.profiles(userIDs: ids)
            async let tonightFetch = ck.tonightCheckIns(userID: me)
            friends = try await profilesFetch.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            persistFriends()
            prefs.prune(keeping: ids)
            persistPrefs()
            // Drop check-ins from anyone no longer a friend (their unexpired
            // records can outlive the friendship by up to the Tonight window).
            tonight = Social.tonightFeed(
                try await tonightFetch.filter { friendIDSet.contains($0.authorID) }, now: Date())
            try await syncSubscriptionsIfNeeded(me: me, friendIDs: ids)
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Wanted subscription IDs as of the last successful server sync; skips
    /// the fetch-all-subscriptions round trip when nothing changed.
    private var syncedSubIDs: Set<String>?

    private func syncSubscriptionsIfNeeded(me: String, friendIDs: [String]) async throws {
        let wanted = Set(prefs.subscribed(of: friendIDs))
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
        busy = true
        defer { busy = false }
        do {
            try await ck.createFriendship(ownerID: me, friendID: request.fromID)
            incomingRequests.removeAll { $0.id == request.id }
            await refresh()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// Hide an incoming request (we can't delete the sender's record, so the
    /// ID is persisted and filtered out of every refresh until it's gone).
    func ignore(_ request: FriendRequestItem) {
        incomingRequests.removeAll { $0.id == request.id }
        prefs.ignored.insert(request.id)
        persistPrefs()
    }

    func removeFriend(_ friend: FriendProfile) async {
        guard let me = userID else { return }
        do {
            try await ck.removeFriendship(ownerID: me, friendID: friend.id)
            // Best effort: retract already-sent check-ins so nothing lingers
            // in their feed. Leftovers expire at the 24h TTL anyway.
            try? await ck.deleteCheckIns(authorID: me, recipientID: friend.id)
            friends.removeAll { $0.id == friend.id }
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

    /// Broadcast presence at a bar to send-enabled friends. Returns true on success.
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
        do {
            try await ck.createCheckIn(author: me, bar: bar, recipients: recipients)
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    func refreshTonight() async {
        guard let me = userID, onboarded else { return }
        do {
            let friendIDSet = Set(friends.map(\.id))
            tonight = Social.tonightFeed(
                try await ck.tonightCheckIns(userID: me).filter { friendIDSet.contains($0.authorID) },
                now: Date())
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Push

    /// Route a CloudKit remote notification: friendship (silent) pushes finish
    /// handshakes; request/check-in alerts refresh the relevant state.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let note = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return }
        switch note.subscriptionID {
        case CloudKitSocial.friendshipSubID, CloudKitSocial.requestSubID:
            await start()
        case .some(let id) where id.hasPrefix("sub-checkin-"):
            await refreshTonight()
        default:
            break
        }
    }

    // MARK: - Helpers

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
