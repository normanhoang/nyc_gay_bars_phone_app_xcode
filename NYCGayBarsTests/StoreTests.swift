import XCTest
@testable import NYCGayBars

/// Store behavior against an isolated UserDefaults suite (never .standard).
final class StoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "StoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func visit(_ bar: String, _ day: String, _ drinks: [(String, Int)]) -> Visit {
        Visit(id: UUID().uuidString, barId: bar,
              date: DayKey.iso(DayKey.toDate(day)),
              drinks: drinks.map { DrinkEntry(type: $0.0, count: $0.1) }, note: nil)
    }

    // MARK: VisitsStore

    func testSetVisitedFutureDayIsRefused() {
        let store = VisitsStore(defaults: defaults)
        let future = DayKey.key(Date().addingTimeInterval(3 * 86400))
        store.setVisited("eagle-nyc", true, day: future)
        XCTAssertFalse(store.isVisited("eagle-nyc"))
        XCTAssertTrue(store.visits.isEmpty)
        XCTAssertTrue(store.visitedIds.isEmpty)
    }

    func testSetVisitedTodayStillWorks() {
        let store = VisitsStore(defaults: defaults)
        store.setVisited("eagle-nyc", true)
        XCTAssertTrue(store.isVisited("eagle-nyc"))
        XCTAssertEqual(store.visits.count, 1)
    }

    func testCorruptVisitDateDroppedAtDecode() {
        let json = """
        [{"id":"bad","barId":"eagle-nyc","date":"not-a-date","drinks":[{"type":"Beer","count":1}]},
         {"id":"good","barId":"eagle-nyc","date":"\(DayKey.iso(Date()))","drinks":[]}]
        """
        defaults.set(Data(json.utf8), forKey: "@gaybars/visits")
        let store = VisitsStore(defaults: defaults)
        // The corrupt entry must be dropped, not silently re-dated to today.
        XCTAssertEqual(store.visits.map(\.id), ["good"])
    }

    // MARK: BadgesStore toast timing

    func testLaterUnlockDoesNotExtendCurrentToast() {
        let store = BadgesStore(defaults: defaults, toastSeconds: 0.5)
        store.reconcile(visits: [], visitedIds: [])   // consume first-reconcile quiet pass
        // 2026-5-10 is Wed June 10: unlocks first-drink + school-night.
        let vs = [visit("eagle-nyc", "2026-5-10", [("Beer", 1)])]
        store.reconcile(visits: vs, visitedIds: ["eagle-nyc"])
        XCTAssertEqual(store.unlocked.count, 2)

        // 0.25s in, a third unlock lands (stonewall). It must queue without
        // restarting the current toast's 0.5s dismiss timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            store.reconcile(visits: vs, visitedIds: ["eagle-nyc", "the-stonewall-inn"])
            XCTAssertEqual(store.unlocked.count, 3)
        }

        let exp = expectation(description: "first toast dismissed on schedule")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            // On-schedule dismiss (0.5s) leaves two queued; a reset timer
            // wouldn't fire until 0.75s and would still show all three.
            XCTAssertEqual(store.unlocked.count, 2)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
    }
}
