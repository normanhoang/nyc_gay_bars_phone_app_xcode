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

    // MARK: Own check-in (self-addressed copy, removal tombstones)

    func testIsSameCheckInMatchesWithinWindow() {
        let ts = Date()
        XCTAssertTrue(Social.isSameCheckIn(ts, ts))
        XCTAssertTrue(Social.isSameCheckIn(ts, ts.addingTimeInterval(0.5)))
        XCTAssertTrue(Social.isSameCheckIn(ts, ts.addingTimeInterval(-Social.checkInMatchWindow)))
        XCTAssertFalse(Social.isSameCheckIn(ts, ts.addingTimeInterval(2)))
    }

    func testWithoutTombstonedDropsOwnRemovedCheckIn() {
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 5, now: now)
        let friend = checkIn("a", "bar2", minutesAgo: 5, now: now)
        let tombstones = [Social.CheckInTombstone(ts: mine.date, at: now)]
        let kept = Social.withoutTombstoned([mine, friend], me: "me", tombstones: tombstones)
        XCTAssertEqual(kept.map(\.id), [friend.id])
    }

    func testWithoutTombstonedKeepsFriendWithMatchingStamp() {
        // A friend sharing at the same instant must not be filtered out by my
        // own removal — only my records are ever tombstoned.
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 5, now: now)
        let friend = checkIn("a", "bar1", minutesAgo: 5, now: now)
        let kept = Social.withoutTombstoned([mine, friend], me: "me",
                                            tombstones: [.init(ts: mine.date, at: now)])
        XCTAssertEqual(kept.map(\.id), [friend.id])
    }

    func testWithoutTombstonedKeepsMyOtherCheckIn() {
        // Bar hopping: removing one own check-in leaves the other standing.
        let now = Date()
        let removed = checkIn("me", "bar1", minutesAgo: 50, now: now)
        let current = checkIn("me", "bar2", minutesAgo: 5, now: now)
        let kept = Social.withoutTombstoned([removed, current], me: "me",
                                            tombstones: [.init(ts: removed.date, at: now)])
        XCTAssertEqual(kept.map(\.id), [current.id])
    }

    func testFanOutMatchesRetainedShare() {
        // The feed row's date round-trips through CloudKit as a Double, so the
        // lookup matches on the same ±window as the delete-by-timestamp path.
        let ts = Date()
        let fanOut = Social.CheckInFanOut(ts: ts, recordNames: ["a", "b"])
        XCTAssertEqual(Social.fanOut(matching: ts, in: [fanOut]), fanOut)
        XCTAssertEqual(Social.fanOut(matching: ts.addingTimeInterval(0.5), in: [fanOut]), fanOut)
        XCTAssertNil(Social.fanOut(matching: ts.addingTimeInterval(2), in: [fanOut]))
        XCTAssertNil(Social.fanOut(matching: ts, in: []))
    }

    func testFanOutPicksTheMatchingShare() {
        // Bar hopping: two fan-outs held at once, each removable on its own.
        let now = Date()
        let earlier = Social.CheckInFanOut(ts: now.addingTimeInterval(-3600), recordNames: ["old"])
        let latest = Social.CheckInFanOut(ts: now, recordNames: ["new"])
        XCTAssertEqual(Social.fanOut(matching: now, in: [earlier, latest]), latest)
        XCTAssertEqual(Social.fanOut(matching: earlier.ts, in: [earlier, latest]), earlier)
    }

    func testPrunedFanOutsDropsPastTTL() {
        let now = Date()
        let live = Social.CheckInFanOut(ts: now.addingTimeInterval(-3600), recordNames: ["a"])
        let expired = Social.CheckInFanOut(
            ts: now.addingTimeInterval(-Social.checkInTTL - 1), recordNames: ["b"])
        XCTAssertEqual(Social.prunedFanOuts([live, expired], now: now), [live])
    }

    func testPrunedTombstonesDropsAfterGrace() {
        let now = Date()
        let fresh = Social.CheckInTombstone(ts: now, at: now.addingTimeInterval(-10))
        let stale = Social.CheckInTombstone(
            ts: now, at: now.addingTimeInterval(-Social.checkInTombstoneGrace - 1))
        XCTAssertEqual(Social.prunedTombstones([fresh, stale], now: now), [fresh])
    }

    func testMergedOwnCheckInsShowsJustSharedRow() {
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 0, now: now)
        let friend = checkIn("a", "bar2", minutesAgo: 5, now: now)
        let (merged, keep) = Social.mergedOwnCheckIns(
            fetched: [friend], optimistic: [(mine, now)], now: now)
        XCTAssertEqual(Set(merged.map(\.id)), [friend.id, mine.id])
        XCTAssertEqual(keep, [mine.id])
    }

    func testMergedOwnCheckInsCanonicalTakesOverWithoutDuplicate() {
        // Same fan-out read back from CloudKit: server record name differs, the
        // stamp doesn't. The optimistic row must drop out, not double up.
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 0, now: now)
        let canonical = FriendCheckIn(id: "ck-server", authorID: "me", authorName: "me",
                                      barId: "bar1", barName: "bar1", date: mine.date)
        let (merged, keep) = Social.mergedOwnCheckIns(
            fetched: [canonical], optimistic: [(mine, now)], now: now)
        XCTAssertEqual(merged.map(\.id), [canonical.id])
        XCTAssertTrue(keep.isEmpty)
    }

    func testMergedOwnCheckInsKeepsRowForADifferentBar() {
        // Bar hop before the first record is queryable: the earlier row is a
        // different author|bar pair and must not be treated as landed.
        let now = Date()
        let earlier = checkIn("me", "bar1", minutesAgo: 20, now: now)
        let fresh = checkIn("me", "bar2", minutesAgo: 0, now: now)
        let (merged, _) = Social.mergedOwnCheckIns(
            fetched: [earlier], optimistic: [(fresh, now)], now: now)
        XCTAssertEqual(Set(merged.map(\.barId)), ["bar1", "bar2"])
    }

    func testMergedOwnCheckInsDropsExpiredOptimistic() {
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 5, now: now)
        let (merged, keep) = Social.mergedOwnCheckIns(
            fetched: [], optimistic: [(mine, now.addingTimeInterval(-61))], now: now)
        XCTAssertTrue(merged.isEmpty)
        XCTAssertTrue(keep.isEmpty)
    }

    func testFriendsOnlyExcludesMe() {
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 5, now: now)
        let friend = checkIn("a", "bar2", minutesAgo: 5, now: now)
        XCTAssertEqual(Social.friendsOnly([mine, friend], me: "me").map(\.id), [friend.id])
        // Not onboarded / unknown id: nothing to exclude.
        XCTAssertEqual(Social.friendsOnly([mine, friend], me: nil).count, 2)
    }

    func testTonightFeedKeepsOwnRowAlongsideFriends() {
        let now = Date()
        let mine = checkIn("me", "bar1", minutesAgo: 2, now: now)
        let friend = checkIn("a", "bar2", minutesAgo: 20, now: now)
        XCTAssertEqual(Social.tonightFeed([friend, mine], now: now).map(\.id), [mine.id, friend.id])
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

    // MARK: Accepted-request stamp + friend retention (toggle bug)

    func testAcceptStampHidesRequestDespiteClockSkew() {
        // Crossing accept with the device clock trailing the server: the
        // request's server creationDate is "ahead" of now. The stamp must
        // still hide it, and the entry must survive pruning while the record
        // stays on the server.
        let now = Date()
        let request = req("r1", from: "a", created: now.addingTimeInterval(30))
        let stamp = Social.acceptStamp(for: request, now: now)
        let ignored = ["r1": stamp]
        XCTAssertTrue(Social.isHidden(request, ignored: ignored))
        XCTAssertEqual(Set(Social.prunedIgnored(ignored, fetched: [request], now: now).keys), ["r1"])
    }

    func testRetainedFriendIDsRetainsMissingWithinGrace() {
        var since: [String: Date] = [:]
        let retained = Social.retainedFriendIDs(fetched: ["b"], cached: ["a", "b"],
                                                excluded: [], missingSince: &since,
                                                now: Date(), grace: 300)
        XCTAssertEqual(retained, ["a"])
        XCTAssertNotNil(since["a"])   // timer started on first miss
    }

    func testRetainedFriendIDsDropsAfterGrace() {
        // Missing continuously past the grace → genuinely gone, stop retaining.
        let start = Date()
        var since = ["a": start]
        let retained = Social.retainedFriendIDs(fetched: [], cached: ["a"],
                                                excluded: [], missingSince: &since,
                                                now: start.addingTimeInterval(301), grace: 300)
        XCTAssertTrue(retained.isEmpty)
    }

    func testRetainedFriendIDsClearsTimerWhenFetched() {
        // The id came back in a fetch: the blip is over, so a later miss
        // restarts the grace from scratch.
        var since = ["a": Date.distantPast]
        let retained = Social.retainedFriendIDs(fetched: ["a"], cached: ["a"],
                                                excluded: [], missingSince: &since,
                                                now: Date(), grace: 300)
        XCTAssertTrue(retained.isEmpty)   // fetched ids need no retaining
        XCTAssertNil(since["a"])
    }

    func testRetainedFriendIDsExcludesDeliberateRemovals() {
        // An id removed on purpose this refresh must not be retained or timed.
        var since: [String: Date] = [:]
        let retained = Social.retainedFriendIDs(fetched: [], cached: ["a"],
                                                excluded: ["a"], missingSince: &since,
                                                now: Date(), grace: 300)
        XCTAssertTrue(retained.isEmpty)
        XCTAssertNil(since["a"])
    }

    func testRetainedFriendIDsPrunesNonCachedTimers() {
        // A timer for someone no longer in the friends list is dead weight.
        var since = ["gone": Date.distantPast]
        _ = Social.retainedFriendIDs(fetched: [], cached: [],
                                     excluded: [], missingSince: &since,
                                     now: Date(), grace: 300)
        XCTAssertTrue(since.isEmpty)
    }

    func testAcceptedRequestToggleScenario() {
        // Field sequence behind the toggle bug: B accepts A's request; A's
        // device hasn't completed the handshake, so request-A-B stays on the
        // server; a later refresh hits a stale replica that omits B's own
        // Friendship{B→A}. At every step A must read as a friend and the
        // request must stay hidden — never the Accept row.
        let t0 = Date()
        let request = req("request-a-me", from: "a", created: t0.addingTimeInterval(-10))
        var ignored = ["request-a-me": Social.acceptStamp(for: request, now: t0)]
        var since: [String: Date] = [:]

        // t0+5s: consistent fetch — own friendship visible, record still there.
        var t = t0.addingTimeInterval(5)
        var ids: Set<String> = ["a"]
        ignored = Social.prunedIgnored(ignored, fetched: [request], now: t)
        XCTAssertTrue(Social.isHidden(request, ignored: ignored))
        XCTAssertTrue(Social.retainedFriendIDs(fetched: ids, cached: ["a"], excluded: [],
                                               missingSince: &since, now: t).isEmpty)

        // t0+90s: stale replica omits the friendship (old overlay long dead),
        // request-A-B still fetched.
        t = t0.addingTimeInterval(90)
        ids = []
        ignored = Social.prunedIgnored(ignored, fetched: [request], now: t)
        XCTAssertTrue(Social.isHidden(request, ignored: ignored))   // no Accept row
        XCTAssertEqual(Social.retainedFriendIDs(fetched: ids, cached: ["a"], excluded: [],
                                                missingSince: &since, now: t), ["a"])   // still a friend

        // t0+120s: fresh replica again — timer clears, nothing to retain.
        t = t0.addingTimeInterval(120)
        ids = ["a"]
        XCTAssertTrue(Social.retainedFriendIDs(fetched: ids, cached: ["a"], excluded: [],
                                               missingSince: &since, now: t).isEmpty)
        XCTAssertTrue(since.isEmpty)
    }
}
