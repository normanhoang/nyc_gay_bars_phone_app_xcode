import Foundation

/// Local-day identity helpers. A "day" follows the user's calendar. Mirrors the
/// RN lib/VisitsContext.tsx dayKey helpers exactly — including the 0-indexed
/// month in the key string — so stored visits round-trip identically.
enum DayKey {
    private static var calendar: Calendar { Calendar.current }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse a stored ISO date-time into an instant.
    static func parseISO(_ iso: String) -> Date {
        isoFormatter.date(from: iso) ?? isoFormatterNoFraction.date(from: iso) ?? Date()
    }

    /// Produce an ISO date-time string (matches JS Date.toISOString format).
    static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Local day identifier "YYYY-M-D" (month 0-indexed, like JS getMonth()).
    static func key(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month! - 1)-\(c.day!)"
    }

    /// Day key for a stored visit's ISO date string.
    static func key(iso: String) -> String { key(parseISO(iso)) }

    /// Noon local time on the given day, so the ISO string round-trips the key.
    static func toDate(_ key: String) -> Date {
        let parts = key.split(separator: "-").map { Int($0) ?? 0 }
        var c = DateComponents()
        c.year = parts.count > 0 ? parts[0] : 1970
        c.month = (parts.count > 1 ? parts[1] : 0) + 1
        c.day = parts.count > 2 ? parts[2] : 1
        c.hour = 12
        return calendar.date(from: c) ?? Date()
    }

    /// Human-readable form, e.g. "Tuesday, June 9, 2026".
    static func format(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: toDate(key))
    }

    /// True when the day key is after today.
    static func isFuture(_ key: String) -> Bool {
        toDate(key).timeIntervalSince1970 > toDate(self.key()).timeIntervalSince1970
    }

    /// Unique id for a new visit (timestamp + random suffix).
    static func makeId() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
        return "\(ms)-\(suffix)"
    }
}
