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

    // MARK: Optimistic incoming-request merge

    private func req(_ id: String, from: String, created: Date = Date()) -> FriendRequestItem {
        FriendRequestItem(id: id, fromID: from, fromName: from, toID: "me", created: created)
    }

    func testMergedIncomingKeepsOptimisticUntilFetched() {
        let now = Date()
        let opt = [(item: req("r1", from: "a"), at: now)]
        let (merged, keep) = Social.mergedIncoming(fetched: [], optimistic: opt, now: now, grace: 60)
        XCTAssertEqual(merged.map(\.id), ["r1"])
        XCTAssertEqual(keep, ["r1"])
    }

    func testMergedIncomingDropsOptimisticOnceFetchedHasIt() {
        let now = Date()
        let opt = [(item: req("r1", from: "a"), at: now)]
        let (merged, keep) = Social.mergedIncoming(fetched: [req("r1", from: "a")], optimistic: opt, now: now, grace: 60)
        XCTAssertEqual(merged.map(\.id), ["r1"])   // no duplicate
        XCTAssertTrue(keep.isEmpty)                // canonical took over
    }

    func testMergedIncomingDropsStaleOptimistic() {
        let now = Date()
        let opt = [(item: req("r1", from: "a"), at: now.addingTimeInterval(-61))]
        let (merged, keep) = Social.mergedIncoming(fetched: [], optimistic: opt, now: now, grace: 60)
        XCTAssertTrue(merged.isEmpty)
        XCTAssertTrue(keep.isEmpty)
    }

    // MARK: Removal debounce (consistency-window guard)

    func testConfirmedRemovalsNotOnFirstSighting() {
        // A candidate seen for the first time starts a timer, isn't confirmed.
        var since: [String: Date] = [:]
        let now = Date()
        let confirmed = Social.confirmedRemovals(candidates: ["a"], since: &since, now: now, grace: 60)
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertNotNil(since["a"])
    }

    func testConfirmedRemovalsAfterGrace() {
        // Still a candidate after the grace elapses → confirmed.
        let start = Date()
        var since: [String: Date] = ["a": start]
        let confirmed = Social.confirmedRemovals(candidates: ["a"], since: &since,
                                                 now: start.addingTimeInterval(61), grace: 60)
        XCTAssertEqual(confirmed, ["a"])
    }

    func testConfirmedRemovalsClearsWhenNoLongerCandidate() {
        // A transient blip (reverse reappears) clears the timer, never confirms.
        let start = Date()
        var since: [String: Date] = ["a": start]
        // 'a' is no longer a candidate this pass (mirror became visible).
        let confirmed = Social.confirmedRemovals(candidates: [], since: &since,
                                                 now: start.addingTimeInterval(61), grace: 60)
        XCTAssertTrue(confirmed.isEmpty)
        XCTAssertNil(since["a"])   // timer dropped, so a later sighting restarts grace
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

    // MARK: Optimistic accepted-friends overlay

    private func profile(_ id: String) -> FriendProfile {
        FriendProfile(id: id, displayName: id, code: "")
    }

    func testMergedFriendsKeepsOptimisticUntilFetched() {
        let now = Date()
        let (profiles, keep) = Social.mergedFriends(
            fetched: [profile("old")],
            optimistic: [(profile("new"), now.addingTimeInterval(-5))],
            fetchedIDs: ["old"], now: now, grace: 60)
        XCTAssertEqual(Set(profiles.map(\.id)), ["old", "new"])
        XCTAssertEqual(keep, ["new"])
    }

    func testMergedFriendsCanonicalTakesOverWithoutDuplicate() {
        let now = Date()
        let canonical = FriendProfile(id: "new", displayName: "Real Name", code: "ABC234")
        let (profiles, keep) = Social.mergedFriends(
            fetched: [canonical],
            optimistic: [(profile("new"), now.addingTimeInterval(-5))],
            fetchedIDs: ["new"], now: now, grace: 60)
        XCTAssertEqual(profiles, [canonical])   // one copy, the canonical one
        XCTAssertTrue(keep.isEmpty)
    }

    func testMergedFriendsDropsExpiredOptimistic() {
        let now = Date()
        let (profiles, keep) = Social.mergedFriends(
            fetched: [],
            optimistic: [(profile("new"), now.addingTimeInterval(-61))],
            fetchedIDs: [], now: now, grace: 60)
        XCTAssertTrue(profiles.isEmpty)
        XCTAssertTrue(keep.isEmpty)
    }

    func testMergedFriendsPassthroughWithoutOptimistic() {
        let (profiles, keep) = Social.mergedFriends(
            fetched: [profile("a"), profile("b")],
            optimistic: [], fetchedIDs: ["a", "b"], now: Date(), grace: 60)
        XCTAssertEqual(profiles.map(\.id), ["a", "b"])
        XCTAssertTrue(keep.isEmpty)
    }

    // MARK: Handshake acceptance gate (stale Friendship records)

    private func outReq(_ id: String, to: String, created: Date) -> FriendRequestItem {
        FriendRequestItem(id: id, fromID: "me", fromName: "me", toID: to, created: created)
    }

    func testAcceptedOutgoingAcceptsFriendshipNewerThanRequest() {
        let sent = Date()
        let requests = [outReq("r1", to: "a", created: sent)]
        let accepted = Social.acceptedOutgoing(requests,
                                               friendedByDates: ["a": sent.addingTimeInterval(5)])
        XCTAssertEqual(accepted.map(\.id), ["r1"])
    }

    func testAcceptedOutgoingIgnoresStaleFriendship() {
        // Their Friendship{them→me} predates my request: a relic of a dead
        // friendship, not an acceptance — completing it auto-accepts.
        let sent = Date()
        let requests = [outReq("r1", to: "a", created: sent)]
        let accepted = Social.acceptedOutgoing(requests,
                                               friendedByDates: ["a": sent.addingTimeInterval(-3600)])
        XCTAssertTrue(accepted.isEmpty)
    }

    func testAcceptedOutgoingIgnoresMissingFriendship() {
        let accepted = Social.acceptedOutgoing([outReq("r1", to: "a", created: Date())],
                                               friendedByDates: [:])
        XCTAssertTrue(accepted.isEmpty)
    }

    func testStaleOwnFriendshipsDetectsRelic() {
        // My Friendship{me→a} predates a's fresh request and a doesn't friend
        // me back: delete it so the Accept row can surface.
        let now = Date()
        let stale = Social.staleOwnFriendships(
            incoming: [req("r1", from: "a", created: now)],
            ownFriendDates: ["a": now.addingTimeInterval(-3600)],
            friendedBy: [])
        XCTAssertEqual(stale, ["a"])
    }

    func testStaleOwnFriendshipsKeepsMutualFriend() {
        // a friends me back → the incoming request is the stale thing, not my record.
        let now = Date()
        let stale = Social.staleOwnFriendships(
            incoming: [req("r1", from: "a", created: now)],
            ownFriendDates: ["a": now.addingTimeInterval(-3600)],
            friendedBy: ["a"])
        XCTAssertTrue(stale.isEmpty)
    }

    func testStaleOwnFriendshipsKeepsAcceptInFlight() {
        // I just accepted a's request (my record is newer than it); the mirror
        // hasn't landed yet — normal handshake window, not a relic.
        let now = Date()
        let stale = Social.staleOwnFriendships(
            incoming: [req("r1", from: "a", created: now.addingTimeInterval(-10))],
            ownFriendDates: ["a": now],
            friendedBy: [])
        XCTAssertTrue(stale.isEmpty)
    }

    func testStaleOwnFriendshipsIgnoresNonFriendRequesters() {
        let stale = Social.staleOwnFriendships(
            incoming: [req("r1", from: "stranger", created: Date())],
            ownFriendDates: [:],
            friendedBy: [])
        XCTAssertTrue(stale.isEmpty)
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
        p.ignored["request-x-y"] = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let back = try JSONDecoder().decode(SocialPrefs.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testPrefsDecodeWithoutIgnoredKey() throws {
        // Prefs persisted before the ignored set existed must still decode.
        let legacy = #"{"sendOff":["a"],"getOff":[]}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(SocialPrefs.self, from: legacy)
        XCTAssertEqual(p.sendOff, ["a"])
        XCTAssertTrue(p.ignored.isEmpty)
        XCTAssertTrue(p.groups.isEmpty)
    }

    func testPrefsDecodeLegacyIgnoredArray() throws {
        // Pre-timestamp prefs stored ignored as a bare array of record names;
        // they must decode and keep hiding the requests they hid before
        // (stamped "now", so only records created later surface).
        let legacy = #"{"sendOff":[],"getOff":[],"ignored":["request-a-me"]}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(SocialPrefs.self, from: legacy)
        let at = try XCTUnwrap(p.ignored["request-a-me"])
        XCTAssertLessThan(abs(at.timeIntervalSinceNow), 5)
        XCTAssertTrue(Social.isHidden(req("request-a-me", from: "a",
                                          created: at.addingTimeInterval(-3600)),
                                      ignored: p.ignored))
    }

    // MARK: Friend groups

    func testGroupSendGetAggregate() {
        var p = SocialPrefs()
        let g = FriendGroup(name: "Close", members: ["a", "b"])
        p.groups = [g]
        XCTAssertTrue(p.groupSends(g))          // all default on
        XCTAssertTrue(p.groupGets(g))
        p.toggleSend("a")                       // one member off → group off
        XCTAssertFalse(p.groupSends(p.groups[0]))
    }

    func testEmptyGroupIsOff() {
        let p = SocialPrefs()
        XCTAssertFalse(p.groupSends(FriendGroup(name: "Empty")))
        XCTAssertFalse(p.groupGets(FriendGroup(name: "Empty")))
    }

    func testGroupBulkSetSendGet() {
        var p = SocialPrefs()
        let ids: Set<String> = ["a", "b", "c"]
        p.setSend(ids, on: false)
        XCTAssertEqual(p.recipients(of: ["a", "b", "c", "d"]), ["d"])
        p.setSend(["a", "b"], on: true)
        XCTAssertEqual(Set(p.recipients(of: ["a", "b", "c"])), ["a", "b"])
        p.setGet(ids, on: false)
        XCTAssertEqual(p.subscribed(of: ["a", "b", "c", "d"]), ["d"])
    }

    func testPrunePrunesGroupMembers() {
        var p = SocialPrefs()
        p.groups = [FriendGroup(name: "G", members: ["kept", "gone"])]
        p.prune(keeping: ["kept"])
        XCTAssertEqual(p.groups[0].members, ["kept"])
    }

    func testGroupsCodableRoundTrip() throws {
        var p = SocialPrefs()
        p.groups = [FriendGroup(id: "g1", name: "Close", members: ["a", "b"])]
        let back = try JSONDecoder().decode(SocialPrefs.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    // MARK: 24h TTL for own check-in records

    func testIsExpired() {
        let now = Date()
        XCTAssertTrue(Social.isExpired(now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertFalse(Social.isExpired(now.addingTimeInterval(-23 * 3600), now: now))
    }

    // MARK: Ignored-request hiding + pruning

    func testIsHiddenOnlyForRequestsPredatingIgnore() {
        let at = Date()
        let ignored = ["r1": at]
        // The record that was ignored (created before the ignore) stays hidden.
        XCTAssertTrue(Social.isHidden(req("r1", from: "a", created: at.addingTimeInterval(-60)),
                                      ignored: ignored))
        // Same deterministic record name but created after the ignore: a fresh
        // re-request — must surface.
        XCTAssertFalse(Social.isHidden(req("r1", from: "a", created: at.addingTimeInterval(60)),
                                       ignored: ignored))
        // No entry at all → visible.
        XCTAssertFalse(Social.isHidden(req("r2", from: "b", created: at), ignored: ignored))
    }

    func testPrunedIgnoredKeepsFetchedAndRecentEntries() {
        let now = Date()
        let ignored = ["on-server": now.addingTimeInterval(-3600),
                       "just-ignored": now.addingTimeInterval(-5),
                       "long-gone": now.addingTimeInterval(-3600)]
        let pruned = Social.prunedIgnored(
            ignored,
            fetched: [req("on-server", from: "a", created: now.addingTimeInterval(-7200))],
            now: now)
        // Old record still on server → kept; ignored seconds ago but missing
        // from a possibly-stale fetch → kept; absent and past grace → dropped.
        XCTAssertEqual(Set(pruned.keys), ["on-server", "just-ignored"])
    }

    func testPrunedIgnoredDropsUnknownStaleEntries() {
        let pruned = Social.prunedIgnored(["a": Date.distantPast, "b": Date.distantPast],
                                          fetched: [], now: Date())
        XCTAssertTrue(pruned.isEmpty)
    }

    func testPrunedIgnoredDropsEntryWhenFetchedRequestIsNewer() {
        // The fetched record postdates the ignore: it's a re-request the entry
        // no longer applies to — drop immediately, even inside the grace.
        let now = Date()
        let pruned = Social.prunedIgnored(
            ["r1": now.addingTimeInterval(-5)],
            fetched: [req("r1", from: "a", created: now)],
            now: now)
        XCTAssertTrue(pruned.isEmpty)
    }
}
