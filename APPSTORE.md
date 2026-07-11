# NYC Gay Bars — App Store Connect Assets

Everything to paste into App Store Connect. Character counts shown against Apple's limits.

> Source of truth: `docs/appstore/index.html` (interactive click-to-copy version).

## App Information

| Field | Value | Limit |
|---|---|---|
| App Name | NYC Gay Bars | 30 max (12) |
| Subtitle | Track NYC's queer nightlife | 30 max (27) |
| Bundle ID | `com.normanhoang.nycgaybars` | — |
| SKU | `nycgaybars-001` | — |
| Primary Category | Lifestyle | — |
| Secondary Category | Travel (optional) | — |
| Primary Language | English (U.S.) | — |

## Version — 1.1.0

| Field | Value |
|---|---|
| Version String | `1.1.0` · Build `6` |
| Copyright | 2026 Norman Hoang |

**Promotional Text** (170 max, 152):

> Your pocket map to every gay bar in NYC. Check in, log the night, earn badges, and watch your nightlife stats come alive — 100% private, all on your device.

> Note: the 1.0.0 train is closed for new submissions. Create a new **1.1.0** version in App Store Connect before uploading build 6.

## Description (4000 max)

```
NYC Gay Bars is your personal guide to the city's LGBTQ+ nightlife — and a fun way to remember every night out.

Browse 80+ gay bars across Manhattan, Brooklyn, and Queens on an interactive map or a searchable list. Filter by neighborhood, sort by distance, and find your next spot in seconds.

Been somewhere? Check in and log what you drank — tonight or backdated. Your history builds a personal timeline of every bar, every drink, every night.

FEATURES
• Map + list of 80+ NYC gay bars, by neighborhood
• Sort by distance to what's closest right now
• One-tap check-ins and drink logging (today or any past day)
• A calendar history of your nights out
• Personal stats: favorite bar, top drink, biggest night, longest streak
• Neighborhood progress bars — how much of the city have you hit?
• 30 unlockable badges to chase
• Optional Friends: share a check-in and ping exactly the friends you choose — with per-friend controls for who gets your check-ins and who can notify you
• Beautiful, fast, native design

PRIVATE BY DESIGN
Your drink log stays on your iPhone — no account, no sign-up, no tracking, no third-party servers. Friends is optional, runs on your iCloud, uses invite codes instead of a directory, and only shares a check-in when you tap the button.

Whether you're a local completist or visiting for Pride, NYC Gay Bars makes exploring the scene a game worth playing.
```

## Keywords (100 max, comma-separated, no spaces after commas)

```
gay bar,lgbtq,queer,nyc nightlife,gay nyc,bar crawl,drink log,pride,gay map,bar tracker,manhattan
```

(97 chars)

## URLs

| Field | Notes |
|---|---|
| Privacy Policy URL **(required)** | You have `docs/privacy.html` — host it and paste the public URL. e.g. GitHub Pages: `https://normanhoang.github.io/<repo>/privacy.html` |
| Support URL **(required)** | A page or email people can reach you at. A simple GitHub repo README or a mailto page works (`docs/support.html`). |
| Marketing URL | Optional — skip. |

## Screenshots — 6.5" iPhone (1284 × 2778 ✓)

These are the 6.5" display size (1284 × 2778). Apple auto-scales them for smaller devices, so this one size covers all iPhones. Upload 3–10; order matters (first is the hero).

| # | File | Screen |
|---|---|---|
| 1 · hero | `docs/appstore/screenshots/page-0.png` | Map |
| 2 | `docs/appstore/screenshots/page-1.png` | Stats |
| 3 | `docs/appstore/screenshots/page-2.png` | History |
| 4 | `docs/appstore/screenshots/page-3.png` | Friends |

Seed data is demo-only; not shipped.

## App Icon

**1024 × 1024** (1024² · no alpha ✓) — `NYCGayBars/Assets.xcassets/AppIcon.appiconset/icon.png`. Uploaded automatically inside the build; also usable as the App Store icon.

## Age Rating (likely 17+)

In the rating questionnaire, answer honestly — the alcohol content drives the rating:

- **Alcohol, Tobacco, or Drug Use or References** → **Frequent/Intense** (the app is about bars & drink logging)
- Everything else (violence, sexual content, gambling, etc.) → **None**

Result is typically 17+. Friends content (display names + check-ins) is shared only between mutually accepted friends — no public UGC or unrestricted web access flags.

## App Privacy (updated for Friends)

The optional Friends feature stores data in CloudKit, so "Data Not Collected" no longer applies. In the privacy questionnaire declare, all **linked to the user**, **not used for tracking**, purpose **App Functionality**:

- **Name** — the display name chosen for Friends
- **User ID** — the CloudKit user identifier / invite code
- **Other User Content** — shared check-ins (display name + bar + time, sent only to selected friends; auto-deleted within ~24h)
- Location is still used only on-device to show distance/sort bars — never transmitted, so **not "collected"**; do not list it.
- Tracking: **No**.

This matches the shipped `PrivacyInfo.xcprivacy` (UserDefaults reason CA92.1; Name / User ID / Other User Content collected, linked, no tracking).

## Export Compliance (handled)

`ITSAppUsesNonExemptEncryption = false` is set in Info.plist, so App Store Connect won't prompt on upload. Answer "No" if asked about non-exempt encryption.

## Submission Checklist

- ☐ Archive in Xcode → Distribute App → App Store Connect (uploads build 6)
- ☐ Create the **1.1.0** version record (the 1.0.0 train is closed)
- ☐ Paste name, subtitle, promo text, description, keywords (above)
- ☐ Upload the 4 screenshots
- ☐ Host privacy policy + support page, paste URLs
- ☐ Complete age rating (17+) and App Privacy (Name / User ID / Other User Content)
- ☐ Attach build 6, set price (Free), submit for review
