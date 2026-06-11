# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important

Read the exact versioned docs at https://docs.expo.dev/versions/v54.0.0/ before writing any code. Expo APIs change significantly between SDK versions.

## Commands

```bash
npm start          # Start Expo dev server (shows QR code for Expo Go)
npm run ios        # Start with iOS simulator
npm run android    # Start with Android emulator
npm run web        # Start for browser
```

There is no lint script configured. To verify changes:

```bash
npx tsc --noEmit                          # type-check (strict mode)
npm test                                  # Jest (jest-expo) unit tests for lib/ (run one: npx jest stats)
npx expo export --platform ios --output-dir /tmp/exp   # full bundle compile — catches Metro/Babel/resolution errors tsc can't
```

When adding new Expo/React Native packages, always use `npx expo install <package>` instead of `npm install` — this resolves the SDK 54 compatible version automatically. Some packages (e.g. NativeWind) trip npm's peer-dependency resolver because Expo pins `react`; add `--legacy-peer-deps` when a plain `npm install` fails with an `ERESOLVE` error.

## Stack

- **Expo SDK 54** — targeted at Expo Go 54.x on device
- **React Native 0.81** / **React 19.1**
- **Expo Router 6** — file-based routing via the `app/` directory
- **NativeWind 4** — Tailwind CSS utility classes (`className`) on React Native components, backed by Tailwind v3
- **TypeScript** in strict mode

## What this app is

A tracker for **NYC gay bars**: browse bars in a list or map view, log how many (and what kind of) drinks you've had at each bar (today or backdated to a past day), and review history, stats, and earned badges. The bar list is a curated static dataset — gaycities.com blocks scraping (Cloudflare), and open sources (OSM Overpass, Wikidata) were tested and cover only a fraction of the bars.

## Architecture

### Routing (`app/`)
Expo Router maps files in `app/` to routes automatically. The root layout (`app/_layout.tsx`) mounts `VisitsProvider` → `BadgesProvider` (inside `GestureHandlerRootView` + `SafeAreaProvider`), imports `global.css`, then renders a `<Stack>`.

- `app/(tabs)/` — bottom tabs, in order: `index.tsx` (**Explore** — List/Map toggle), `stats.tsx` (**Stats** — totals, stat cards, recent badges + all-badges Modal), `history.tsx` (**History** — month calendar; resets to today on tab focus).
- `app/bar/[id].tsx` — **modal** stack screen for logging drinks at one bar. Accepts an optional `?day=<dayKey>` param to log against a past day instead of today.
- `app/log/[day].tsx` — modal bar picker reached from History's "Add drinks for this day"; it `router.replace`s into `bar/[id]?day=` so closing the logger returns to History.

### Data (`lib/` + generated files)
- `lib/types.ts` — `Bar`, `Visit`, `DrinkEntry`.
- `lib/bars.ts` (the `BARS` array, `NYC_REGION`, `NEIGHBORHOODS`, `getBarById`) and `lib/neighborhoods.ts` (outline polygons) are **generated — do not edit by hand**. Edit `gay_bars.csv`, then re-run `node scripts/geocode-bars.mjs` (build-time geocoding; the app needs no map API key or network at runtime) and `node scripts/build-neighborhoods.mjs` (fetches NYC Open Data boundaries, falls back to convex hulls of each neighborhood's bars).
- `lib/drinks.ts` — `PRESET_DRINKS` and `drinkEmoji`.
- `lib/geo.ts` — `distanceMiles`, proximity ordering for the filter chips, per-neighborhood bounding boxes, and `fullyVisibleNeighborhoods(region)` used by the map's zoom-out detection.
- `lib/stats.ts` — pure functions over `visits` (totals, favorite bar, streaks computed from noon-stamped day timestamps) plus `badges()`, which returns exactly **30 badges**.

### State (two context providers)
- `lib/VisitsContext.tsx` — `visits: Visit[]` plus a manual `visitedBars: string[]` "been here" flag list, persisted to AsyncStorage (`@gaybars/visits`, `@gaybars/visited`): hydrated on mount, saved on every change. A visit aggregates drinks per type for one **local calendar day** (`dayKey`). `logDrink`/`removeDrink`/`getVisitFor` take an optional `day` param (defaults to today); backdated visits are stamped **noon local time** so the stored ISO date round-trips `dayKey` across timezones, and future days are refused. Time-of-day badge logic (e.g. Night Owl) relies on this noon-stamping — only live logging can produce small-hours timestamps.
- `lib/BadgesContext.tsx` — computes badges from visits and persists **first-earned timestamps** (`@gaybars/badgeDates`); newly earned badges get stamped, reverted ones (e.g. after Clear History) get un-stamped. The Stats screen shows the 4 most recently earned.

Screens consume state via the `useVisits()` / `useBadges()` hooks.

### Map behavior (`components/BarMap.tsx`) — non-obvious rules
- Uses `react-native-maps`, which **works in Expo Go on SDK 54** with no native setup (Apple Maps on iOS, no API key). Do not switch to `expo-maps` — it requires a custom dev build and would break the Expo Go target. `MapView` needs explicit dimensions via `style`, not `className`.
- `onRegionChangeComplete`'s `details.isGesture` is **Google Maps only** — always undefined on Apple Maps. User gestures are distinguished from the component's own `animateToRegion` calls by timestamp (`programmaticMoveAt`, 800ms window).
- Zooming out far enough to fully contain 2+ neighborhoods **and** 1.2× past the last framed region (the slack matters: Brooklyn's framed region already fully contains three Manhattan neighborhoods) switches the filter to "All" **without moving the camera** (`suppressNextFrame`). The camera only re-frames when the user explicitly re-presses a chip, signalled by the `frameNonce` counter prop from the Explore screen.
- `BarMap.web.tsx` is a list-based web stand-in (Metro picks it automatically on web); keep its `Props` type in sync with the native one.

### Styling
NativeWind lets you use `className` on any React Native core component. The Tailwind config scans `app/**` and `components/**`. All Tailwind directives live in `global.css`, which is imported once in `app/_layout.tsx`.

Do not use `StyleSheet.create` for new code — use `className` instead. Conditional classes must use fully-spelled-out class names in ternaries (not string concatenation), so NativeWind's static scanner can detect them.

### Liquid Glass surfaces — non-obvious rules
The app uses an Apple "Liquid Glass" look. `components/Glass.tsx` is the one surface primitive: on **iOS 26+** it renders the native `GlassView` (`expo-glass-effect`); everywhere else it falls back to a frosted `BlurView` (`expo-blur`) with a hairline white border + faint white fill. Both ship in Expo Go on SDK 54. Use `<Glass className="rounded-3xl p-4">…</Glass>` for cards/panels instead of `bg-ink-card`.
- **Never put an `opacity-*` utility on a `Glass` element or any ancestor** — native `GlassView` errors on sub-1 opacity. To dim or tint, use a translucent `bg-white/[0.06]` / `bg-black/40` fill or an absolutely-positioned overlay child (see `BadgeTile`, `BarListItem`).
- Glass needs colour behind it to refract. `components/AppBackground.tsx` (an `expo-linear-gradient` wash) is rendered behind every screen — the `(tabs)` layout provides it for all three tabs (scenes are `transparent`); modal/root screens (`bar/[id]`, `log/[day]`, `sign-in`, the badges Modal) each render their own `<AppBackground />`. Tab screens own their top safe-area padding (`insets.top`) since the native headers are hidden.
- For many small repeated elements (filter chips, tag pills) use a cheap translucent `bg-white/[0.08] border border-white/10` instead of a real `Glass`/blur per item, to avoid mounting dozens of blur views.

### Key config files
- `babel.config.js` — sets `jsxImportSource: "nativewind"`, includes the `nativewind/babel` preset, and lists `react-native-worklets/plugin` **last** (reanimated v4 moved its babel plugin into `react-native-worklets`)
- `metro.config.js` — wraps default Expo config with `withNativeWind`, pointing at `global.css`
- `tailwind.config.js` — includes `nativewind/preset`, sets content paths, and defines the `primary`/`ink` color palette
- `nativewind-env.d.ts` — provides TypeScript types for `className` prop
- `babel-preset-expo` is pinned as a direct devDependency so Babel can resolve it from the project root (npm nests it under `expo/` otherwise)
