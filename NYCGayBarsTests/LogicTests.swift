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

    func testDerivedDistancesAndProximity() {
        let s = AppData.bar(id: "the-stonewall-inn")!
        let d1 = Geo.derived(s.latitude, s.longitude)
        XCTAssertEqual(d1.distances.count, AppData.bars.count)
        XCTAssertEqual(d1.distances["the-stonewall-inn"]!, 0, accuracy: 1e-5)
        // Own neighborhood always ranks first (its nearest bar is 0 mi away).
        XCTAssertEqual(d1.neighborhoodsByProximity.first, s.neighborhood)
        XCTAssertEqual(Set(d1.neighborhoodsByProximity), Set(AppData.neighborhoods))
    }

    func testDerivedCacheKeyedByCoordinate() {
        let s = AppData.bar(id: "the-stonewall-inn")!
        let e = AppData.bar(id: "eagle-nyc")!
        let atStonewall = Geo.derived(s.latitude, s.longitude)
        // Moving must not serve the previous coordinate's cached result…
        let atEagle = Geo.derived(e.latitude, e.longitude)
        XCTAssertEqual(atEagle.distances["eagle-nyc"]!, 0, accuracy: 1e-5)
        XCTAssertEqual(atEagle.neighborhoodsByProximity.first, e.neighborhood)
        // …and returning must still be correct.
        let back = Geo.derived(s.latitude, s.longitude)
        XCTAssertEqual(back.distances["the-stonewall-inn"]!, 0, accuracy: 1e-5)
        XCTAssertEqual(back.neighborhoodsByProximity, atStonewall.neighborhoodsByProximity)
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
        XCTAssertEqual(Geo.neighborhoodForZip("11201"), "Carroll Gardens")
        XCTAssertEqual(Geo.neighborhoodForZip("11101"), "Astoria")
        XCTAssertNil(Geo.neighborhoodForZip("90210"))
    }
}

final class DayKeyTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 15) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (y, m, d, hour)
        return Calendar.current.date(from: c)!
    }

    func testKeyUsesZeroIndexedMonth() {
        XCTAssertEqual(DayKey.key(date(2026, 6, 24)), "2026-5-24")
        XCTAssertEqual(DayKey.key(date(2026, 1, 1)), "2026-0-1")
        XCTAssertEqual(DayKey.key(date(2026, 12, 31)), "2026-11-31")
    }

    func testToDateRoundTripsKey() {
        for key in ["2026-5-24", "2026-0-1", "2026-11-31"] {
            XCTAssertEqual(DayKey.key(DayKey.toDate(key)), key)
        }
    }

    func testKeyFromISORoundTrips() {
        let iso = DayKey.iso(DayKey.toDate("2026-5-24"))
        XCTAssertEqual(DayKey.key(iso: iso), "2026-5-24")
    }

    func testIsoParseRoundTrip() {
        let now = Date()
        XCTAssertEqual(DayKey.parseISO(DayKey.iso(now)).timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testParseISOStrict() {
        XCTAssertNotNil(DayKey.parseISOStrict("2026-06-24T19:00:00.000Z"))
        XCTAssertNotNil(DayKey.parseISOStrict("2026-06-24T19:00:00Z"))
        XCTAssertNil(DayKey.parseISOStrict("not-a-date"))
        XCTAssertNil(DayKey.parseISOStrict(""))
    }

    func testIsFuture() {
        XCTAssertFalse(DayKey.isFuture(DayKey.key()))
        XCTAssertTrue(DayKey.isFuture(DayKey.key(Date().addingTimeInterval(2 * 86400))))
        XCTAssertFalse(DayKey.isFuture(DayKey.key(Date().addingTimeInterval(-2 * 86400))))
    }

    func testFormat() {
        XCTAssertEqual(DayKey.format("2026-5-24"), "Wednesday, June 24, 2026")
    }

    func testMakeIdVaries() {
        XCTAssertNotEqual(DayKey.makeId(), DayKey.makeId())
    }
}

@MainActor
final class ZipQueryTests: XCTestCase {
    func testRecognizedZipIntercepts() {
        let z = ZipQuery()
        var selected: String?
        z.onZip = { selected = $0 }
        z.change("10014")
        XCTAssertEqual(selected, "West Village")
        XCTAssertEqual(z.query, "")
        XCTAssertEqual(z.zipNote, "10014 → West Village")
    }

    func testRecognizedZipTrimsWhitespace() {
        let z = ZipQuery()
        var selected: String?
        z.onZip = { selected = $0 }
        z.change(" 10014 ")
        XCTAssertEqual(selected, "West Village")
    }

    func testPlainTextPassesThrough() {
        let z = ZipQuery()
        var selected: String?
        z.onZip = { selected = $0 }
        z.change("stonewall")
        XCTAssertNil(selected)
        XCTAssertEqual(z.query, "stonewall")
        XCTAssertNil(z.zipNote)
    }
}

final class DrinksTests: XCTestCase {
    func testDrinkEmojiIsCaseInsensitive() {
        XCTAssertEqual(drinkEmoji("Beer"), "🍺")
        XCTAssertEqual(drinkEmoji("beer"), "🍺")
        XCTAssertEqual(drinkEmoji("SHOT"), "🥃")
        XCTAssertEqual(drinkEmoji("Margarita"), "🍹")
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

    func testBoroughProgress() {
        let boroughs = Stats.boroughProgress([])
        XCTAssertEqual(boroughs.map(\.borough), ["Manhattan", "Brooklyn", "Queens"])
        for b in boroughs {
            XCTAssertEqual(b.total, b.neighborhoods.reduce(0) { $0 + $1.total })
            XCTAssertEqual(b.visited, 0)
        }
        XCTAssertEqual(boroughs.reduce(0) { $0 + $1.total }, AppData.bars.count)
        let brooklyn = boroughs.first { $0.borough == "Brooklyn" }!
        XCTAssertTrue(brooklyn.neighborhoods.contains { $0.neighborhood == "Williamsburg" })
        let queens = boroughs.first { $0.borough == "Queens" }!
        XCTAssertTrue(queens.neighborhoods.contains { $0.neighborhood == "Astoria" })
    }

    func testBoroughProgressCountsVisited() {
        let astoriaBar = AppData.bars.first { $0.neighborhood == "Astoria" }!
        let boroughs = Stats.boroughProgress([astoriaBar.id])
        let queens = boroughs.first { $0.borough == "Queens" }!
        XCTAssertEqual(queens.visited, 1)
        XCTAssertEqual(boroughs.first { $0.borough == "Manhattan" }!.visited, 0)
    }

    func testFavoriteBarMostDaysThenMostDrinks() {
        let vs = [
            visit("eagle-nyc", "2026-5-1", [("Beer", 1)]),
            visit("eagle-nyc", "2026-5-2", [("Beer", 1)]),
            visit("the-cock", "2026-5-3", [("Beer", 2)]),
            visit("the-cock", "2026-5-4", [("Beer", 3)]),
            visit("the-stonewall-inn", "2026-5-5", [("Beer", 9)]),
        ]
        // eagle and the-cock tie on days (2); the-cock wins on drinks (5 > 2).
        XCTAssertEqual(Stats.favoriteBar(vs)?.id, "the-cock")
        XCTAssertNil(Stats.favoriteBar([]))
    }

    func testTopDrinkType() {
        let vs = [
            visit("eagle-nyc", "2026-5-1", [("Beer", 2), ("Wine", 1)]),
            visit("eagle-nyc", "2026-5-2", [("Wine", 2)]),
        ]
        let top = Stats.topDrinkType(vs)
        XCTAssertEqual(top?.type, "Wine")
        XCTAssertEqual(top?.count, 3)
        XCTAssertNil(Stats.topDrinkType([]))
    }

    func testBiggestNightSumsAcrossBars() {
        let vs = [
            visit("eagle-nyc", "2026-5-1", [("Beer", 2)]),
            visit("the-cock", "2026-5-1", [("Shot", 2)]),
            visit("eagle-nyc", "2026-5-2", [("Beer", 3)]),
        ]
        let night = Stats.biggestNight(vs)
        XCTAssertEqual(night?.day, "2026-5-1")
        XCTAssertEqual(night?.total, 4)
        XCTAssertNil(Stats.biggestNight([]))
    }

    func testComputeVisitedIdsDropsUnknownBars() {
        let ids = Stats.computeVisitedIds(
            visits: [visit("eagle-nyc", "2026-5-1", [("Beer", 1)])],
            visitedBars: ["the-stonewall-inn", "not-a-real-bar"])
        XCTAssertEqual(ids, ["eagle-nyc", "the-stonewall-inn"])
    }

    func testNeighborhoodProgressTotalsAndOrder() {
        let empty = Stats.neighborhoodProgress([])
        XCTAssertEqual(empty.count, AppData.neighborhoods.count)
        XCTAssertEqual(empty.reduce(0) { $0 + $1.total }, AppData.bars.count)
        // The one visited bar's neighborhood sorts first (only nonzero ratio).
        let ranked = Stats.neighborhoodProgress(["eagle-nyc"])
        XCTAssertEqual(ranked.first?.neighborhood, "Chelsea")
        XCTAssertEqual(ranked.first?.visited, 1)
    }

    func testBadgeProgressCounts() {
        let vs = [
            visit("eagle-nyc", "2026-5-10", [("Beer", 2)]),
            visit("eagle-nyc", "2026-5-11", [("Wine", 1)]),
        ]
        let p = Stats.badgeProgress(vs, ["eagle-nyc"])
        XCTAssertEqual(p["on-a-roll"]?.current, 2)       // 2-day streak
        XCTAssertEqual(p["on-a-roll"]?.target, 3)
        XCTAssertEqual(p["nifty-fifty"]?.current, 3)     // total drinks
        XCTAssertEqual(p["regular"]?.current, 2)         // days at one bar
        XCTAssertEqual(p["mixologist"]?.current, 2)      // distinct types
        XCTAssertEqual(p["conqueror"]?.target, AppData.bars.count)
        XCTAssertEqual(p["grand-tour"]?.target, AppData.neighborhoods.count)
    }

    func testStreakAndPerTypeBadges() {
        var vs = [
            visit("eagle-nyc", "2026-5-10", [("Beer", 13)]),
            visit("eagle-nyc", "2026-5-11", [("Beer", 12), ("Wine", 10)]),
            visit("eagle-nyc", "2026-5-12", [("Non-alcoholic", 1)]),
        ]
        var earned = Set(Stats.badges(vs, ["eagle-nyc"]).filter(\.earned).map(\.id))
        XCTAssertTrue(earned.contains("on-a-roll"))       // 3-day streak
        XCTAssertTrue(earned.contains("back-to-back"))    // same bar consecutive days
        XCTAssertTrue(earned.contains("hophead"))         // 25 beers
        XCTAssertTrue(earned.contains("wine-not"))        // 10 wines
        XCTAssertTrue(earned.contains("sober-curious"))
        XCTAssertTrue(earned.contains("double-digits"))   // 22 drinks in one day
        XCTAssertFalse(earned.contains("full-week"))
        // Extend the run to 7 straight days for full-week.
        for d in 13...16 { vs.append(visit("eagle-nyc", "2026-5-\(d)", [("Beer", 1)])) }
        earned = Set(Stats.badges(vs, ["eagle-nyc"]).filter(\.earned).map(\.id))
        XCTAssertTrue(earned.contains("full-week"))
    }

    func testNightOwlNeedsEarlyMorningHour() {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour) = (2026, 6, 20, 2)
        let twoAM = Visit(id: "x", barId: "eagle-nyc",
                          date: DayKey.iso(Calendar.current.date(from: c)!),
                          drinks: [DrinkEntry(type: "Shot", count: 1)], note: nil)
        XCTAssertTrue(Stats.badges([twoAM], []).first { $0.id == "night-owl" }!.earned)
        // Backdated visits are noon-stamped and must not count.
        let noon = visit("eagle-nyc", "2026-5-20", [("Shot", 1)])
        XCTAssertFalse(Stats.badges([noon], []).first { $0.id == "night-owl" }!.earned)
    }

    func testBoroughHopperAcrossThreeBoroughs() {
        let manhattan = AppData.barsByNeighborhood["Chelsea"]!.first!.id
        let brooklyn = AppData.barsByNeighborhood["Williamsburg"]!.first!.id
        let queens = AppData.barsByNeighborhood["Astoria"]!.first!.id
        let two = Stats.badges([], [manhattan, brooklyn])
        XCTAssertFalse(two.first { $0.id == "borough-hopper" }!.earned)
        let three = Stats.badges([], [manhattan, brooklyn, queens])
        XCTAssertTrue(three.first { $0.id == "borough-hopper" }!.earned)
    }

    /// Snapshot of the hardcoded neighborhood→borough map. Fails loudly when a
    /// neighborhood is added to the data without classifying it here and in
    /// `Stats.borough` — otherwise it silently counts as Manhattan.
    func testEveryNeighborhoodHasExpectedBorough() {
        let expected: [String: String] = [
            "Chelsea": "Manhattan", "East Village": "Manhattan", "Harlem": "Manhattan",
            "Hell's Kitchen": "Manhattan", "Lower East Side": "Manhattan",
            "Midtown East": "Manhattan", "Upper East Side": "Manhattan",
            "Upper West Side": "Manhattan", "West Village": "Manhattan",
            "Williamsburg": "Brooklyn", "Bushwick": "Brooklyn", "Bed-Stuy": "Brooklyn",
            "Prospect Heights": "Brooklyn", "Park Slope": "Brooklyn",
            "Carroll Gardens": "Brooklyn",
            "Astoria": "Queens", "Jackson Heights": "Queens",
        ]
        XCTAssertEqual(Set(AppData.neighborhoods), Set(expected.keys),
                       "neighborhood set changed — update this map AND Stats.borough's sets")
        var actual: [String: String] = [:]
        for b in Stats.boroughProgress([]) {
            for hood in b.neighborhoods { actual[hood.neighborhood] = b.borough }
        }
        XCTAssertEqual(actual, expected)
    }

    func testShotsBadgeMatchesCustomCasedShots() {
        // A first-of-the-day custom "shot" is stored verbatim; the badge must
        // still count it.
        let vs = [visit("eagle-nyc", "2026-5-10", [("shot", 3)])]
        XCTAssertTrue(Stats.badges(vs, ["eagle-nyc"]).first { $0.id == "shots-shots-shots" }!.earned)
        XCTAssertEqual(Stats.badgeProgress(vs, ["eagle-nyc"])["shots-shots-shots"]?.current, 3)
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
