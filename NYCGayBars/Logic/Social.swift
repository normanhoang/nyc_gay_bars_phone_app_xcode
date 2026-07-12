import Foundation

/// Pure logic for the friends feature: invite codes, the Tonight feed window,
/// and the TTL for our own shared check-in records.
enum Social {
    /// Crockford-style alphabet: no I/L/O/0/1 so codes survive being read aloud.
    static let codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    static let codeLength = 6
    /// Friends' check-ins stay in the Tonight feed this long.
    static let tonightWindow: TimeInterval = 6 * 3600
    /// Own CheckIn records older than this are deleted from CloudKit.
    static let checkInTTL: TimeInterval = 24 * 3600
    /// Max display-name length (no server enforces it; shown in others' pushes).
    static let maxDisplayNameLength = 40

    /// Gate for the CloudKit creator-authenticity check (audit finding #1).
    /// OFF until verified against a second iCloud account — a wrong assumption
    /// about `creatorUserRecordID` here would silently drop real check-ins /
    /// requests. See FINDINGS.md "Finding #1 verification". Flip to `true`
    /// only after that test passes.
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

    /// Check-ins from the last 6h, newest first. Future-dated entries (friend
    /// clock skew) are kept. Repeated shares collapse to the newest per
    /// friend + bar (the same friend at a different bar stays a separate row).
    static func tonightFeed(_ checkIns: [FriendCheckIn], now: Date) -> [FriendCheckIn] {
        var seen = Set<String>()
        return checkIns
            .filter { $0.date > now.addingTimeInterval(-tonightWindow) }
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.authorID + "|" + $0.barId).inserted }
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

    static func isExpired(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) > checkInTTL
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
    /// Ignored friend-request record names. The sender owns the record, so it
    /// can't be deleted — hide it until it disappears from the server.
    var ignored: Set<String> = []
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
        ignored = try c.decodeIfPresent(Set<String>.self, forKey: .ignored) ?? []
        groups = try c.decodeIfPresent([FriendGroup].self, forKey: .groups) ?? []
    }
}
