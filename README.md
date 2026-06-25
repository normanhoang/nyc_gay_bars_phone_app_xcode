# NYC Gay Bars — native iOS (SwiftUI)

A tracker for NYC gay bars: browse bars in a list or map, log drinks (today or
backdated), and review history, stats, and earned badges. Single-user, fully
local (no accounts, no network at runtime). Native Swift/SwiftUI port of the
original Expo/React Native app.

## Requirements

- Xcode 26+ (uses SwiftUI's native Liquid Glass `.glassEffect`)
- iOS 26 deployment target
- [`xcodegen`](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
xcodegen generate                                   # (re)create NYCGayBars.xcodeproj from project.yml
open NYCGayBars.xcodeproj                            # then run in Xcode, or:

xcodebuild -scheme NYCGayBars \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
xcodebuild -scheme NYCGayBars \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test   # unit tests
```

To run on a device, open the project in Xcode and select your Apple Developer
team under **Signing & Capabilities** (a free personal team works for 7-day
installs). Bundle id: `com.normanhoang.nycgaybars`.

## Structure (`NYCGayBars/`)

- `Models/` — `Bar`, `Visit`, `DrinkEntry`, `Badge`
- `Data/` — `AppData` loads bundled JSON in `Data/Resources/`
- `Logic/` — `DayKey`, `Drinks`, `Geo`, `Stats` (the 30 badges), `ZipQuery`
- `Stores/` — `VisitsStore`, `BadgesStore` (`@Published` state, UserDefaults persistence)
- `Services/` — `LocationManager` (CoreLocation), `Haptics`
- `Theme/` — `Palette`, `AppBackground`, `Glass`
- `Components/` — reusable views (toggle, chips, calendar, tiles, toast, confetti…)
- `Screens/` — `RootTabView`, `ExploreView`, `BarMapView`, `StatsView`, `HistoryView`,
  `BarDetailSheet`, `DrinkLogger`, `LogDayPicker`

## Data pipeline

The bar dataset, neighborhood polygons, and ZIP centroids are generated at build
time and bundled as JSON — the app needs no map API key or network at runtime.
Source of truth lives in `legacy-expo/` (`gay_bars.csv` + the `scripts/*.mjs`
generators). To refresh:

```bash
cd legacy-expo
node scripts/geocode-bars.mjs          # gay_bars.csv -> lib/bars.ts
node scripts/build-neighborhoods.mjs   # lib/bars.ts  -> lib/neighborhoods.ts
node scripts/build-zips.mjs            # US Census    -> lib/zips.ts
node scripts/export-swift-data.mjs     # lib/*.ts     -> NYCGayBars/Data/Resources/*.json
```

## `legacy-expo/`

The original Expo/React Native app, kept for reference and as the dataset's
source of truth. Not part of the Xcode build.
