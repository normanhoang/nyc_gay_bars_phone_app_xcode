import Foundation

struct NeighborhoodProgress: Identifiable {
    let neighborhood: String
    let visited: Int
    let total: Int
    var id: String { neighborhood }
}

/// Pure stat + badge logic ported from RN lib/stats.ts.
enum Stats {
    private static let dayMS = 24.0 * 60.0 * 60.0 * 1000.0

    /// Prestige badges whose unlock warrants a confetti celebration.
    static let milestoneBadgeIds: Set<String> = [
        "full-week", "old-faithful", "nifty-fifty", "century-club", "explorer",
        "half-the-city", "neighborhood-hero", "grand-tour", "conqueror",
    ]

    static func totalDrinks(_ visits: [Visit]) -> Int {
        visits.reduce(0) { $0 + $1.drinkTotal }
    }

    /// Number of distinct calendar days the user went to a bar (a day at two
    /// bars counts once).
    static func totalDrinkDays(_ visits: [Visit]) -> Int {
        Set(visits.map { DayKey.key(iso: $0.date) }).count
    }

    static func longestDayStreak(_ visits: [Visit]) -> Int {
        longestRun(uniqueSortedDayTimes(visits))
    }

    static func distinctBarsVisited(_ visits: [Visit]) -> Int {
        Set(visits.map { $0.barId }).count
    }

    /// Bar with the most drink-days, tiebroken by total drinks.
    static func favoriteBar(_ visits: [Visit]) -> Bar? {
        var byBar: [String: (days: Int, drinks: Int)] = [:]
        for v in visits {
            let cur = byBar[v.barId] ?? (0, 0)
            byBar[v.barId] = (cur.days + 1, cur.drinks + v.drinkTotal)
        }
        var bestId: String?
        var best = (days: 0, drinks: 0)
        // Deterministic pass over unique bar ids in first-seen order.
        var seen: Set<String> = []
        for v in visits where !seen.contains(v.barId) {
            seen.insert(v.barId)
            let s = byBar[v.barId]!
            if s.days > best.days || (s.days == best.days && s.drinks > best.drinks) {
                bestId = v.barId
                best = s
            }
        }
        return bestId.flatMap { AppData.bar(id: $0) }
    }

    /// Most-logged drink type and its all-time count.
    static func topDrinkType(_ visits: [Visit]) -> (type: String, count: Int)? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for v in visits {
            for d in v.drinks {
                if counts[d.type] == nil { order.append(d.type) }
                counts[d.type, default: 0] += d.count
            }
        }
        var best: (type: String, count: Int)?
        for type in order {
            let count = counts[type]!
            if best == nil || count > best!.count { best = (type, count) }
        }
        return best
    }

    /// The single day with the highest drink total.
    static func biggestNight(_ visits: [Visit]) -> (day: String, total: Int)? {
        var byDay: [String: Int] = [:]
        var order: [String] = []
        for v in visits {
            let key = DayKey.key(iso: v.date)
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: 0] += v.drinkTotal
        }
        var best: (day: String, total: Int)?
        for day in order {
            let total = byDay[day]!
            if best == nil || total > best!.total { best = (day, total) }
        }
        return best
    }

    /// Set of bar ids the user has ever visited (marked or drink-logged).
    static func computeVisitedIds(_ isVisited: (String) -> Bool) -> Set<String> {
        var ids: Set<String> = []
        for bar in AppData.bars where isVisited(bar.id) { ids.insert(bar.id) }
        return ids
    }

    /// Visited/total bar counts per neighborhood, most-complete first.
    static func neighborhoodProgress(_ visitedIds: Set<String>) -> [NeighborhoodProgress] {
        AppData.neighborhoods.map { neighborhood -> NeighborhoodProgress in
            let bars = AppData.bars.filter { $0.neighborhood == neighborhood }
            return NeighborhoodProgress(
                neighborhood: neighborhood,
                visited: bars.filter { visitedIds.contains($0.id) }.count,
                total: bars.count)
        }.sorted { a, b in
            let ra = Double(a.visited) / Double(a.total)
            let rb = Double(b.visited) / Double(b.total)
            if ra != rb { return ra > rb }
            return a.visited > b.visited
        }
    }

    // MARK: - Streak helpers

    private static let brooklynHoods: Set = ["Williamsburg", "Bushwick", "Bed-Stuy",
        "Prospect Heights", "Park Slope", "Carroll Gardens"]
    private static let queensHoods: Set = ["Astoria", "Jackson Heights"]

    /// Coarse borough for a neighborhood (Manhattan unless it's a known BK/QN one).
    private static func borough(_ neighborhood: String) -> String {
        brooklynHoods.contains(neighborhood) ? "Brooklyn"
            : queensHoods.contains(neighborhood) ? "Queens" : "Manhattan"
    }

    /// The distinct visit days as sorted local-noon timestamps (ms).
    private static func uniqueSortedDayTimes(_ visits: [Visit]) -> [Double] {
        Set(visits.map { DayKey.key(iso: $0.date) })
            .map { DayKey.toDate($0).timeIntervalSince1970 * 1000.0 }
            .sorted()
    }

    /// Longest run of consecutive days among sorted local-noon timestamps.
    private static func longestRun(_ dayTimes: [Double]) -> Int {
        var best = dayTimes.isEmpty ? 0 : 1
        var run = 1
        for i in 1..<max(dayTimes.count, 1) where dayTimes.count > 1 {
            if (((dayTimes[i] - dayTimes[i - 1]) / dayMS).rounded()) == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    // MARK: - Badges

    static func badges(_ visits: [Visit], _ visitedIds: Set<String>) -> [Badge] {
        let neighborhoodsVisited = Set(
            visitedIds.compactMap { AppData.bar(id: $0)?.neighborhood }
        ).count

        var barsPerDay: [String: Set<String>] = [:]
        for v in visits {
            barsPerDay[DayKey.key(iso: v.date), default: []].insert(v.barId)
        }
        let maxBarsInOneDay = barsPerDay.values.map { $0.count }.max() ?? 0

        var daysPerBar: [String: Int] = [:]
        for v in visits { daysPerBar[v.barId, default: 0] += 1 }
        let maxDaysAtOneBar = daysPerBar.values.max() ?? 0

        var drinkTotalsByType: [String: Int] = [:]
        for v in visits {
            for d in v.drinks {
                drinkTotalsByType[d.type.lowercased(), default: 0] += d.count
            }
        }

        let maxShotsInOneVisit = visits.map { v in
            v.drinks.first { $0.type == "Shot" }?.count ?? 0
        }.max() ?? 0
        let maxTypesInOneVisit = visits.map { $0.drinks.count }.max() ?? 0

        let boroughsVisited = Set(
            visitedIds.compactMap { AppData.bar(id: $0)?.neighborhood }.map(borough)
        )

        // Noon-stamped backdated visits can't produce early-morning hours; only
        // live after-midnight logging can.
        let hasLateNightVisit = visits.contains {
            Calendar.current.component(.hour, from: DayKey.parseISO($0.date)) < 4
        }

        // Weekdays (1=Sun…7=Sat in Swift). Convert to JS 0=Sun…6=Sat.
        let visitWeekdays = Set(visits.map {
            Calendar.current.component(.weekday, from: DayKey.parseISO($0.date)) - 1
        })

        let streak = longestDayStreak(visits)
        let maxDrinksInOneDay = biggestNight(visits)?.total ?? 0

        var visitsByBar: [String: [Visit]] = [:]
        for v in visits { visitsByBar[v.barId, default: []].append(v) }
        let maxRunAtOneBar = visitsByBar.values.map { longestRun(uniqueSortedDayTimes($0)) }.max() ?? 0

        let hasCompleteNeighborhood = AppData.neighborhoods.contains { n in
            AppData.bars.filter { $0.neighborhood == n }.allSatisfy { visitedIds.contains($0.id) }
        }

        let halfTheCity = Int((Double(AppData.bars.count) / 2).rounded(.up))

        return [
            Badge(id: "first-drink", emoji: "🍻", title: "First Drink",
                  description: "Log your first drink", earned: !visits.isEmpty),
            Badge(id: "stonewall", emoji: "🏳️‍🌈", title: "Stonewall Pilgrimage",
                  description: "Visit The Stonewall Inn", earned: visitedIds.contains("the-stonewall-inn")),
            Badge(id: "sampler", emoji: "🗺️", title: "Neighborhood Sampler",
                  description: "Visit bars in 3 neighborhoods", earned: neighborhoodsVisited >= 3),
            Badge(id: "crawler", emoji: "🐛", title: "Bar Crawler",
                  description: "Hit 3 bars in one day", earned: maxBarsInOneDay >= 3),
            Badge(id: "regular", emoji: "💺", title: "Regular",
                  description: "5 drink-days at one bar", earned: maxDaysAtOneBar >= 5),
            Badge(id: "night-owl", emoji: "🦉", title: "Night Owl",
                  description: "Log a drink after midnight", earned: hasLateNightVisit),
            Badge(id: "on-a-roll", emoji: "🔥", title: "On a Roll",
                  description: "Drinks logged 3 days in a row", earned: streak >= 3),
            Badge(id: "mixologist", emoji: "🍹", title: "Mixologist",
                  description: "Try 5 different drink types", earned: drinkTotalsByType.count >= 5),
            Badge(id: "shots-shots-shots", emoji: "🥃", title: "Shots Shots Shots",
                  description: "3 shots in one visit", earned: maxShotsInOneVisit >= 3),
            Badge(id: "sober-curious", emoji: "🧃", title: "Sober Curious",
                  description: "Log a non-alcoholic drink", earned: drinkTotalsByType["non-alcoholic"] != nil),
            Badge(id: "bar-star", emoji: "⭐", title: "Bar Star",
                  description: "Visit 10 different bars", earned: visitedIds.count >= 10),
            Badge(id: "century-club", emoji: "💯", title: "Century Club",
                  description: "100 drinks all-time", earned: totalDrinks(visits) >= 100),
            Badge(id: "borough-hopper", emoji: "🌉", title: "Borough Hopper",
                  description: "Visit Manhattan, Brooklyn & Queens bars", earned: boroughsVisited.count >= 3),
            Badge(id: "marathon", emoji: "🏃", title: "Marathon",
                  description: "Hit 5 bars in one day", earned: maxBarsInOneDay >= 5),
            Badge(id: "weekend-warrior", emoji: "🪩", title: "Weekend Warrior",
                  description: "Log drinks on a Friday and a Saturday",
                  earned: visitWeekdays.contains(5) && visitWeekdays.contains(6)),
            Badge(id: "school-night", emoji: "📚", title: "School Night",
                  description: "Log drinks on a weeknight (Mon–Thu)",
                  earned: [1, 2, 3, 4].contains { visitWeekdays.contains($0) }),
            Badge(id: "full-week", emoji: "📅", title: "Full Week",
                  description: "Drinks logged 7 days in a row", earned: streak >= 7),
            Badge(id: "back-to-back", emoji: "🔁", title: "Back to Back",
                  description: "Same bar two days in a row", earned: maxRunAtOneBar >= 2),
            Badge(id: "old-faithful", emoji: "🪑", title: "Old Faithful",
                  description: "10 drink-days at one bar", earned: maxDaysAtOneBar >= 10),
            Badge(id: "double-digits", emoji: "🔟", title: "Double Digits",
                  description: "10 drinks in one day", earned: maxDrinksInOneDay >= 10),
            Badge(id: "nifty-fifty", emoji: "🏅", title: "Nifty Fifty",
                  description: "50 drinks all-time", earned: totalDrinks(visits) >= 50),
            Badge(id: "hophead", emoji: "🍺", title: "Hophead",
                  description: "25 beers all-time", earned: (drinkTotalsByType["beer"] ?? 0) >= 25),
            Badge(id: "wine-not", emoji: "🍷", title: "Wine Not?",
                  description: "10 wines all-time", earned: (drinkTotalsByType["wine"] ?? 0) >= 10),
            Badge(id: "shaken-stirred", emoji: "🍸", title: "Shaken & Stirred",
                  description: "25 cocktails all-time", earned: (drinkTotalsByType["cocktail"] ?? 0) >= 25),
            Badge(id: "variety-pack", emoji: "🌈", title: "Variety Pack",
                  description: "4 different drink types in one visit", earned: maxTypesInOneVisit >= 4),
            Badge(id: "explorer", emoji: "🧭", title: "Explorer",
                  description: "Visit 25 different bars", earned: visitedIds.count >= 25),
            Badge(id: "half-the-city", emoji: "🗽", title: "Half the City",
                  description: "Visit \(halfTheCity) bars", earned: visitedIds.count >= halfTheCity),
            Badge(id: "neighborhood-hero", emoji: "🏘️", title: "Neighborhood Hero",
                  description: "Visit every bar in one neighborhood", earned: hasCompleteNeighborhood),
            Badge(id: "grand-tour", emoji: "🚇", title: "Grand Tour",
                  description: "Visit a bar in every neighborhood",
                  earned: neighborhoodsVisited == AppData.neighborhoods.count),
            Badge(id: "conqueror", emoji: "👑", title: "Scene Conqueror",
                  description: "Visit every bar in the city", earned: visitedIds.count == AppData.bars.count),
        ]
    }
}
