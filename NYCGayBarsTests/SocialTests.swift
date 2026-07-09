import XCTest
@testable import NYCGayBars

final class SocialTests: XCTestCase {
    private func checkIn(_ author: String, _ bar: String, minutesAgo: Double, now: Date) -> FriendCheckIn {
        FriendCheckIn(id: UUID().uuidString, authorID: author, authorName: author,
                      barId: bar, barName: bar, date: now.addingTimeInterval(-minutesAgo * 60))
    }

    // MARK: Friend codes

    func testGenerateFriendCodeShape() {
        let code = Social.generateFriendCode()
        XCTAssertEqual(code.count, Social.codeLength)
        XCTAssertTrue(code.allSatisfy { Social.codeAlphabet.contains($0) })
    }

    func testGenerateFriendCodeVaries() {
        XCTAssertNotEqual(Social.generateFriendCode(), Social.generateFriendCode())
    }

    func testNormalizeCodeAcceptsValid() {
        XCTAssertEqual(Social.normalizeCode(" qrs234 "), "QRS234")
        XCTAssertEqual(Social.normalizeCode("ABCDEF"), "ABCDEF")
    }

    func testNormalizeCodeRejectsInvalid() {
        XCTAssertNil(Social.normalizeCode(""))
        XCTAssertNil(Social.normalizeCode("QRS23"))      // too short
        XCTAssertNil(Social.normalizeCode("QRS2345"))    // too long
        XCTAssertNil(Social.normalizeCode("QRS10O"))     // ambiguous chars excluded from alphabet
        XCTAssertNil(Social.normalizeCode("QR S23"))     // inner whitespace
    }

    func testGeneratedCodeRoundTripsNormalize() {
        let code = Social.generateFriendCode()
        XCTAssertEqual(Social.normalizeCode(code.lowercased()), code)
    }

    // MARK: Tonight feed (6h window, newest first)

    func testTonightFeedFiltersAndSorts() {
        let now = Date()
        let recent = checkIn("a", "bar1", minutesAgo: 60, now: now)
        let edge = checkIn("b", "bar2", minutesAgo: 359, now: now)
        let stale = checkIn("c", "bar3", minutesAgo: 60 * 7, now: now)
        let feed = Social.tonightFeed([stale, recent, edge], now: now)
        XCTAssertEqual(feed.map(\.id), [recent.id, edge.id])
    }

    func testTonightFeedEmpty() {
        XCTAssertTrue(Social.tonightFeed([], now: Date()).isEmpty)
    }

    func testTonightFeedDropsFutureClockSkewKeeps() {
        // A friend's clock slightly ahead should still show.
        let now = Date()
        let ahead = checkIn("a", "bar1", minutesAgo: -2, now: now)
        XCTAssertEqual(Social.tonightFeed([ahead], now: now).count, 1)
    }

    // MARK: 24h TTL for own check-in records

    func testIsExpired() {
        let now = Date()
        XCTAssertTrue(Social.isExpired(now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertFalse(Social.isExpired(now.addingTimeInterval(-23 * 3600), now: now))
    }
}
