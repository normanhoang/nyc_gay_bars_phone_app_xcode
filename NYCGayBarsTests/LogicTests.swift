import XCTest
@testable import NYCGayBars

final class GeoTests: XCTestCase {
    func testDistanceRoughlyMatches() {
        let eagle = AppData.bar(id: "eagle-nyc")!
        let stonewall = AppData.bar(id: "the-stonewall-inn")!
        let mi = Geo.distanceMiles(stonewall.latitude, stonewall.longitude, eagle)
        XCTAssertGreaterThan(mi, 1.0)
        XCTAssertLessThan(mi, 1.5)
    }

    func testDistanceZeroAtBar() {
        let eagle = AppData.bar(id: "eagle-nyc")!
        XCTAssertEqual(Geo.distanceMiles(eagle.latitude, eagle.longitude, eagle), 0, accuracy: 1e-5)
    }

    func testNearestBarAtOwnCoords() {
        let s = AppData.bar(id: "the-stonewall-inn")!
        XCTAssertEqual(Geo.nearestBar(s.latitude, s.longitude).id, "the-stonewall-inn")
    }

    func testFullyVisibleWide() {
        let r = Region(latitude: AppData.region.latitude, longitude: AppData.region.longitude,
                       latitudeDelta: 1, longitudeDelta: 1)
        XCTAssertEqual(Geo.fullyVisibleNeighborhoods(r), AppData.neighborhoods.count)
    }

    func testFullyVisibleTight() {
        let s = AppData.bar(id: "the-stonewall-inn")!
        let r = Region(latitude: s.latitude, longitude: s.longitude,
                       latitudeDelta: 0.002, longitudeDelta: 0.002)
        XCTAssertLessThanOrEqual(Geo.fullyVisibleNeighborhoods(r), 1)
    }

    func testFullyVisibleAtlantic() {
        let r = Region(latitude: 30, longitude: -50, latitudeDelta: 0.2, longitudeDelta: 0.2)
        XCTAssertEqual(Geo.fullyVisibleNeighborhoods(r), 0)
    }

    func testKnownZip() {
        XCTAssertTrue(Geo.isKnownZip("10001"))
        XCTAssertTrue(Geo.isKnownZip("11201"))
        XCTAssertFalse(Geo.isKnownZip("90210"))
        XCTAssertFalse(Geo.isKnownZip("1001"))
        XCTAssertFalse(Geo.isKnownZip("abcde"))
        XCTAssertFalse(Geo.isKnownZip("constructor"))
    }

    func testZipNeighborhoods() {
        XCTAssertEqual(Geo.neighborhoodForZip("10014"), "West Village")
        XCTAssertEqual(Geo.neighborhoodForZip("10009"), "East Village")
        XCTAssertEqual(Geo.neighborhoodForZip("10027"), "Harlem")
        XCTAssertEqual(Geo.neighborhoodForZip("11201"), "Brooklyn")
        XCTAssertEqual(Geo.neighborhoodForZip("11101"), "Queens")
        XCTAssertNil(Geo.neighborhoodForZip("90210"))
    }
}

final class StatsTests: XCTestCase {
    private func visit(_ bar: String, _ day: String, _ drinks: [(String, Int)]) -> Visit {
        Visit(id: UUID().uuidString, barId: bar,
              date: DayKey.iso(DayKey.toDate(day)),
              drinks: drinks.map { DrinkEntry(type: $0.0, count: $0.1) }, note: nil)
    }

    func testTotalsAndStreak() {
        let vs = [
            visit("a", "2026-5-10", [("Beer", 2)]),
            visit("a", "2026-5-11", [("Wine", 1)]),
            visit("b", "2026-5-12", [("Beer", 3)]),
        ]
        XCTAssertEqual(Stats.totalDrinks(vs), 6)
        XCTAssertEqual(Stats.totalDrinkDays(vs), 3)
        XCTAssertEqual(Stats.longestDayStreak(vs), 3)
        XCTAssertEqual(Stats.distinctBarsVisited(vs), 2)
    }

    func testBadgesFirstDrinkAndStonewall() {
        let vs = [visit("the-stonewall-inn", "2026-5-10", [("Beer", 1)])]
        let ids = Set(["the-stonewall-inn"])
        let badges = Stats.badges(vs, ids)
        XCTAssertEqual(badges.count, 30)
        XCTAssertTrue(badges.first { $0.id == "first-drink" }!.earned)
        XCTAssertTrue(badges.first { $0.id == "stonewall" }!.earned)
        XCTAssertFalse(badges.first { $0.id == "conqueror" }!.earned)
    }
}
