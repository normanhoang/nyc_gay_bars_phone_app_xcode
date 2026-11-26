# Bar links + "near me" map button — design

Date: 2026-11-26 · Size: small change

## Intent

1. **Bar links.** Let the user check what's on at a bar *tonight* before going.
   Bars post flyers/party lineups on Instagram, so Instagram leads; the website
   is second (often holds the event calendar when the IG grid is stale).
2. **Near-me map button.** One tap frames the map on the neighborhood the user
   is in; a second tap zooms back out to All.

## Goals / non-goals / anti-goals

- Goals: links on every active bar we can confidently source; near-me button on
  the Explore map.
- Non-goals: links for archived bars; in-app web view; showing event content
  in-app; links in list rows.
- Anti-goals: a wrong/impostor handle (worse than none); a near-me button that
  lands somewhere arbitrary when the user isn't near any bar.

## Approaches (decided)

- **Link data in `bars.json`** (chosen) vs. a separate `links.json` keyed by bar
  id — rejected: second lookup + a file that drifts as bars are added.
- **UI shape A — separate row of link chips** (chosen, user pick) vs. B — one
  best-link chip inside the existing row (hides website when IG exists).
- **Near-me logic in `Geo` (pure, tested), state in `ExploreView`** (chosen) vs.
  inside `BarMapView` — rejected: untestable, splits the filter state.

## Design

### Data
- New optional fields on `Bar` and in `bars.json`: `instagram` (handle, no `@`),
  `website` (full https URL), `facebook` (URL), `tiktok` (handle).
- `facebook`/`tiktok` populated **only when a bar has no Instagram**.
- Filled via a throwaway Python script editing `bars.json` directly (repo
  convention); 88 active bars researched, 12 archived skipped.
- Research bar: handle/site must match the bar's name **and** address/area, and
  be recently active. Ambiguous or dormant (>1 yr) → not written; goes on a
  review list for the user (bar, candidate, why unsure).

### Link UI — `Components/BarLinkChips.swift`
- Row of chips directly under `BarActionPills`, in both `BarDetailSheet` and
  `QuickLogSheet`. Same chip look as `BarActionPills` (glass capsule, icon +
  label, equal width).
- Order: Instagram, Website, then Facebook / TikTok fallbacks.
- Instagram opens the app if installed (`instagram://user?username=`), else
  `https://instagram.com/<handle>`; others open the URL via `openURL`.
- Bar with no links → row not rendered.
- Instagram has no SF Symbol: use `camera` for Instagram, `globe` for Website,
  `f.square`-style / `music.note` for FB/TikTok (builder's call on exact glyphs;
  no brand assets).
- No privacy-policy change: opening an outside link sends no app data.

### Near-me button
- `Geo.nearMeNeighborhood(lat, lng) -> String?`:
  1. neighborhood polygon containing the point, else
  2. neighborhood of the nearest bar (existing proximity ranking),
  3. `nil` if the nearest active bar is > 5 km away.
  Unit-tested in `LogicTests`.
- `ExploreView` map mode: glass circle button, top-right, `location` arrow
  icon. Hidden when location is unknown/denied or `nearMeNeighborhood` is nil.
- Tap (inactive) → `selectNeighborhood(hood)` — same path as tapping an outline:
  chip selected, pins shown, camera framed, coverage callout shown. Button turns
  filled/active (`nearMeHood = hood`).
- Tap (active) → `selectNeighborhood("All")`, button returns to plain.
- Active is derived: `nearMeHood != nil && neighborhood == nearMeHood`. Any other
  neighborhood change (chip, outline tap, zoom-out→All) makes it plain again; the
  next tap zooms to the user's neighborhood again.
- Map mode only.

## Left to the builder
- Exact icons, chip spacing, button padding relative to the search bar.
- Whether polygon containment reuses `BarMapView.pointInPolygon` (move it to
  `Geo`) — preferred, so it's tested and shared.
