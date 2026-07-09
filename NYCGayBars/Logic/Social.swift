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
}
