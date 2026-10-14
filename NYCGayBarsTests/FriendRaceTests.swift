import XCTest
@testable import NYCGayBars

/// Races in the friend handshake / removal paths (audit 2026-10-13).
/// Pure logic only, so this file also runs under Linux XCTest.
final class FriendRaceTests: XCTestCase {
    private func outReq(to: String, created: Date) -> FriendRequestItem {
        FriendRequestItem(id: "request-me-\(to)", fromID: "me", fromName: "me", toID: to, created: created)
    }

    // MARK: Fix 1 — a lagged re-read of a finished handshake must not re-create the mirror

    func testMirrorAlreadyExistsWhenOwnRecordPostdatesRequest() {
        // The handshake already ran: my Friendship{me→a} was created after my
        // request. A stale query still returning the request must not trigger
        // another delete+recreate of the live mirror.
        let sent = Date()
        XCTAssertTrue(Social.mirrorAlreadyExists(outReq(to: "a", created: sent),
                                                 ownFriendDates: ["a": sent.addingTimeInterval(5)]))
    }

    func testMirrorNeededWhenOwnRecordIsRelic() {
        // My record predates the request (dead friendship) — re-create it so
        // its creationDate is fresh for the other side's handshake gate.
        let sent = Date()
        XCTAssertFalse(Social.mirrorAlreadyExists(outReq(to: "a", created: sent),
                                                  ownFriendDates: ["a": sent.addingTimeInterval(-3600)]))
    }

    func testMirrorNeededWhenNoOwnRecord() {
        XCTAssertFalse(Social.mirrorAlreadyExists(outReq(to: "a", created: Date()), ownFriendDates: [:]))
    }

    // MARK: Fix 2 — a just-removed friend must not come back through query lag

    func testRecentRemovalSuppressesLaggedRecord() {
        // Removed 10s ago; the own-Friendship query still returns the deleted
        // record (created long before the removal) → suppress it.
        let now = Date()
        let suppressed = Social.suppressedRemovals(["a": now.addingTimeInterval(-10)],
                                                   ownFriendDates: ["a": now.addingTimeInterval(-86400)],
                                                   now: now)
        XCTAssertEqual(suppressed, ["a"])
    }

    func testRecentRemovalSuppressesWhenRecordAlreadyGone() {
        // Query already consistent (record absent) — still suppressed, so the
        // cached-friend retention can't hold the removed friend for 300s.
        let now = Date()
        XCTAssertEqual(Social.suppressedRemovals(["a": now.addingTimeInterval(-10)],
                                                 ownFriendDates: [:], now: now), ["a"])
    }

    func testReAddAfterRemovalIsNotSuppressed() {
        // Own record newer than the removal = re-friended since; let it through.
        let now = Date()
        let suppressed = Social.suppressedRemovals(["a": now.addingTimeInterval(-30)],
                                                   ownFriendDates: ["a": now.addingTimeInterval(-5)],
                                                   now: now)
        XCTAssertTrue(suppressed.isEmpty)
    }

    func testRemovalSuppressionExpiresAfterGrace() {
        let now = Date()
        XCTAssertTrue(Social.suppressedRemovals(["a": now.addingTimeInterval(-301)],
                                                ownFriendDates: [:], now: now, grace: 300).isEmpty)
    }

    func testSuppressedRemovalIsNotRetained() {
        // Field sequence: remove a, then a refresh whose query no longer has
        // the record. Before the fix `a` was still cached (resurrected by an
        // in-flight refresh) and retainedFriendIDs kept it for 300s.
        let now = Date()
        let suppressed = Social.suppressedRemovals(["a": now.addingTimeInterval(-10)],
                                                   ownFriendDates: [:], now: now)
        var since: [String: Date] = [:]
        let retained = Social.retainedFriendIDs(fetched: [], cached: ["a"], excluded: suppressed,
                                                missingSince: &since, now: now)
        XCTAssertTrue(retained.isEmpty)
    }

    // MARK: Fix 3 — re-sending a request must replace an ignored one, unless already accepted

    func testRequestAlreadyAcceptedWhenTheirFriendshipIsNewer() {
        let sent = Date()
        XCTAssertTrue(Social.requestAlreadyAccepted(requestCreated: sent,
                                                    friendshipCreated: sent.addingTimeInterval(5)))
    }

    func testRequestNotAcceptedWhenTheirFriendshipIsRelic() {
        let sent = Date()
        XCTAssertFalse(Social.requestAlreadyAccepted(requestCreated: sent,
                                                     friendshipCreated: sent.addingTimeInterval(-3600)))
    }

    func testRequestNotAcceptedWithoutRequestOrFriendship() {
        XCTAssertFalse(Social.requestAlreadyAccepted(requestCreated: nil, friendshipCreated: Date()))
        XCTAssertFalse(Social.requestAlreadyAccepted(requestCreated: Date(), friendshipCreated: nil))
    }

    func testReplacedRequestSurfacesPastIgnore() {
        // The point of replacing: a re-created record gets a creationDate after
        // the ignore stamp, so isHidden lets it through. The old record kept
        // its original date and stayed hidden forever.
        let ignoredAt = Date()
        let old = FriendRequestItem(id: "request-a-me", fromID: "a", fromName: "A", toID: "me",
                                    created: ignoredAt.addingTimeInterval(-60))
        let replaced = FriendRequestItem(id: "request-a-me", fromID: "a", fromName: "A", toID: "me",
                                         created: ignoredAt.addingTimeInterval(60))
        let ignored = ["request-a-me": ignoredAt]
        XCTAssertTrue(Social.isHidden(old, ignored: ignored))
        XCTAssertFalse(Social.isHidden(replaced, ignored: ignored))
    }
}
