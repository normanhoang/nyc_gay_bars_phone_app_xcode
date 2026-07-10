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

    static func generateFriendCode() -> String {
        String((0..<codeLength).map { _ in codeAlphabet.randomElement()! })
    }

    /// Trimmed, uppercased code if it's exactly `codeLength` chars of the alphabet; nil otherwise.
    static func normalizeCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == codeLength, code.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return code
    }

    /// Check-ins from the last 6h, newest first. Future-dated entries (friend clock skew) are kept.
    static func tonightFeed(_ checkIns: [FriendCheckIn], now: Date) -> [FriendCheckIn] {
        checkIns
            .filter { $0.date > now.addingTimeInterval(-tonightWindow) }
            .sorted { $0.date > $1.date }
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

/// Per-friend notification preferences, device-local. Sparse "off" sets keyed
/// by friend ID so new friends default to both toggles on.
struct SocialPrefs: Codable, Equatable {
    /// Friends who should NOT receive my check-ins (no record addressed to them).
    var sendOff: Set<String> = []
    /// Friends whose check-ins should NOT ping me (no subscription; Tonight feed unaffected).
    var getOff: Set<String> = []

    func sendsTo(_ id: String) -> Bool { !sendOff.contains(id) }
    func getsFrom(_ id: String) -> Bool { !getOff.contains(id) }

    /// Friends who receive a shared check-in, preserving input order.
    func recipients(of friendIDs: [String]) -> [String] { friendIDs.filter(sendsTo) }
    /// Friends whose check-ins should have an alert subscription.
    func subscribed(of friendIDs: [String]) -> [String] { friendIDs.filter(getsFrom) }

    mutating func toggleSend(_ id: String) { sendOff.formSymmetricDifference([id]) }
    mutating func toggleGet(_ id: String) { getOff.formSymmetricDifference([id]) }

    /// Drop entries for IDs no longer in the friends list.
    mutating func prune(keeping ids: [String]) {
        sendOff.formIntersection(ids)
        getOff.formIntersection(ids)
    }
}
