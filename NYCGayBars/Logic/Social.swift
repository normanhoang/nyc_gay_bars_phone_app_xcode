import Foundation

/// Pure logic for the friends feature: invite codes, the Tonight feed window,
/// and the TTL for our own shared check-in records.
enum Social {
    /// Crockford-style alphabet: no I/L/O/0/1 so codes survive being read aloud.
    static let codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    static let codeLength = 6
    /// Friends' check-ins stay in the Tonight feed this long.
    static let tonightWindow: TimeInterval = 3 * 3600
    /// Own CheckIn records older than this are deleted from CloudKit.
    static let checkInTTL: TimeInterval = 6 * 3600
    /// Max display-name length (no server enforces it; shown in others' pushes).
    static let maxDisplayNameLength = 40

    /// Gate for the CloudKit creator-authenticity check (audit finding #1).
    /// Verified against a second iCloud account on 2026-07-11 and enabled —
    /// see FINDINGS.md "Finding #1 verification". If check-ins/requests ever
    /// silently stop appearing after a CloudKit/OS change, flip this off first
    /// and compare `creatorUserRecordID` to the stored author/sender IDs.
    static let verifyRecordCreator = true

    /// Push a notification to friends when you check in. OFF by design: check-in
    /// pushes were judged too noisy — friends see check-ins in the Tonight feed
    /// instead. Flipping to `true` re-creates the per-friend check-in
    /// subscriptions on next refresh (see `SocialStore.syncSubscriptionsIfNeeded`
    /// and the CLAUDE.md social-layer note). The bell (get) toggle is inert while
    /// this is off. Does NOT affect friend-request pushes or the Tonight feed.
    static let checkInPushEnabled = false

    static func generateFriendCode() -> String {
        String((0..<codeLength).map { _ in codeAlphabet.randomElement()! })
    }

    /// Trimmed, uppercased code if it's exactly `codeLength` chars of the alphabet; nil otherwise.
    static func normalizeCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == codeLength, code.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return code
    }

    /// Check-ins within `tonightWindow`, newest first. Future-dated entries (friend
    /// clock skew) are kept. Repeated shares collapse to the newest per
    /// friend + bar (the same friend at a different bar stays a separate row).
    static func tonightFeed(_ checkIns: [FriendCheckIn], now: Date) -> [FriendCheckIn] {
        var seen = Set<String>()
        return checkIns
            .filter { $0.date > now.addingTimeInterval(-tonightWindow) }
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.authorID + "|" + $0.barId).inserted }
    }

    /// How far apart two check-in timestamps may be and still count as copies
    /// of one fan-out. Every recipient copy (including my own) is stamped with
    /// a single `now`, but the value round-trips through CloudKit as a Double —
    /// match a window rather than equality.
    static let checkInMatchWindow: TimeInterval = 1

    /// How long a just-removed own check-in stays suppressed locally. CloudKit
    /// queries are eventually consistent and non-monotonic, so a refresh right
    /// after the delete can hand the record back; without this the row would
    /// flicker straight back into the feed. Matches `friendRetentionGrace`.
    static let checkInTombstoneGrace: TimeInterval = 300

    /// Own check-ins removed moments ago, suppressed until CloudKit stops
    /// returning them (see `checkInTombstoneGrace`).
    struct CheckInTombstone: Equatable {
        /// Timestamp of the removed fan-out (shared by every recipient copy).
        let ts: Date
        /// When the removal was issued.
        let at: Date
    }

    /// How long a just-shared own check-in is shown from local state, before
    /// CloudKit's query index makes the record fetchable.
    static let ownCheckInGrace: TimeInterval = 60

    /// Server record names of one shared check-in fan-out, retained from the
    /// create so a removal can delete by ID. A query-based delete can't be
    /// trusted right after a share: CloudKit's public-DB query index lags the
    /// write by seconds, so it matches nothing, deletes nothing, and reports
    /// success — leaving every copy live in friends' feeds while the local row
    /// hides behind a tombstone that eventually expires.
    struct CheckInFanOut: Equatable {
        /// The stamp every copy shares — how a feed row maps back to its fan-out.
        let ts: Date
        let recordNames: [String]
    }

    /// The retained fan-out this check-in belongs to, if still held (only
    /// fan-outs shared this launch are).
    static func fanOut(matching date: Date, in fanOuts: [CheckInFanOut]) -> CheckInFanOut? {
        fanOuts.first { isSameCheckIn($0.ts, date) }
    }

    /// Drop retained fan-outs past the record TTL: those records are being
    /// reaped anyway, and by then the query fallback is long consistent.
    static func prunedFanOuts(_ fanOuts: [CheckInFanOut], now: Date) -> [CheckInFanOut] {
        fanOuts.filter { !isExpired($0.ts, now: now) }
    }

    /// Two check-in stamps belong to the same fan-out.
    static func isSameCheckIn(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) <= checkInMatchWindow
    }

    static func prunedTombstones(_ tombstones: [CheckInTombstone], now: Date,
                                 grace: TimeInterval = checkInTombstoneGrace) -> [CheckInTombstone] {
        tombstones.filter { now.timeIntervalSince($0.at) < grace }
    }

    /// Drop my own check-ins that a removal already deleted server-side. Only
    /// own records are ever tombstoned — a friend's record with a coincidentally
    /// close timestamp must not be filtered out.
    static func withoutTombstoned(_ checkIns: [FriendCheckIn], me: String,
                                  tombstones: [CheckInTombstone]) -> [FriendCheckIn] {
        guard !tombstones.isEmpty else { return checkIns }
        return checkIns.filter { checkIn in
            guard checkIn.authorID == me else { return true }
            return !tombstones.contains { isSameCheckIn($0.ts, checkIn.date) }
        }
    }

    /// Merge a just-shared own check-in into a freshly-fetched feed, so the row
    /// is visible the instant the write succeeds instead of after CloudKit makes
    /// the record queryable (seconds later). Symmetric to `mergedIncoming` /
    /// `mergedFriends`: an optimistic entry is kept only while the fetch has no
    /// copy of it and it's younger than `grace`; once the canonical record
    /// arrives, it wins. Returns (merged list, ids to keep optimistic).
    static func mergedOwnCheckIns(fetched: [FriendCheckIn],
                                  optimistic: [(checkIn: FriendCheckIn, at: Date)],
                                  now: Date, grace: TimeInterval = ownCheckInGrace)
        -> (merged: [FriendCheckIn], keepIDs: Set<String>) {
        var merged = fetched
        var keep = Set<String>()
        for entry in optimistic {
            let landed = fetched.contains {
                $0.authorID == entry.checkIn.authorID && $0.barId == entry.checkIn.barId
                    && isSameCheckIn($0.date, entry.checkIn.date)
            }
            guard !landed, now.timeIntervalSince(entry.at) < grace else { continue }
            merged.append(entry.checkIn)
            keep.insert(entry.checkIn.id)
        }
        return (merged, keep)
    }

    /// Check-ins by someone other than me — the "who's out" surfaces (map pins,
    /// the friends-out count) are about friends, so my own row is excluded.
    static func friendsOnly(_ checkIns: [FriendCheckIn], me: String?) -> [FriendCheckIn] {
        guard let me else { return checkIns }
        return checkIns.filter { $0.authorID != me }
    }

    /// Friends whose own Friendship{them→me} record is gone and who have no
    /// request pending in either direction: they unfriended me, so my mirror
    /// record should be deleted too. A pending request marks the acceptance
    /// handshake window, where only one side's record exists yet — never a
    /// removal.
    static func removedFriendIDs(friends: [String], friendedBy: Set<String>,
                                 pendingIn: Set<String>, pendingOut: Set<String>) -> Set<String> {
        Set(friends.filter {
            !friendedBy.contains($0) && !pendingIn.contains($0) && !pendingOut.contains($0)
        })
    }

    /// Grace before a removal candidate is acted on. Right after an acceptance,
    /// CloudKit is eventually consistent: the requester's mirror create and the
    /// request delete propagate independently, so a freshly-mutual friendship
    /// can momentarily look one-sided (`removedFriendIDs` flags it). Debouncing
    /// past this window keeps a real unfriend removable while ignoring the blip.
    static let removalGrace: TimeInterval = 60

    /// Debounce `removedFriendIDs`: confirm only candidates that have stayed
    /// candidates for at least `grace`. `since` (persisted across refreshes)
    /// tracks when each id first became a candidate; entries for ids no longer
    /// candidates are dropped. A transient one-sided state clears its own timer
    /// before `grace` and is never confirmed.
    static func confirmedRemovals(candidates: Set<String>, since: inout [String: Date],
                                  now: Date, grace: TimeInterval = removalGrace) -> Set<String> {
        since = since.filter { candidates.contains($0.key) }
        var confirmed = Set<String>()
        for id in candidates {
            if let first = since[id] {
                if now.timeIntervalSince(first) >= grace { confirmed.insert(id) }
            } else {
                since[id] = now
            }
        }
        return confirmed
    }

    /// Outgoing requests genuinely accepted: the counterpart's
    /// Friendship{them→me} record exists AND was created *after* the request.
    /// Both dates are CloudKit server stamps, so no device clock skew. Unfriend
    /// only deletes your own direction, so a record predating the request is a
    /// relic of a dead friendship — completing the handshake on it would
    /// auto-accept the request without the other side ever tapping Accept.
    static func acceptedOutgoing(_ outgoing: [FriendRequestItem],
                                 friendedByDates: [String: Date]) -> [FriendRequestItem] {
        outgoing.filter { request in
            guard let friendshipCreated = friendedByDates[request.toID] else { return false }
            return friendshipCreated > request.created
        }
    }

    /// My own Friendship{me→X} records that predate a fresh incoming request
    /// from X while X doesn't friend me back: relics of a dead friendship.
    /// Left alone they hide X's Accept row (X reads as "already a friend") and
    /// the pending request shields them from mirror-removal — delete them so
    /// the request can surface. A record *newer* than the request is a normal
    /// accept-in-flight (mirror not landed yet) and is kept.
    static func staleOwnFriendships(incoming: [FriendRequestItem],
                                    ownFriendDates: [String: Date],
                                    friendedBy: Set<String>) -> Set<String> {
        Set(incoming.compactMap { request in
            guard let ownCreated = ownFriendDates[request.fromID],
                  !friendedBy.contains(request.fromID),
                  ownCreated < request.created else { return nil }
            return request.fromID
        })
    }

    /// Merge optimistically-inserted incoming requests (added from a push
    /// payload before the record is queryable) into the freshly-fetched set, so
    /// a `refresh()` that runs before CloudKit is consistent doesn't drop the
    /// Accept row. Keeps an optimistic entry only while it's absent from
    /// `fetched` and younger than `grace`; once `fetched` has it, the canonical
    /// copy wins (no duplicates). Returns (merged list, ids to keep optimistic).
    static func mergedIncoming(fetched: [FriendRequestItem],
                               optimistic: [(item: FriendRequestItem, at: Date)],
                               now: Date, grace: TimeInterval = 60)
        -> (merged: [FriendRequestItem], keepIDs: Set<String>) {
        let fetchedIDs = Set(fetched.map(\.id))
        var merged = fetched
        var keep = Set<String>()
        for entry in optimistic where !fetchedIDs.contains(entry.item.id) {
            guard now.timeIntervalSince(entry.at) < grace else { continue }
            merged.append(entry.item)
            keep.insert(entry.item.id)
        }
        return (merged, keep)
    }

    /// Merge just-accepted friends into a freshly-fetched profile list, so a
    /// refresh() that beats CloudKit's query index doesn't drop them (the
    /// just-written Friendship record isn't queryable for a few seconds, and a
    /// refresh in that window would make the accepted friend vanish and the
    /// Accept row reappear). Symmetric to `mergedIncoming`. Keeps an optimistic
    /// entry only while its id is absent from `fetchedIDs` and younger than
    /// `grace`; once fetched, the canonical profile wins (no duplicates).
    /// Returns (merged profiles, ids to keep optimistic).
    static func mergedFriends(fetched: [FriendProfile],
                              optimistic: [(profile: FriendProfile, at: Date)],
                              fetchedIDs: Set<String>, now: Date, grace: TimeInterval = 60)
        -> (profiles: [FriendProfile], keepIDs: Set<String>) {
        var merged = fetched
        var keep = Set<String>()
        for entry in optimistic where !fetchedIDs.contains(entry.profile.id) {
            guard now.timeIntervalSince(entry.at) < grace,
                  !merged.contains(where: { $0.id == entry.profile.id }) else { continue }
            merged.append(entry.profile)
            keep.insert(entry.profile.id)
        }
        return (merged, keep)
    }

    /// Ignore-stamp for a request being accepted: at least the request's own
    /// (server-clock) creation date, so `isHidden` holds even when the device
    /// clock trails the server — crossing accepts happen seconds after the
    /// record is created. The stamp keeps the accepted request hidden until
    /// the sender's device deletes it, however long that takes; a genuine
    /// re-request later gets a newer creationDate and surfaces normally.
    static func acceptStamp(for request: FriendRequestItem, now: Date) -> Date {
        max(now, request.created)
    }

    /// Grace before a cached friend missing from the own-Friendship query is
    /// dropped. Own Friendship{me→X} records are only ever deleted by this
    /// device, so absence from the (eventually-consistent, non-monotonic)
    /// query is a replica blip unless we deleted it ourselves this refresh.
    /// Matches `ignoredPruneGrace`: the accepted request stays hidden through
    /// a 300s-grace mechanism, so the friend row must survive the same window
    /// or a blip shows neither row. Genuine cross-device removal of an own
    /// record (same iCloud account on two devices) reflects within this grace.
    static let friendRetentionGrace: TimeInterval = 300

    /// Cached friends missing from the fetched own-Friendship ids, retained
    /// until they've been missing continuously for `grace` (inverse of
    /// `confirmedRemovals`). `missingSince` (persisted across refreshes)
    /// tracks the first miss per id; timers self-prune when the id reappears
    /// in `fetched`, leaves `cached`, or is `excluded`. `excluded` ids were
    /// deliberately removed this refresh and must never be retained.
    static func retainedFriendIDs(fetched: Set<String>, cached: [String],
                                  excluded: Set<String>,
                                  missingSince: inout [String: Date],
                                  now: Date, grace: TimeInterval = friendRetentionGrace) -> [String] {
        let cachedSet = Set(cached)
        missingSince = missingSince.filter {
            cachedSet.contains($0.key) && !fetched.contains($0.key) && !excluded.contains($0.key)
        }
        var retained: [String] = []
        for id in cached where !fetched.contains(id) && !excluded.contains(id) {
            let first = missingSince[id] ?? now
            missingSince[id] = first
            if now.timeIntervalSince(first) < grace { retained.append(id) }
        }
        return retained
    }

    static func isExpired(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) > checkInTTL
    }

    /// Grace before a missing ignored-request entry may be pruned, covering the
    /// window where the record exists but a fetch missed it (consistency blip).
    static let ignoredPruneGrace: TimeInterval = 300

    /// True if an ignore entry hides this request: the entry exists and the
    /// request predates it. Record names are deterministic
    /// (`request-<from>-<to>`), so a later re-request reuses the ignored name —
    /// only records created up to the ignore stay hidden; anything newer is a
    /// fresh request and must surface. (`created` is a server stamp, the ignore
    /// time is device-clock — close enough for a minutes-scale comparison.)
    static func isHidden(_ request: FriendRequestItem, ignored: [String: Date]) -> Bool {
        guard let at = ignored[request.id] else { return false }
        return request.created <= at
    }

    /// Prune ignored-request entries against a fresh fetch. Keep an entry while
    /// the record it hid is still on the server (fetched and predating the
    /// ignore), or while it's within `grace` of being added — pruning a
    /// just-ignored entry on a stale fetch lets the request reappear. A fetched
    /// record *newer* than the entry is a re-request the entry never applied
    /// to: drop it immediately so nothing hides the fresh request.
    static func prunedIgnored(_ ignored: [String: Date], fetched: [FriendRequestItem],
                              now: Date, grace: TimeInterval = ignoredPruneGrace) -> [String: Date] {
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ignored.filter { id, _ in
            if let request = byID[id] { return isHidden(request, ignored: ignored) }
            return now.timeIntervalSince(ignored[id]!) < grace
        }
    }

    // MARK: Add-friend links

    /// Web bounce page (GitHub Pages) that opens the app via nycgaybars://.
    static let addFriendPage = "https://normanhoang.github.io/nyc_gay_bars_phone_app_xcode/add-friend.html"

    /// Shareable https link; the code rides in the fragment so it never
    /// appears in server logs.
    static func addFriendLink(code: String) -> URL {
        URL(string: "\(addFriendPage)#\(code)")!
    }

    /// Raw deep link that opens the app directly — offline, no web page.
    /// Used for the QR code. Inverse of `parseAddFriendURL`.
    static func addFriendDeepLink(code: String) -> URL {
        URL(string: "nycgaybars://addfriend?code=\(code)")!
    }

    /// Code from a `nycgaybars://addfriend?code=X` deep link, normalized;
    /// nil for anything else.
    static func parseAddFriendURL(_ url: URL) -> String? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.scheme == "nycgaybars",
              comps.host == "addfriend",
              let raw = comps.queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        return normalizeCode(raw)
    }
}

/// A device-local, named set of friends for bulk send/get toggling. Not synced
/// and never leaves the device.
struct FriendGroup: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var members: Set<String> = []
}

/// Per-friend notification preferences, device-local. Sparse "off" sets keyed
/// by friend ID so new friends default to both toggles on.
struct SocialPrefs: Codable, Equatable {
    /// Friends who should NOT receive my check-ins (no record addressed to them).
    var sendOff: Set<String> = []
    /// Friends whose check-ins should NOT ping me (no subscription; Tonight feed unaffected).
    var getOff: Set<String> = []
    /// Ignored friend-request record names → when ignored. The sender owns the
    /// record, so it can't be deleted — hide it until it disappears from the
    /// server. The timestamp lets a *newer* request reusing the same
    /// deterministic record name surface (re-request after ignore/unfriend);
    /// see `Social.isHidden`.
    var ignored: [String: Date] = [:]
    /// Named friend groups for bulk toggling. Device-local.
    var groups: [FriendGroup] = []

    func sendsTo(_ id: String) -> Bool { !sendOff.contains(id) }
    func getsFrom(_ id: String) -> Bool { !getOff.contains(id) }

    /// Friends who receive a shared check-in, preserving input order.
    func recipients(of friendIDs: [String]) -> [String] { friendIDs.filter(sendsTo) }
    /// Friends whose check-ins should have an alert subscription.
    func subscribed(of friendIDs: [String]) -> [String] { friendIDs.filter(getsFrom) }

    mutating func toggleSend(_ id: String) { sendOff.formSymmetricDifference([id]) }
    mutating func toggleGet(_ id: String) { getOff.formSymmetricDifference([id]) }

    /// A group sends iff every member sends; same for get. Empty group → off.
    func groupSends(_ group: FriendGroup) -> Bool {
        !group.members.isEmpty && group.members.allSatisfy(sendsTo)
    }
    func groupGets(_ group: FriendGroup) -> Bool {
        !group.members.isEmpty && group.members.allSatisfy(getsFrom)
    }

    /// Set every member's send/get to `on` uniformly (bulk group toggle).
    mutating func setSend(_ ids: Set<String>, on: Bool) {
        if on { sendOff.subtract(ids) } else { sendOff.formUnion(ids) }
    }
    mutating func setGet(_ ids: Set<String>, on: Bool) {
        if on { getOff.subtract(ids) } else { getOff.formUnion(ids) }
    }

    /// Drop entries for IDs no longer in the friends list.
    mutating func prune(keeping ids: [String]) {
        let keep = Set(ids)
        sendOff.formIntersection(keep)
        getOff.formIntersection(keep)
        for i in groups.indices { groups[i].members.formIntersection(keep) }
    }
}

extension SocialPrefs {
    private enum CodingKeys: String, CodingKey { case sendOff, getOff, ignored, groups }

    /// decodeIfPresent throughout so prefs persisted before a key existed
    /// still decode instead of resetting to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sendOff = try c.decodeIfPresent(Set<String>.self, forKey: .sendOff) ?? []
        getOff = try c.decodeIfPresent(Set<String>.self, forKey: .getOff) ?? []
        if let dated = (try? c.decodeIfPresent([String: Date].self, forKey: .ignored)) ?? nil {
            ignored = dated
        } else if let legacy = (try? c.decodeIfPresent(Set<String>.self, forKey: .ignored)) ?? nil {
            // Pre-timestamp prefs stored a bare set of record names. Stamp them
            // "now": everything they hid stays hidden, and only requests
            // created after the upgrade surface.
            ignored = Dictionary(uniqueKeysWithValues: legacy.map { ($0, Date()) })
        } else {
            ignored = [:]
        }
        groups = try c.decodeIfPresent([FriendGroup].self, forKey: .groups) ?? []
    }
}
