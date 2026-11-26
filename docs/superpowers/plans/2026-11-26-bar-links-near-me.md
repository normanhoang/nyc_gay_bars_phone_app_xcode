# Bar Links + Near-Me Map Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instagram/website (FB/TikTok fallback) link chips on bar pages, plus a map button that toggles between the user's neighborhood and All.

**Architecture:** Optional link fields on `Bar` (decoded from `bars.json`), with pure URL builders in `Logic/BarLinks.swift` and a `BarLinkChips` view under `BarActionPills`. Near-me picks a neighborhood with a pure `Geo.nearMeNeighborhood`. `ExploreView` owns the toggle state and reuses `selectNeighborhood`.

**Tech Stack:** Swift / SwiftUI, iOS 26, XCTest, xcodegen. No new deps.

**Spec:** `docs/superpowers/specs/2026-11-26-bar-links-near-me-design.md`

## Global Constraints

- iOS 26 only. Static content uses `.contentPanel()`; `.glassSurface` is for interactive chrome only. Never put `opacity` on a glass element.
- `.xcodeproj` is generated. After adding files, run `xcodegen generate`.
- Build/test destination: `'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- Links only for **active** bars (`AppData.bars` already excludes archived). `facebook`/`tiktok` only when `instagram` is nil.
- Never write an unsure handle. Unsure ones go on the review list instead.
- Near-me cutoff: nearest active bar **> 5 km** → nil (button hidden).
- No brand assets. Reuse the existing in-repo `InstagramGlyph` drawing for the Instagram chip. Others use SF Symbols (`globe`, etc.).
- Instagram open pattern matches the existing `ExploreView.openInstagram`: try `instagram://user?username=<h>`, fall back to `https://www.instagram.com/<h>`. The `instagram` query scheme is already in `project.yml`.

## Review Focus

1. Bad data in `bars.json` (handle with `@`, trailing slash, URL in the `instagram` field, `http://` website) → chips build broken URLs. A data-integrity test pins the format (Task 3).
2. A bar with both `instagram` and `facebook` set breaks the fallback-only rule. Pinned in the integrity test (Task 3).
3. A user standing exactly on a neighborhood border or in water (outside every polygon) should still get the nearest neighborhood, not nil (Task 4 test).
4. Location arriving *after* the map has appeared → button must appear without reopening the tab. It's derived from `location.coordinate`, a `@Published` value (Task 5 manual check).
5. User taps near-me, then zoom-out→All fires. The button must return to plain, not stay filled (Task 5: active state is derived, never stored as a bool).

---

### Task 1: Link fields + URL builders

**Files:**
- Modify: `NYCGayBars/Models/Models.swift` (struct `Bar`)
- Create: `NYCGayBars/Logic/BarLinks.swift`
- Test: `NYCGayBarsTests/LogicTests.swift` (new `BarLinksTests` class)

**Interfaces:**
- Produces: `Bar.instagram: String?`, `Bar.website: String?`, `Bar.facebook: String?`, `Bar.tiktok: String?` (all `var`, optional, like `description`).
- Produces: `enum BarLinkKind { case instagram, website, facebook, tiktok }`, `struct BarLink: Identifiable { let kind: BarLinkKind; let url: URL; let appURL: URL?; var id: BarLinkKind { kind } }`, and `enum BarLinks { static func links(for bar: Bar) -> [BarLink] }`, ordered instagram, website, facebook, tiktok, with nil/empty fields skipped.

- [ ] **Step 1: Write failing tests.** Build `Bar` values in-test via JSON decode (the memberwise init has many fields). Tests:
  - `testOrderAndSkipsMissing`: bar with `instagram:"eaglenyc"`, `website:"https://www.eagle-ny.com"` → kinds `[.instagram, .website]`.
  - `testInstagramURLs`: `url == https://www.instagram.com/eaglenyc`, `appURL == instagram://user?username=eaglenyc`.
  - `testTikTokURL`: `tiktok:"somebar"` → `url == https://www.tiktok.com/@somebar`, `appURL == nil`.
  - `testNoLinks`: bar with none → `[]`.
  - `testDecodesWithoutLinkFields`: existing `AppData.bar(id:"eagle-nyc")` decodes. Guards old JSON.
- [ ] **Step 2: Run** `xcodebuild … test -only-testing:NYCGayBarsTests/BarLinksTests`. Expected: FAIL (no `BarLinks`).
- [ ] **Step 3: Add fields + implement `BarLinks.links(for:)`.** Website/facebook pass through `URL(string:)`; skip if that returns nil.
- [ ] **Step 4:** `xcodegen generate`, rerun the tests. Expected: PASS.
- [ ] **Step 5: Commit** `feat(links): optional bar link fields + URL builders`.

### Task 2: `BarLinkChips` view on both bar pages

**Files:**
- Create: `NYCGayBars/Components/BarLinkChips.swift`
- Create: `NYCGayBars/Components/InstagramGlyph.swift`. Move `InstagramGlyph` out of `ExploreView.swift:371-414` unchanged except `private` → internal.
- Modify: `NYCGayBars/Screens/BarDetailSheet.swift` (after `BarActionPills`, ~line 44), `NYCGayBars/Screens/QuickLogSheet.swift` (inside `if let bar`, after `BarActionPills`, ~line 41)

**Interfaces:**
- Consumes: `BarLinks.links(for:) -> [BarLink]` (Task 1).
- Produces: `struct BarLinkChips: View { let bar: Bar }`. It renders nothing (`EmptyView`) when there are no links.

- [ ] **Step 1: Implement `BarLinkChips`.** `HStack(spacing: 8)` of equal-width capsule chips, visually identical to `BarActionPills.chipLabel` with no tint (glass capsule, 13pt icon, 14pt semibold label, 9pt vertical padding), `PressableScale` style. Labels: "Instagram", "Website", "Facebook", "TikTok". Icons: `InstagramGlyph(size: 16, corner: 5)`, `globe`, `f.cursive.circle`, `music.note`. Tap: if `appURL` is set, open it with a completion fallback to `url` (same shape as `openInstagram`); otherwise open `url`. Add `.accessibilityLabel("Open \(bar.name) on Instagram")` etc. Padding: `.padding(.top, 8)` at both call sites.
- [ ] **Step 2: Wire into both sheets.** In `QuickLogSheet` the chips must follow the bar swap, since `bar` is the same variable.
- [ ] **Step 3:** `xcodegen generate` + `build`. Expected: `** BUILD SUCCEEDED **`. Re-run the full `test`. Expected: all pass.
- [ ] **Step 4: Commit** `feat(links): link chip row on bar detail + quick log`.

### Task 3: Research + populate `bars.json`

**Files:**
- Modify: `NYCGayBars/Data/Resources/bars.json`
- Test: `NYCGayBarsTests/LogicTests.swift` (`BarLinksTests`)
- Scratch (not committed): `<scratchpad>/links.json` mapping `id → {instagram?, website?, facebook?, tiktok?, confidence, note}`, and `<scratchpad>/apply_links.py`

- [ ] **Step 1: Write data-integrity tests** over `AppData.allBars`:
  - `testInstagramHandlesClean`: each non-nil `instagram` matches `^[A-Za-z0-9._]{1,30}$`.
  - `testTikTokHandlesClean`: same rule, no `@`.
  - `testWebURLsHttps`: `website`/`facebook` start with `https://` and parse as `URL`.
  - `testFallbacksOnlyWithoutInstagram`: no bar has `instagram` and also `facebook` or `tiktok`.
  - `testArchivedHaveNoLinks`: archived bars have all four nil.
  These pass trivially now. Run them to confirm they compile.
- [ ] **Step 2: Research each of the 88 active bars** (web search: `"<name>" <address> instagram` + official site). Write to `links.json` only when the handle/site matches name **and** address/area and has posted within ~12 months. Mark `confidence: "high"`. Anything else gets `confidence: "unsure"` + a note, and is not applied.
- [ ] **Step 3: Apply.** Run `python3 -I apply_links.py <bars.json> <links.json>`. It writes only high-confidence fields, preserves key order and existing 1-space indentation of the file (check with `git diff` that only link keys are added), and drops fallbacks when instagram is present.
- [ ] **Step 4: Run full test suite.** Expected: all pass, including the integrity tests.
- [ ] **Step 5: Commit** `data(links): instagram/website for N active bars`. Deliver the unsure list to the user in chat (bar · candidate · why unsure).

### Task 4: `Geo.nearMeNeighborhood`

**Files:**
- Modify: `NYCGayBars/Logic/Geo.swift`
- Modify: `NYCGayBars/Screens/BarMapView.swift:221-242`. Delete the private `neighborhood(containing:)`/`pointInPolygon` and call the `Geo` versions.
- Test: `NYCGayBarsTests/LogicTests.swift` (`GeoTests`)

**Interfaces:**
- Produces: `static func neighborhood(containing lat: Double, _ lng: Double) -> String?` (moved; the iteration order and algorithm stay as they are in `BarMapView`).
- Produces: `static func nearMeNeighborhood(_ lat: Double, _ lng: Double, maxKm: Double = 5) -> String?`: polygon hit → else nearest bar's `neighborhood` if `distanceMiles * 1.609344 <= maxKm` → else nil. The cutoff is checked in both branches. Containment alone doesn't qualify, since a polygon can extend > 5 km from any bar (Mott Haven).
- [ ] **Step 1: Write failing tests:**
  - `testNearMeInsidePolygon`: Stonewall's coords → `"West Village"` (also assert `neighborhood(containing:)` returns the same).
  - `testNearMeOutsidePolygonsFallsBackToNearestBar`: point in the Hudson off Chelsea `(40.7500, -74.0150)`. Precondition `XCTAssertNil(Geo.neighborhood(containing:…))`, then expect `Geo.nearestBar(…).neighborhood`. If the precondition fails, nudge west until it's outside, then hard-code that point.
  - `testNearMeFarAwayIsNil`: Albany `(42.6526, -73.7562)` → nil.
  - `testNearMeCutoffBoundary`: `maxKm: 0.01` at a point 1 km from the nearest bar → nil. `maxKm: 5` → non-nil.
- [ ] **Step 2: Run** `-only-testing:NYCGayBarsTests/GeoTests`. Expected: FAIL (undefined).
- [ ] **Step 3: Implement + update `BarMapView` to call `Geo.neighborhood(containing:)`.**
- [ ] **Step 4: Run full tests.** Expected: PASS. Build succeeds, and outline taps still use the same logic.
- [ ] **Step 5: Commit** `feat(map): Geo.nearMeNeighborhood + shared polygon hit test`.

### Task 5: Near-me button on the Explore map

**Files:**
- Modify: `NYCGayBars/Screens/ExploreView.swift` (state ~line 15; map `ZStack` ~line 273)

**Interfaces:**
- Consumes: `Geo.nearMeNeighborhood(_:_:)` (Task 4), existing `selectNeighborhood(_:)`, `coords`.

- [ ] **Step 1: Implement.**
  - `@State private var nearMeHood: String?`
  - `private var nearMeTarget: String? { coords.flatMap { Geo.nearMeNeighborhood($0.lat, $0.lng) } }`
  - `private var nearMeActive: Bool { nearMeHood != nil && neighborhood == nearMeHood }`
  - Button rendered in map mode only, when `nearMeTarget != nil`: `.overlay(alignment: .topTrailing)` on the map `ZStack`, 44pt glass circle (`glassSurface(radius: 999, bordered: true)`), icon `location` (inactive) / `location.fill` tinted `Palette.primary` (active), `PressableScale`, `Haptics.light()`. Keep it clear of the "No bars match" banner (12pt top / 16pt trailing padding is the builder's call).
  - Tap: if `nearMeActive` → `selectNeighborhood("All")`. Else `nearMeHood = nearMeTarget`, `selectNeighborhood(nearMeTarget!)`.
  - Accessibility label: "Zoom to my neighborhood" / "Show all neighborhoods".
- [ ] **Step 2: Build.** Expected: `** BUILD SUCCEEDED **`. Full `test` passes.
- [ ] **Step 3: Manual check on the simulator** with a custom location set near Chelsea (`xcrun simctl location <udid> set 40.7465,-74.0014`). Check that:
  - the button appears;
  - tap → Chelsea chip selected, pins + callout shown;
  - tap → All;
  - tap, then pick another chip → button goes plain;
  - with location set to Albany, the button is hidden.
  Screenshot via the temporary `START_PAGE` scaffold per CLAUDE.md, then revert it.
- [ ] **Step 4: Commit** `feat(map): near-me neighborhood toggle button`.
