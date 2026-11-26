Findings

Updated 2026-07-09 after per-friend notification controls (PR #1, branch friends-checkins).

- ⚠️ Not exercised live: CloudKit record ops, push delivery, deep link tap, onboarding/main-content visuals, and the new per-friend toggles UI (rows only render with real friends) — all require a signed-in iCloud account (two, for the friend handshake) plus dashboard schema. Listed on the PR checklist.
- ⚠️ Before TestFlight you must do dashboard work: create container iCloud.com.normanhoang.nycgaybars, add queryable indexes (Profile.code, FriendRequest.fromID/toID, Friendship.ownerID/friendID, CheckIn.authorID + **recipientID** + ts, ts also sortable), then deploy schema to Production. First run on your device (dev environment) auto-creates the record types; indexes are manual.
- ~~Known v1 limit: removing a friend can't revoke their subscription to your check-ins~~ **Fixed** by per-recipient fan-out: check-ins are one record per selected friend (recipientID), and subscriptions are scoped `authorID == friend AND recipientID == me`, so unchecked/removed friends never have a record that can fire their subscription.
- Per-friend prefs are device-local (UserDefaults @gaybars/socialPrefs) — they don't sync between the user's own devices via iCloud. Acceptable for v1; revisit if multi-device becomes a complaint.
- Shared-simulator gotcha: the default iPhone 17 sim was in use by another session during verification (a different app kept taking foreground). Use a dedicated sim (e.g. iPhone 17 Pro) for smoke tests and shut it down after.
- Scaffold screenshot artifact from v1 (Explore pill active while on Friends) was temporary-scaffold-only; not in committed code.

## Security audit follow-ups (2026-07-10)

- **Finding #2 (applied):** display name capped at `Social.maxDisplayNameLength` (40) in `SocialStore.createProfile` — no server enforces it and the name shows in others' push alerts.

- **Finding #1 (VERIFIED + ENABLED, 2026-07-11).** CloudKit `CheckIn.authorID` and `FriendRequest.fromID` are self-declared record fields, not verified against the record's system creator. On the public DB any authenticated iCloud user can create these records, so an attacker who knows a victim's user-record ID + a friend's ID could forge a "friend is at bar" check-in push, or an impersonated request banner. Fix lives in `CloudKitSocial.creatorMatches(_:claimedID:)`, called from `checkIn(from:)` / `request(from:)`, gated by `Social.verifyRecordCreator` — now **`true`**.
  - **Verification (two devices, two iCloud accounts) passed:** A shared a check-in to B → B received the push and saw A in B's Tonight feed; A sent a request → B saw it with A's name. So `authorID`/`fromID` do equal `CKRecord.creatorUserRecordID.recordName` for another account's records — legit records are not dropped, spoofed ones (creator ≠ claimed ID) are.
  - If check-ins/requests ever silently stop appearing after a CloudKit/OS change, this guard is the first suspect — log `rec.creatorUserRecordID?.recordName` vs the stored `authorID` on the receiver and compare; flip back to `false` if they diverge.

- **Finding #4 (APPLIED, 2026-07-19 — configuration-conditional):** the entitlements file now carries `aps-environment: $(APS_ENVIRONMENT)`, resolved at codesign time from per-config settings in `project.yml` (`Debug: development`, `Release: production`). No manual flip at archive time.
  - **Verified from signed binaries** (`codesign -d --entitlements :-`): Debug device build → `development`; exported App Store IPA → `production`.
  - Gotcha observed: the **archive's** app still shows `development` — automatic signing clamps the entitlement to the development provisioning profile used at archive time. That's fine: the `-exportArchive` re-sign with the App Store profile is what determines the shipped value, and the exported IPA is `production`. Always verify the IPA, not the archive.
  - Production APNs still requires the CloudKit schema deployed to the Production environment before TestFlight (see the pre-TestFlight bullet above) — that dashboard step remains manual.

## Friends audit (2026-11-26)

- **Fixed — prefs reset on short profile fetch.** `refresh()` pruned send/get prefs against the fetched profiles; `profiles(userIDs:)` drops per-record failures, so one transient miss deleted a friend's "don't send" entry and sharing to them silently resumed. Now pruned against the friendship id set, with missing profiles backfilled from cache (`Social.backfilledProfiles`).
- **Fixed — 6h deletion promise.** The expired-check-in sweep only ran on `start()`; it now also runs from `refresh()` (throttled 10 min). Policy/support/App Store copy corrected: deletion is done by the sender's device, so it can't happen while the app is never opened. **The App Store listing text must be updated in App Store Connect separately.**
- **Fixed — Friendship records not creator-verified.** `friendIDs`/`friendedByIDs` now drop records whose creator ≠ `ownerID` (`CloudKitSocial.friendshipCreatorValid`). Previously a tampered client could insert itself into a victim's friend list (and receive their check-ins), fake an acceptance, or keep a removed friend alive. Same verification caveat as Finding #1: if friends silently vanish after a CloudKit/OS change, suspect this guard first.
- **Open — deterministic record names can be squatted.** `request-A-B` / `friendship-A-B` / `profile-<id>` names are predictable; a tampered client that pre-creates one blocks the real owner's write (permission error). Low risk (needs IDs + modified client); fixing needs non-deterministic names plus a migration.
- **Open — smaller audit items:** add-friend links auto-send/auto-accept without confirmation; `start()` never retries after an offline launch (onboarding button no-ops); unfriend revoke uses a lag-prone query delete; locked-device background refresh fails at Keychain read and leaves a generic error; failed accept doesn't restore the request row.
