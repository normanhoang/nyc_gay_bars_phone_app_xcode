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
| Version String | `1.1.0` · Build `12` |
| Copyright | 2026 Norman Hoang |

**Promotional Text** (170 max, 152):

> Your pocket map to every gay bar in NYC. Check in, log the night, earn badges, and watch your nightlife stats come alive — 100% private, all on your device.

## What's New in This Version (4000 max)

1.1.0 vs 1.0.0: the Friends feature is the headline (1.0 was fully solo: map/list, check-ins, drink log, history, stats, badges).

```
Introducing Friends — the night is better together.

• Add friends with a QR code, invite code, or share link — no accounts, no directory, no phone numbers
• Share a check-in with exactly the friends you choose; it appears in their Tonight feed
• Tonight: see which bars your friends are at right now
• Per-friend controls — pick who gets your check-ins, friend by friend or in groups
• Get a notification when someone sends you a friend request; nothing is shared until you approve
• Private by design: runs on your iCloud, invite codes instead of a directory, and shared check-ins auto-delete within 24 hours

Friends is completely optional — everything else stays 100% on your device.

Also in this update: smoother friend requests and accepts, plus polish and performance fixes throughout.
```

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
• Optional Friends: share a check-in with exactly the friends you choose — they see it in their Tonight feed, with per-friend controls over who gets yours
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
| Privacy Policy URL **(required)** | `https://normanhoang.github.io/nyc_gay_bars_phone_app_xcode/privacy.html` (docs/ is served via GitHub Pages — same base the in-app add-friend link uses) |
| Support URL **(required)** | `https://normanhoang.github.io/nyc_gay_bars_phone_app_xcode/support.html` |
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

## App Review Information

**Sign-in Information: not required.** Leave "Sign-in required" unchecked — there is no app account or login. The optional Friends feature uses the reviewer's own iCloud (CloudKit); Apple never accepts iCloud credentials for review, and every other feature works signed out.

**Notes for App Review** (paste into the review notes field):

```
No sign-in or account: all core features (bar map/list, check-ins, drink log, history, stats, badges) run entirely on-device with no login.

The optional Friends tab uses the device's own iCloud account via CloudKit — no separate credentials exist. Without iCloud it simply shows a "sign in to iCloud" prompt; the rest of the app is unaffected.

Friends is invite-code based and peer-to-peer: to fully exercise it you need a second device/iCloud account (send a friend request by code or QR, the other person approves). Solo, you can still complete onboarding (pick a display name) and view your own invite code and QR.

Location permission is optional and used only on-device to sort bars by distance — nothing is transmitted. Denying it just hides distances.

Notifications are optional and only used for friend requests (delivered by CloudKit).

Alcohol content: the app is a bar directory and personal drink journal. It does not sell or promote alcohol delivery.
```

## Export Compliance (handled)

`ITSAppUsesNonExemptEncryption = false` is set in Info.plist, so App Store Connect won't prompt on upload. Answer "No" if asked about non-exempt encryption.

## Submission Checklist

- ☐ **Deploy the CloudKit schema to Production first** (dashboard → container `iCloud.com.normanhoang.nycgaybars` → Deploy Schema Changes; indexes are manual — see FINDINGS.md). A production build against an undeployed schema breaks Friends silently.
- ☐ Upload build 12 — the exported IPA is at `build/ipa/NYCGayBars.ipa` (signed, `aps-environment: production` verified; the `aps-environment` entitlement is configuration-conditional now, no manual flip). Upload via Xcode Organizer, Transporter, or `xcrun altool`.
- ☐ Create the **1.1.0** version record (the 1.0.0 train is closed)
- ☐ Paste name, subtitle, promo text, description, keywords (above)
- ☐ Upload the 4 screenshots
- ☐ Privacy policy + support URLs (above — already hosted on GitHub Pages)
- ☐ Complete age rating (17+) and App Privacy (Name / User ID / Other User Content)
- ☐ App Review Information: leave sign-in unchecked, paste the review notes (above)
- ☐ Attach build 12, set price (Free), submit for review
