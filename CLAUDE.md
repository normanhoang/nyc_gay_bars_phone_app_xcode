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
- `app/bar/[id].tsx` — **modal** stack screen for logging drinks at one bar (opened from Explore, logs today). Thin wrapper around `components/BarDetailSheet.tsx`, which holds the entire logging UI.
- `app/log/[day].tsx` — modal bar picker reached from History's "Add drinks for this day". Picking a bar does **not** navigate — it renders `BarDetailSheet` (with the past `day`) in-place as a slide-up overlay inside the same modal, so swipe-down/close always lands back on History. Stacked modals were abandoned: pushing the logger left the picker visible behind a swipe-dismiss, and removing the picker from the stack mid-presentation made iOS re-run the modal animations.

### Data (`lib/` + generated files)
- `lib/types.ts` — `Bar`, `Visit`, `DrinkEntry`.
- `lib/bars.ts` (the `BARS` array, `NYC_REGION`, `NEIGHBORHOODS`, `getBarById`) and `lib/neighborhoods.ts` (outline polygons) are **generated — do not edit by hand**. Edit `gay_bars.csv`, then re-run `node scripts/geocode-bars.mjs` (build-time geocoding; the app needs no map API key or network at runtime) and `node scripts/build-neighborhoods.mjs` (fetches NYC Open Data boundaries, falls back to convex hulls of each neighborhood's bars).
- `lib/drinks.ts` — `PRESET_DRINKS` and `drinkEmoji`.
- `lib/geo.ts` — `distanceMiles`, proximity ordering for the filter chips, per-neighborhood bounding boxes, and `fullyVisibleNeighborhoods(region)` used by the map's zoom-out detection.
- `lib/stats.ts` — pure functions over `visits` (totals, favorite bar, streaks computed from noon-stamped day timestamps) plus `badges()`, which returns exactly **30 badges**.

### State (two context providers)
- `lib/VisitsContext.tsx` — `visits: Visit[]` plus a manual `visitedBars: string[]` "been here" flag list, persisted to **Supabase** (tables `visits`, `visited_bars`) scoped to `auth.uid()`, hydrated on mount with a one-time migration from the legacy AsyncStorage keys. A visit aggregates drinks per type for one **local calendar day** (`dayKey`). A visit may have **zero drinks** — `setVisited(barId, true, day?)` records a zero-drink "check-in" so a bar shows on that day's calendar even with no drinks logged; these count as visits/nights-out everywhere (drink-count stats like Century Club sum actual drinks, so 0-drink visits don't inflate them). `logDrink`/`removeDrink`/`getVisitFor` take an optional `day` param (defaults to today); backdated visits are stamped **noon local time** so the stored ISO date round-trips `dayKey` across timezones, and future days are refused. Time-of-day badge logic (e.g. Night Owl) relies on this noon-stamping — only live logging can produce small-hours timestamps.
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
The app uses an Apple "Liquid Glass" look. `components/Glass.tsx` is the surface primitive for **chrome and controls only** (search bars, toggles, buttons, toasts, tab/header backgrounds, interactive list rows): on **iOS 26+** it renders the native `GlassView` (`expo-glass-effect`); everywhere else a frosted `BlurView` (`expo-blur`) + faint white fill. Both ship in Expo Go on SDK 54.
- **Glass vs. panel split**: static *content* (stat cards, calendar, visit cards, badge tiles) must NOT use `Glass` — native glass draws an un-disableable luminous rim that reads as a border. Use a plain `View className="rounded-3xl bg-white/[0.05] p-4"` panel instead.
- **`Glass` API**: corner radius and borders are **props, not classes** — `<Glass radius={16} bordered className="flex-row px-3">`. `className` carries layout/padding only. The radius must be a prop because the native glass layer needs it to shape itself (a `rounded-*` class on the wrapper rect-clips the glass rim → jagged edges); `bordered` draws a `StyleSheet.hairlineWidth` overlay (1px utility borders on the clipping view alias badly). `borderColor` overrides the default white hairline (e.g. the primary-tinted visited rows).
- **Never put an `opacity-*` utility on a `Glass` element or any ancestor** — native `GlassView` errors on sub-1 opacity. To dim or tint inside glass, use a translucent fill or an overlay child (see `BarListItem`'s visited wash). Plain panels are exempt (e.g. `BadgeTile` dims unearned content with `opacity-40`).
- Glass needs colour behind it to refract. `components/AppBackground.tsx` (an `expo-linear-gradient` wash) is rendered behind every screen — the `(tabs)` layout provides it for all three tabs (scenes are `transparent`); modal/root screens (`bar/[id]`, `log/[day]`, `sign-in`, the badges Modal) each render their own `<AppBackground />`. Tab screens own their top safe-area padding (`insets.top`) since the native headers are hidden.
- For many small repeated elements (filter chips, tag pills) use a cheap translucent `bg-white/[0.08] border border-white/10` instead of a real `Glass`/blur per item, to avoid mounting dozens of blur views.

### Motion primitives (`react-native-reanimated`, Expo Go-safe)
Reusable animation components, all pure JS/Reanimated (no native deps beyond what's installed):
- `components/PressableScale.tsx` — Pressable that springs to 0.97 while held (the Apple "squish"). Scale lives on an inner `Animated.View` (plain `transform` style, not className — `Animated.View` isn't NativeWind-interop'd, same trap as `Glass`). Use for cards/buttons instead of `active:opacity-*`.
- `components/CountUp.tsx` — animates a number from its current value to the new one. Remount via a `key` (e.g. a focus counter bumped in `useFocusEffect`) to replay from zero; live increments tick smoothly.
- `components/ProgressBar.tsx` — slim track with a magenta→violet gradient fill that springs to a 0–1 `progress`; `delay` staggers rows.
- `components/Confetti.tsx` — one-shot burst, plays on mount; drop inside any absolute container. Fired by `BadgeToast` only for prestige badges in `MILESTONE_BADGE_IDS` (`lib/stats.ts`).
- The sliding chip in the tab bar (`app/(tabs)/_layout.tsx`) and `SegmentedToggle` share the same pattern: measure each item's `onLayout`, spring a single absolute chip's `left`/`width`.
- **Hydration fade-in**: data screens (`stats`, `history`) return a blank `<View className="flex-1" />` while `!hydrated` (from `useVisits`), then render their root with reanimated's `entering={FadeIn}` so user data doesn't flash empty before Supabase responds.
- **Swipeable tabs**: `app/(tabs)/_layout.tsx` uses `@react-navigation/material-top-tabs` (via expo-router's `withLayoutContext`) pinned to the bottom, so pages follow the finger interactively (react-native-pager-view, Expo Go-safe). A custom `tabBar` renders the floating glass pill with the sliding chip (springs to the active tab via `onLayout` measurements). The Explore map needs horizontal panning, which fights the pager, so Explore toggles the pager's `swipeEnabled` through `components/TabSwipeContext.tsx`: a `useFocusEffect` sets it `false` in map mode / `true` in list mode and restores `true` on blur (so Stats↔History stay swipeable regardless of Explore's mode).

### Key config files
- `babel.config.js` — sets `jsxImportSource: "nativewind"`, includes the `nativewind/babel` preset, and lists `react-native-worklets/plugin` **last** (reanimated v4 moved its babel plugin into `react-native-worklets`)
- `metro.config.js` — wraps default Expo config with `withNativeWind`, pointing at `global.css`
- `tailwind.config.js` — includes `nativewind/preset`, sets content paths, and defines the `primary`/`ink` color palette
- `nativewind-env.d.ts` — provides TypeScript types for `className` prop
- `babel-preset-expo` is pinned as a direct devDependency so Babel can resolve it from the project root (npm nests it under `expo/` otherwise)
