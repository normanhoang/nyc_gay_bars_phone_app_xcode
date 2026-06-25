# NYC Gay Bar Tracker 🏳️‍🌈🍸

A mobile app for exploring NYC's gay bars and keeping track of your nights out. Browse 72 curated bars across 11 neighborhoods on a map or in a list, log what you drank at each one, and earn badges as you work your way through the scene.

Built with Expo and designed to run in **Expo Go** — no native build, no API keys, and all your data stays on your device.

## Features

- **Explore** — searchable bar list and an interactive map (Apple Maps on iOS) with neighborhood outlines, distance-to-bar, nearest-first sorting, and location-aware filter chips. Zoom out on the map to jump back to the city-wide view.
- **Drink logging** — tap a bar and count your drinks by type (beer, cocktail, wine, shot, seltzer, non-alcoholic, or anything custom), with a note for the night. Forgot to log last night? Backdate drinks to any past day from the History calendar.
- **History** — a month calendar of your drink days, with per-day bar and drink breakdowns, plus JSON export/import of all your data.
- **Stats & badges** — all-time totals, favorite bar, top drink, biggest night, neighborhood progress, and **30 earnable badges** (from 🍻 First Drink to 👑 Scene Conqueror), with the four most recently earned on display.

## Getting started

Prerequisites: Node 18+, npm, and the [Expo Go](https://expo.dev/go) app (SDK 54) on your phone — or an iOS Simulator / Android emulator.

```bash
npm install
npm start          # scan the QR code with Expo Go
```

Or target a simulator directly:

```bash
npm run ios
npm run android
npm run web        # web fallback (the map renders as a list)
```

### Verifying changes

```bash
npx tsc --noEmit                                      # type-check
npm test                                              # unit tests (lib/)
npx expo export --platform ios --output-dir /tmp/exp  # full bundle compile
```

## Tech stack

- [Expo SDK 54](https://docs.expo.dev/versions/v54.0.0/) / React Native 0.81 / React 19
- [Expo Router](https://docs.expo.dev/router/introduction/) — file-based navigation (`app/`)
- [NativeWind 4](https://www.nativewind.dev/) — Tailwind classes on React Native components
- [react-native-maps](https://github.com/react-native-maps/react-native-maps) — works in Expo Go, no key needed
- AsyncStorage for persistence — visits, visited flags, and badge earn dates never leave the device
- TypeScript (strict)

## The bar data

The bar list is a curated static dataset in [gay_bars.csv](gay_bars.csv) (name, neighborhood, address, vibe tags).

Two build-time scripts turn the CSV into app data, so the app needs no geocoding or map API at runtime:

```bash
node scripts/geocode-bars.mjs           # CSV → lib/bars.ts (US Census → Nominatim geocoding)
node scripts/build-neighborhoods.mjs    # lib/bars.ts → lib/neighborhoods.ts (outline polygons)
```

Edit the CSV (not the generated `lib/bars.ts` / `lib/neighborhoods.ts`) and re-run both scripts to change the bar list.

## Project layout

```
app/                # Expo Router screens
  (tabs)/           #   Explore · Stats · History
  bar/[id].tsx      #   drink logger modal (supports ?day= for backdating)
  log/[day].tsx     #   bar picker for adding drinks to a past day
components/         # BarMap (+ web stand-in), DrinkLogger, MonthCalendar, …
lib/                # data, geo helpers, stats/badges, context providers
scripts/            # build-time data generation (see above)
gay_bars.csv        # the source-of-truth bar list
```

See [CLAUDE.md](CLAUDE.md) for deeper architecture notes and development conventions.
