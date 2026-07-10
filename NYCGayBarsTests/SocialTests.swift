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

    func testTonightFeedDedupesRepeatSharesKeepingNewest() {
        let now = Date()
        let older = checkIn("a", "bar1", minutesAgo: 90, now: now)
        let newer = checkIn("a", "bar1", minutesAgo: 10, now: now)
        let feed = Social.tonightFeed([older, newer], now: now)
        XCTAssertEqual(feed.map(\.id), [newer.id])
    }

    func testTonightFeedKeepsSameFriendAtDifferentBars() {
        let now = Date()
        let bar1 = checkIn("a", "bar1", minutesAgo: 90, now: now)
        let bar2 = checkIn("a", "bar2", minutesAgo: 10, now: now)
        XCTAssertEqual(Social.tonightFeed([bar1, bar2], now: now).map(\.id), [bar2.id, bar1.id])
    }

    // MARK: Mirror removal (unfriend seen from the other side)

    func testRemovedFriendIDsDetectsRemoval() {
        let removed = Social.removedFriendIDs(friends: ["a", "b"], friendedBy: ["b"],
                                              pendingIn: [], pendingOut: [])
        XCTAssertEqual(removed, ["a"])
    }

    func testRemovedFriendIDsMutualFriendsUntouched() {
        XCTAssertTrue(Social.removedFriendIDs(friends: ["a", "b"], friendedBy: ["a", "b"],
                                              pendingIn: [], pendingOut: []).isEmpty)
    }

    func testRemovedFriendIDsSkipsHandshakeWindow() {
        // I just accepted a's request (their request record still exists) —
        // a's mirror is missing but this is not a removal.
        XCTAssertTrue(Social.removedFriendIDs(friends: ["a"], friendedBy: [],
                                              pendingIn: ["a"], pendingOut: []).isEmpty)
        // Same for an outgoing request that hasn't fully settled.
        XCTAssertTrue(Social.removedFriendIDs(friends: ["a"], friendedBy: [],
                                              pendingIn: [], pendingOut: ["a"]).isEmpty)
    }

    // MARK: Add-friend links

    func testAddFriendLinkEmbedsCodeInFragment() {
        let url = Social.addFriendLink(code: "QRS234")
        XCTAssertEqual(url.absoluteString,
                       "https://normanhoang.github.io/nyc_gay_bars_phone_app_xcode/add-friend.html#QRS234")
    }

    func testDeepLinkRoundTrips() {
        let url = Social.addFriendDeepLink(code: "QRS234")
        XCTAssertEqual(url.scheme, "nycgaybars")
        XCTAssertEqual(Social.parseAddFriendURL(url), "QRS234")
    }

    func testParseAddFriendURLAccepts() {
        XCTAssertEqual(Social.parseAddFriendURL(URL(string: "nycgaybars://addfriend?code=QRS234")!), "QRS234")
        // Normalizes case like manual entry does.
        XCTAssertEqual(Social.parseAddFriendURL(URL(string: "nycgaybars://addfriend?code=qrs234")!), "QRS234")
    }

    func testParseAddFriendURLRejects() {
        XCTAssertNil(Social.parseAddFriendURL(URL(string: "https://example.com/addfriend?code=QRS234")!))
        XCTAssertNil(Social.parseAddFriendURL(URL(string: "nycgaybars://other?code=QRS234")!))
        XCTAssertNil(Social.parseAddFriendURL(URL(string: "nycgaybars://addfriend")!))
        XCTAssertNil(Social.parseAddFriendURL(URL(string: "nycgaybars://addfriend?code=BAD")!))
    }

    // MARK: Per-friend notification prefs

    func testPrefsDefaultOn() {
        let p = SocialPrefs()
        XCTAssertTrue(p.sendsTo("a"))
        XCTAssertTrue(p.getsFrom("a"))
        XCTAssertEqual(p.recipients(of: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(p.subscribed(of: ["a", "b"]), ["a", "b"])
    }

    func testPrefsToggle() {
        var p = SocialPrefs()
        p.toggleSend("a")
        p.toggleGet("b")
        XCTAssertFalse(p.sendsTo("a"))
        XCTAssertTrue(p.getsFrom("a"))
        XCTAssertFalse(p.getsFrom("b"))
        XCTAssertEqual(p.recipients(of: ["a", "b"]), ["b"])
        XCTAssertEqual(p.subscribed(of: ["a", "b"]), ["a"])
        p.toggleSend("a")
        XCTAssertTrue(p.sendsTo("a"))
    }

    func testPrefsPrune() {
        var p = SocialPrefs()
        p.toggleSend("gone")
        p.toggleGet("gone")
        p.toggleGet("kept")
        p.prune(keeping: ["kept"])
        XCTAssertTrue(p.sendOff.isEmpty)
        XCTAssertEqual(p.getOff, ["kept"])
    }

    func testPrefsCodableRoundTrip() throws {
        var p = SocialPrefs()
        p.toggleSend("a")
        p.toggleGet("b")
        p.ignored.insert("request-x-y")
        let back = try JSONDecoder().decode(SocialPrefs.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testPrefsDecodeWithoutIgnoredKey() throws {
        // Prefs persisted before the ignored set existed must still decode.
        let legacy = #"{"sendOff":["a"],"getOff":[]}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(SocialPrefs.self, from: legacy)
        XCTAssertEqual(p.sendOff, ["a"])
        XCTAssertTrue(p.ignored.isEmpty)
    }

    // MARK: 24h TTL for own check-in records

    func testIsExpired() {
        let now = Date()
        XCTAssertTrue(Social.isExpired(now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertFalse(Social.isExpired(now.addingTimeInterval(-23 * 3600), now: now))
    }
}
