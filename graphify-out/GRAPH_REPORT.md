# Graph Report - .  (2026-07-04)

## Corpus Check
- 59 files · ~364,929 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 437 nodes · 888 edges · 29 communities (27 shown, 2 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 54 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Stats & Badge Logic|Stats & Badge Logic]]
- [[_COMMUNITY_DayKey Date Logic|DayKey Date Logic]]
- [[_COMMUNITY_Confetti & Dialog UI|Confetti & Dialog UI]]
- [[_COMMUNITY_App Data & Geo|App Data & Geo]]
- [[_COMMUNITY_Badges & Drink Utilities|Badges & Drink Utilities]]
- [[_COMMUNITY_Location & Navigation Shell|Location & Navigation Shell]]
- [[_COMMUNITY_Architecture Docs & App Store|Architecture Docs & App Store]]
- [[_COMMUNITY_Explore Screen|Explore Screen]]
- [[_COMMUNITY_Map Framing|Map Framing]]
- [[_COMMUNITY_Drink Logging & Haptics|Drink Logging & Haptics]]
- [[_COMMUNITY_Motion Springs|Motion Springs]]
- [[_COMMUNITY_Flow Layout|Flow Layout]]
- [[_COMMUNITY_Screen Scaffolding|Screen Scaffolding]]
- [[_COMMUNITY_Progress & Splash|Progress & Splash]]
- [[_COMMUNITY_Count-Up Animation|Count-Up Animation]]
- [[_COMMUNITY_Stats Screenshot|Stats Screenshot]]
- [[_COMMUNITY_Month Calendar|Month Calendar]]
- [[_COMMUNITY_Explore Screenshot|Explore Screenshot]]
- [[_COMMUNITY_Visit Coding Keys|Visit Coding Keys]]
- [[_COMMUNITY_History Screenshot|History Screenshot]]
- [[_COMMUNITY_Badge Toast|Badge Toast]]
- [[_COMMUNITY_Bar List Item|Bar List Item]]
- [[_COMMUNITY_Search Box|Search Box]]
- [[_COMMUNITY_App Entry Point|App Entry Point]]
- [[_COMMUNITY_App Icon Branding|App Icon Branding]]
- [[_COMMUNITY_Splash Logo Branding|Splash Logo Branding]]
- [[_COMMUNITY_Filter Chips|Filter Chips]]
- [[_COMMUNITY_Segmented Toggle|Segmented Toggle]]
- [[_COMMUNITY_Zip Note|Zip Note]]

## God Nodes (most connected - your core abstractions)
1. `Visit` - 34 edges
2. `SwiftUI` - 29 edges
3. `VisitsStore` - 29 edges
4. `Bar` - 24 edges
5. `Color` - 23 edges
6. `BarMapView` - 21 edges
7. `Stats` - 18 edges
8. `AppData` - 16 edges
9. `ExploreView` - 15 edges
10. `Badge` - 14 edges

## Surprising Connections (you probably didn't know these)
- `Location When-In-Use Permission Declaration` --semantically_similar_to--> `On-Device-Only Location Use`  [INFERRED] [semantically similar]
  project.yml → docs/privacy.html
- `Simulator Screenshot and XCUITest Workflow` --conceptually_related_to--> `App Store Connect Assets Page`  [INFERRED]
  CLAUDE.md → docs/appstore/index.html
- `Export Compliance via ITSAppUsesNonExemptEncryption` --references--> `NYCGayBars App Target (project.yml)`  [INFERRED]
  docs/appstore/index.html → project.yml
- `Third-Party Instagram Link Handoff` --conceptually_related_to--> `NYCGayBars App Target (project.yml)`  [INFERRED]
  docs/privacy.html → project.yml
- `XcodeGen-Generated Xcode Project` --references--> `NYCGayBars App Target (project.yml)`  [EXTRACTED]
  CLAUDE.md → project.yml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **App Store Submission Flow** — docs_appstore_index_asc_assets, docs_privacy_privacy_policy, docs_support_support_page, docs_appstore_index_data_not_collected, docs_appstore_index_age_rating_17, docs_appstore_index_export_compliance [EXTRACTED 1.00]
- **Privacy-by-Design: Fully Local, No Collection** — docs_privacy_local_only_data, docs_privacy_on_device_location, docs_appstore_index_data_not_collected, project_location_usage, readme_nyc_gay_bars_app [INFERRED 0.85]
- **Visit Logging and Badge Reconcile Flow** — claude_visitsstore_persistence, claude_badges_reconcile, claude_daykey_zero_indexed_month, claude_navigation_shell [EXTRACTED 1.00]
- **Stats Tab Stat Card Layout** — docs_appstore_screenshots_page_1_totals_cards, docs_appstore_screenshots_page_1_favorite_bar_card, docs_appstore_screenshots_page_1_top_drink_card, docs_appstore_screenshots_page_1_biggest_night_card, docs_appstore_screenshots_page_1_longest_streak_card [EXTRACTED 1.00]

## Communities (29 total, 2 thin omitted)

### Community 0 - "Stats & Badge Logic"
Cohesion: 0.10
Nodes (26): Decoder, Hashable, Identifiable, NYCGayBars, Void, VisitCard, BoroughProgress, NeighborhoodProgress (+18 more)

### Community 1 - "DayKey Date Logic"
Cohesion: 0.10
Nodes (18): Calendar, Date, DateFormatter, ISO8601DateFormatter, DayKey, Bool, String, drinks (+10 more)

### Community 2 - "Confetti & Dialog UI"
Cohesion: 0.09
Nodes (25): Confetti, Piece, CGFloat, Double, Int, Action, ConfirmDialog, Style (+17 more)

### Community 3 - "App Data & Geo"
Cohesion: 0.13
Nodes (16): Codable, AppData, LatLng, Meta, Region, Double, String, T (+8 more)

### Community 4 - "Badges & Drink Utilities"
Cohesion: 0.09
Nodes (18): Combine, Foundation, BadgeTile, Bool, String, drinkEmoji(), String, Badge (+10 more)

### Community 5 - "Location & Navigation Shell"
Cohesion: 0.08
Nodes (20): CLLocation, CLLocationManager, CLLocationManagerDelegate, CoreLocation, Equatable, Error, NSObject, HistoryView (+12 more)

### Community 6 - "Architecture Docs & App Store"
Cohesion: 0.09
Nodes (25): BadgesStore Reconcile Pattern, Generated JSON Data Resources (bars/neighborhoods/zips/meta), DayKey 0-Indexed Month Gotcha, Liquid Glass: Chrome vs Panels Policy, Map Camera Framing and Snap-Back Logic, RootTabView Paging Navigation Shell, Neighborhood Polygon Cleaning Pipeline, Simulator Screenshot and XCUITest Workflow (+17 more)

### Community 7 - "Explore Screen"
Cohesion: 0.16
Nodes (13): Never, String, Void, ZipQuery, ExploreView, Bool, Double, Int (+5 more)

### Community 8 - "Map Framing"
Cohesion: 0.19
Nodes (12): MapCameraPosition, MapKit, MKCoordinateRegion, BarMapView, Bool, CLLocationCoordinate2D, Double, Int (+4 more)

### Community 9 - "Drink Logging & Haptics"
Cohesion: 0.23
Nodes (5): DrinkLogger, Int, String, Void, Haptics

### Community 10 - "Motion Springs"
Cohesion: 0.22
Nodes (8): ButtonStyle, Configuration, Anim, PressableScale, CGFloat, View, Void, View

### Community 11 - "Flow Layout"
Cohesion: 0.25
Nodes (8): CGRect, CGSize, Layout, FlowLayout, CGFloat, Void, ProposedViewSize, Subviews

### Community 12 - "Screen Scaffolding"
Cohesion: 0.22
Nodes (4): View, AppBackground, SwiftUI, UIKit

### Community 13 - "Progress & Splash"
Cohesion: 0.27
Nodes (6): ProgressBar, Double, Splash, InstagramGlyph, CGFloat, View

### Community 14 - "Count-Up Animation"
Cohesion: 0.31
Nodes (7): AnimatableModifier, Font, CountText, CountUp, Content, Double, Int

### Community 15 - "Stats Screenshot"
Cohesion: 0.25
Nodes (8): Biggest Night Card, Borough Progress Section (Manhattan/Brooklyn/Queens), Favorite Bar Card, Longest Streak Card, Recent Badges Section (5/30), Stats Tab Screenshot, Top Drink Card, Totals Cards (Drinks/Drink-Days/Bars)

### Community 16 - "Month Calendar"
Cohesion: 0.46
Nodes (4): MonthCalendar, Int, Set, String

### Community 17 - "Explore Screenshot"
Cohesion: 0.33
Nodes (7): Explore Tab (Map Mode) Screenshot, Floating Glass Tab Bar (Explore/Stats/History), Map/List Mode Toggle, Neighborhood Filter Chips, Pink Neighborhood Polygon Overlays on MapKit, Search Bars/Neighborhoods/ZIP Field, Visited Progress (8/81, Just Getting Started)

### Community 18 - "Visit Coding Keys"
Cohesion: 0.33
Nodes (6): CodingKey, CodingKeys, barId, date, id, note

### Community 19 - "History Screenshot"
Cohesion: 0.47
Nodes (6): Add Drinks For This Day (Backdated Logging), Clear History Button, Selected Day Detail (Bars/Drinks Summary), History Tab Screenshot, Month Calendar with Logged-Day Markers, Visit Card (Bar, Drink Chips, Note)

### Community 20 - "Badge Toast"
Cohesion: 0.33
Nodes (5): BadgeToast, Bool, CGFloat, Double, ToastBanner

### Community 21 - "Bar List Item"
Cohesion: 0.33
Nodes (5): BarListItem, Bool, Double, Int, Void

### Community 22 - "Search Box"
Cohesion: 0.40
Nodes (4): SearchBox, Bool, String, Void

### Community 23 - "App Entry Point"
Cohesion: 0.50
Nodes (3): App, NYCGayBarsApp, Scene

### Community 24 - "App Icon Branding"
Cohesion: 0.67
Nodes (4): App Icon (Martini Glass with Progress Pride Flag), Dark Purple/Magenta Brand Palette, Martini Glass / Cocktail Motif, Progress Pride Flag Motif

### Community 25 - "Splash Logo Branding"
Cohesion: 0.67
Nodes (4): App Splash Logo, Martini Glass Motif, Progress Pride Flag Fill, NYC Skyscraper Cocktail Pick

### Community 27 - "Segmented Toggle"
Cohesion: 0.50
Nodes (3): SegmentedToggle, Int, String

## Knowledge Gaps
- **33 isolated node(s):** `destructive`, `primary`, `cancel`, `Anim`, `id` (+28 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Bar` connect `Stats & Badge Logic` to `DayKey Date Logic`, `Confetti & Dialog UI`, `App Data & Geo`, `Explore Screen`, `Map Framing`, `Bar List Item`?**
  _High betweenness centrality (0.113) - this node is a cross-community bridge._
- **Why does `Visit` connect `Stats & Badge Logic` to `DayKey Date Logic`, `App Data & Geo`, `Badges & Drink Utilities`, `Location & Navigation Shell`, `Drink Logging & Haptics`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Why does `SwiftUI` connect `Screen Scaffolding` to `Stats & Badge Logic`, `Confetti & Dialog UI`, `Badges & Drink Utilities`, `Location & Navigation Shell`, `Explore Screen`, `Map Framing`, `Drink Logging & Haptics`, `Motion Springs`, `Flow Layout`, `Progress & Splash`, `Count-Up Animation`, `Badge Toast`, `Bar List Item`, `Search Box`, `App Entry Point`, `Filter Chips`, `Segmented Toggle`, `Zip Note`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `Visit` (e.g. with `.count()` and `.clearVisit()`) actually correct?**
  _`Visit` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `VisitsStore` (e.g. with `NYCGayBarsApp` and `.content()`) actually correct?**
  _`VisitsStore` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `destructive`, `primary`, `cancel` to the rest of the system?**
  _38 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Stats & Badge Logic` be split into smaller, more focused modules?**
  _Cohesion score 0.0996078431372549 - nodes in this community are weakly interconnected._