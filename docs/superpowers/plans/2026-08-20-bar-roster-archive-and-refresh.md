# Bar Roster Archive and Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Archive three inactive/stale records without breaking visit history, refresh one stale name, add eight approved active venues, and support the two newly represented neighborhoods and the Bronx throughout the map and progress UI.

**Architecture:** Add an optional `archived` flag to bundled bar records. `AppData` will retain every record for ID-based historical lookup while exposing only non-archived bars to Explore, maps, proximity, progress, and badges. Continue the existing static-resource approach by extending the bundled bar, neighborhood metadata, and polygon JSON files; classify the new neighborhoods in the existing borough logic.

**Tech Stack:** Swift 5, SwiftUI, XCTest, bundled JSON resources, MapKit

**Spec:** `docs/nyc-bar-roster-audit-2026-08-20.md`

## Global Constraints

- Preserve the IDs and historical lookup of `bar-nine`, `adonis-lounge`, and `rawhide`.
- Exclude archived records from active browsing, maps, proximity, completion totals, and badge progress.
- Give the revived Club Rawhide and FairyTale Lounge new IDs; neither may inherit an archived venue's identity.
- Preserve the existing ID `the-duplex-closed-temporarily` while changing only its display name.
- Leave MB Bar Boutique, PRIDE Bar & Lounge, VV Bar & Kitchen, and Alibi Lounge unchanged.
- Use the official NYC NTA names `Clinton Hill` and `Mott Haven-Port Morris` for the new map neighborhoods.
- Do not refactor unrelated logic or overwrite the workspace's existing uncommitted changes.
- Do not create commits: the workspace already contains mixed user and prior feature changes.

---

### Task 1: Preserve archived records while removing them from the active roster

**Files:**
- Modify: `NYCGayBarsTests/LogicTests.swift`
- Modify: `NYCGayBars/Models/Models.swift`
- Modify: `NYCGayBars/Data/AppData.swift`
- Modify: `NYCGayBars/Data/Resources/bars.json`
- Modify: `NYCGayBars/Logic/Stats.swift`

**Interfaces:**
- Produces: `Bar.isArchived: Bool`, `AppData.bars` as the active roster, and `AppData.bar(id:)` as an all-record historical lookup.
- Consumes: existing `Stats.computeVisitedIds(visits:visitedBars:)` and bundled JSON loading.

- [ ] **Step 1: Write the failing archival behavior test**

Add this test to `AppDataTests`:

```swift
func testArchivedBarsResolveForHistoryButStayOutOfActiveRoster() {
    let archivedIds: Set<String> = ["bar-nine", "adonis-lounge", "rawhide"]

    for id in archivedIds {
        XCTAssertEqual(AppData.bar(id: id)?.isArchived, true)
    }
    XCTAssertTrue(archivedIds.isDisjoint(with: Set(AppData.bars.map(\.id))))

    let historicalVisit = Visit(
        id: "archived-visit", barId: "bar-nine", date: "2026-01-10T17:00:00Z",
        drinks: [], note: nil)
    XCTAssertEqual(AppData.bar(id: historicalVisit.barId)?.name, "Bar Nine")
    XCTAssertFalse(Stats.computeVisitedIds(
        visits: [historicalVisit], visitedBars: ["adonis-lounge", "rawhide"]
    ).contains(where: archivedIds.contains))
}
```

This catches archived records leaking into the active roster/progress or disappearing from historical lookup.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/AppDataTests/testArchivedBarsResolveForHistoryButStayOutOfActiveRoster
```

Expected: compilation fails because `Bar.isArchived` does not exist yet.

- [ ] **Step 3: Add the minimal archival model and active/all data split**

Add to `Bar` in `Models.swift`:

```swift
let archived: Bool?
var isArchived: Bool { archived == true }
```

Change the beginning of `AppData` to:

```swift
private static let allBars: [Bar] = load("bars")
static let bars: [Bar] = allBars.filter { !$0.isArchived }
static let neighborhoodPolygons: [String: [LatLng]] = load("neighborhoods")
static let zipCentroids: [String: ZipCentroid] = load("zips")

static let barsById: [String: Bar] =
    Dictionary(uniqueKeysWithValues: allBars.map { ($0.id, $0) })
static let activeBarIds = Set(bars.map(\.id))
static let barsByNeighborhood: [String: [Bar]] =
    Dictionary(grouping: bars, by: \.neighborhood)
```

Change the final line of `Stats.computeVisitedIds` to:

```swift
return ids.filter { AppData.activeBarIds.contains($0) }
```

Add `"archived": true` to the existing `bar-nine`, `adonis-lounge`, and `rawhide` JSON objects. Do not delete or rename those records.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the focused command from Step 2.

Expected: the archival test passes, proving both active exclusion and historical resolution.

### Task 2: Add the approved active venues and clean up The Duplex label

**Files:**
- Modify: `NYCGayBarsTests/LogicTests.swift`
- Modify: `NYCGayBars/Data/Resources/bars.json`

**Interfaces:**
- Consumes: Task 1's active roster filtering.
- Produces: eight new active bar records and the corrected Duplex display name.

- [ ] **Step 1: Write the failing approved-roster test**

Add this test to `AppDataTests`:

```swift
func testApprovedRosterChangesAreActive() {
    let expected: [String: (name: String, neighborhood: String, address: String)] = [
        "club-rawhide": ("Club Rawhide", "Chelsea", "250 W 26th St, New York"),
        "oberon": ("Oberon", "Williamsburg", "196 N 10th St, Brooklyn"),
        "solera": ("Solera", "Mott Haven-Port Morris", "125 St. Ann's Ave, Bronx"),
        "athena-kekes": ("Athena Keke's", "Clinton Hill", "222 Greene Ave, Brooklyn"),
        "wilkas-sports-bar": ("Wilka's Sports Bar", "Lower East Side", "241 Bowery, New York"),
        "love-thy-neighbor": ("Love Thy Neighbor", "West Village", "55 Christopher St, New York"),
        "the-exley": ("The Exley", "Williamsburg", "1 Jackson St, Brooklyn"),
        "fairytale-lounge": ("FairyTale Lounge", "Hell's Kitchen", "500 W 48th St, New York"),
    ]

    for (id, value) in expected {
        let bar = AppData.bars.first { $0.id == id }
        XCTAssertEqual(bar?.name, value.name, id)
        XCTAssertEqual(bar?.neighborhood, value.neighborhood, id)
        XCTAssertEqual(bar?.address, value.address, id)
        XCTAssertEqual(bar?.isArchived, false, id)
    }
    XCTAssertEqual(AppData.bar(id: "the-duplex-closed-temporarily")?.name, "The Duplex")
}
```

This catches missing additions, accidental archive flags, wrong identity assignment, or the stale Duplex label returning.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/AppDataTests/testApprovedRosterChangesAreActive
```

Expected: assertions fail because the eight approved IDs are absent and the Duplex name still contains the stale status.

- [ ] **Step 3: Add the minimal bundled records**

Rename only the `name` of `the-duplex-closed-temporarily` to `The Duplex`. Append these active records to `bars.json`:

```json
{
  "id": "club-rawhide",
  "name": "Club Rawhide",
  "neighborhood": "Chelsea",
  "address": "250 W 26th St, New York",
  "latitude": 40.74659,
  "longitude": -73.996267,
  "tags": ["leather"]
},
{
  "id": "oberon",
  "name": "Oberon",
  "neighborhood": "Williamsburg",
  "address": "196 N 10th St, Brooklyn",
  "latitude": 40.7187335,
  "longitude": -73.9549155,
  "tags": ["cocktails", "dance"]
},
{
  "id": "solera",
  "name": "Solera",
  "neighborhood": "Mott Haven-Port Morris",
  "address": "125 St. Ann's Ave, Bronx",
  "latitude": 40.804189,
  "longitude": -73.919464,
  "tags": ["latin", "dance"]
},
{
  "id": "athena-kekes",
  "name": "Athena Keke's",
  "neighborhood": "Clinton Hill",
  "address": "222 Greene Ave, Brooklyn",
  "latitude": 40.6869581,
  "longitude": -73.9621926,
  "tags": ["sports", "lesbian"]
},
{
  "id": "wilkas-sports-bar",
  "name": "Wilka's Sports Bar",
  "neighborhood": "Lower East Side",
  "address": "241 Bowery, New York",
  "latitude": 40.7224757,
  "longitude": -73.9927927,
  "tags": ["sports", "lesbian"]
},
{
  "id": "love-thy-neighbor",
  "name": "Love Thy Neighbor",
  "neighborhood": "West Village",
  "address": "55 Christopher St, New York",
  "latitude": 40.7338278,
  "longitude": -74.002252,
  "tags": ["cocktails", "lounge"]
},
{
  "id": "the-exley",
  "name": "The Exley",
  "neighborhood": "Williamsburg",
  "address": "1 Jackson St, Brooklyn",
  "latitude": 40.7161032,
  "longitude": -73.9515122,
  "tags": ["cocktails", "lounge"]
},
{
  "id": "fairytale-lounge",
  "name": "FairyTale Lounge",
  "neighborhood": "Hell's Kitchen",
  "address": "500 W 48th St, New York",
  "latitude": 40.763409,
  "longitude": -73.992805,
  "tags": ["dance", "lounge"]
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the focused command from Step 2.

Expected: all eight active records and the corrected Duplex label pass.

### Task 3: Add Clinton Hill and Bronx map/progress support

**Files:**
- Modify: `NYCGayBarsTests/LogicTests.swift`
- Modify: `NYCGayBars/Logic/Stats.swift`
- Modify: `NYCGayBars/Data/Resources/meta.json`
- Modify: `NYCGayBars/Data/Resources/neighborhoods.json`

**Interfaces:**
- Consumes: the `Clinton Hill` and `Mott Haven-Port Morris` names from Task 2.
- Produces: map outline rings for both neighborhoods and borough progress that classifies them as Brooklyn and Bronx.

- [ ] **Step 1: Write failing map and borough behavior tests**

Update `testBoroughProgress` to assert:

```swift
XCTAssertEqual(boroughs.map(\.borough), ["Manhattan", "Brooklyn", "Queens", "Bronx"])
```

Add:

```swift
func testNewNeighborhoodsHaveMapOutlines() {
    for neighborhood in ["Clinton Hill", "Mott Haven-Port Morris"] {
        XCTAssertGreaterThanOrEqual(
            AppData.neighborhoodPolygons[neighborhood]?.count ?? 0, 3, neighborhood)
    }
}

func testBronxProgressIncludesSolera() {
    let boroughs = Stats.boroughProgress(["solera"])
    let bronx = boroughs.first { $0.borough == "Bronx" }

    XCTAssertEqual(bronx?.visited, 1)
    XCTAssertEqual(bronx?.total, 1)
    XCTAssertEqual(bronx?.neighborhoods.map(\.neighborhood), ["Mott Haven-Port Morris"])
}
```

Extend the literal `expected` dictionary in `testEveryNeighborhoodHasExpectedBorough` with:

```swift
"Clinton Hill": "Brooklyn",
"Mott Haven-Port Morris": "Bronx",
```

These tests catch absent map outlines and the existing silent fallback that would incorrectly classify an unknown Bronx neighborhood as Manhattan.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/GeoTests/testNewNeighborhoodsHaveMapOutlines -only-testing:NYCGayBarsTests/StatsTests/testBronxProgressIncludesSolera -only-testing:NYCGayBarsTests/StatsTests/testEveryNeighborhoodHasExpectedBorough
```

Expected: failures for missing polygons/meta and Bronx being absent or misclassified.

- [ ] **Step 3: Add neighborhood metadata and official simplified rings**

Add `Clinton Hill` and `Mott Haven-Port Morris` to the sorted `meta.json` neighborhood array. Keep the existing region because its current latitude/longitude deltas already contain both new venues.

Add these rings to `neighborhoods.json`, converting each source `[longitude, latitude]` pair to the resource's `{latitude, longitude}` shape:

```json
"Clinton Hill": [
  {"latitude": 40.680464, "longitude": -73.961347},
  {"latitude": 40.682005, "longitude": -73.96869},
  {"latitude": 40.689506, "longitude": -73.970132},
  {"latitude": 40.689468, "longitude": -73.969104},
  {"latitude": 40.693134, "longitude": -73.969831},
  {"latitude": 40.69312, "longitude": -73.96881},
  {"latitude": 40.69608, "longitude": -73.969395},
  {"latitude": 40.696075, "longitude": -73.964661},
  {"latitude": 40.698039, "longitude": -73.96284},
  {"latitude": 40.698326, "longitude": -73.961051},
  {"latitude": 40.683018, "longitude": -73.958841},
  {"latitude": 40.682691, "longitude": -73.961671},
  {"latitude": 40.680464, "longitude": -73.961347}
],
"Mott Haven-Port Morris": [
  {"latitude": 40.818013, "longitude": -73.925185},
  {"latitude": 40.816119, "longitude": -73.926627},
  {"latitude": 40.815439, "longitude": -73.924},
  {"latitude": 40.816698, "longitude": -73.923093},
  {"latitude": 40.816219, "longitude": -73.921245},
  {"latitude": 40.815551, "longitude": -73.921584},
  {"latitude": 40.814564, "longitude": -73.920481},
  {"latitude": 40.816066, "longitude": -73.917645},
  {"latitude": 40.812125, "longitude": -73.90418},
  {"latitude": 40.811507, "longitude": -73.903417},
  {"latitude": 40.804565, "longitude": -73.902292},
  {"latitude": 40.796624, "longitude": -73.911688},
  {"latitude": 40.798985, "longitude": -73.919032},
  {"latitude": 40.802373, "longitude": -73.922927},
  {"latitude": 40.802696, "longitude": -73.927628},
  {"latitude": 40.803989, "longitude": -73.927645},
  {"latitude": 40.804104, "longitude": -73.928726},
  {"latitude": 40.808823, "longitude": -73.932527},
  {"latitude": 40.814152, "longitude": -73.932423},
  {"latitude": 40.813248, "longitude": -73.930278},
  {"latitude": 40.81856, "longitude": -73.927317},
  {"latitude": 40.818013, "longitude": -73.925185}
]
```

These are simplified from NYC's 2020 Neighborhood Tabulation Areas feature layer rather than hand-drawn around the bars.

- [ ] **Step 4: Classify the new boroughs with the minimal existing pattern**

In `Stats.swift`, append `Clinton Hill` to `brooklynHoods`, add:

```swift
private static let bronxHoods: Set = ["Mott Haven-Port Morris"]
```

Change `borough(_:)` to:

```swift
private static func borough(_ neighborhood: String) -> String {
    brooklynHoods.contains(neighborhood) ? "Brooklyn"
        : queensHoods.contains(neighborhood) ? "Queens"
        : bronxHoods.contains(neighborhood) ? "Bronx" : "Manhattan"
}
```

Change borough display order to:

```swift
return ["Manhattan", "Brooklyn", "Queens", "Bronx"].compactMap { name in
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the focused command from Step 2 plus the updated `testBoroughProgress`.

Expected: both map rings resolve, Solera counts under Bronx, and every neighborhood matches its literal borough classification.

### Task 4: Verify the complete behavior and review the surgical diff

**Files:**
- Verify only; no planned production files beyond Tasks 1-3.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: fresh evidence that the roster loads, builds, and passes the full unit suite.

- [ ] **Step 1: Validate bundled JSON and roster invariants**

Run:

```bash
jq empty NYCGayBars/Data/Resources/bars.json NYCGayBars/Data/Resources/meta.json NYCGayBars/Data/Resources/neighborhoods.json
jq '[.[].id] | length == (unique | length)' NYCGayBars/Data/Resources/bars.json
```

Expected: `jq empty` exits 0 and the uniqueness query prints `true`.

- [ ] **Step 2: Run the full unit suite**

Run:

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
```

Expected: exit 0 with zero test failures.

- [ ] **Step 3: Run a clean build**

Run:

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
```

Expected: exit 0.

- [ ] **Step 4: Review only the task-owned diff**

Run:

```bash
git diff --check
git diff -- NYCGayBars/Models/Models.swift NYCGayBars/Data/AppData.swift NYCGayBars/Data/Resources/bars.json NYCGayBars/Data/Resources/meta.json NYCGayBars/Data/Resources/neighborhoods.json NYCGayBars/Logic/Stats.swift NYCGayBarsTests/LogicTests.swift docs/nyc-bar-roster-audit-2026-08-20.md
```

Expected: no whitespace errors; every changed line traces to archival behavior, approved records, required neighborhood/borough support, tests, or the cited audit.
