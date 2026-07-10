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

- **Finding #1 (written, GATED — do not enable without the test below).** CloudKit `CheckIn.authorID` and `FriendRequest.fromID` are self-declared record fields, not verified against the record's system creator. On the public DB any authenticated iCloud user can create these records, so an attacker who knows a victim's user-record ID + a friend's ID can forge a "friend is at bar" check-in push, or an impersonated request banner. Fix lives in `CloudKitSocial.creatorMatches(_:claimedID:)`, called from `checkIn(from:)` / `request(from:)`, gated by `Social.verifyRecordCreator` (currently **`false`** = no-op).
  - **Why gated:** the guard assumes `authorID`/`fromID` equals `CKRecord.creatorUserRecordID.recordName` for records created by *another* account. If that assumption is wrong in practice, every legit friend check-in/request is silently dropped — a broken core feature, not a caught attack. Must be proven on-device with two accounts before trusting it.
  - **How to test (needs two devices, two different iCloud accounts, Production or dev CK env with schema):**
    1. Set `Social.verifyRecordCreator = true`, build+install on both devices.
    2. Devices A and B add each other as friends (full handshake).
    3. On A, share a check-in at a bar to B. **Expect:** B receives the push and sees A in B's Tonight feed. If B sees nothing, the creator-ID assumption is wrong — revert the flag and re-investigate (likely `creatorUserRecordID` returns something other than the plain user-record name; log `rec.creatorUserRecordID?.recordName` vs the stored `authorID` on B and compare).
    4. Send a friend request A→B. **Expect:** B sees the request with A's name.
    5. **Spoof check (optional, via CloudKit Dashboard dev env):** hand-create a `CheckIn` with `authorID` = A's ID but created by a third account, `recipientID` = B. **Expect with flag on:** it does NOT appear in B's feed (creator ≠ authorID). With flag off it would.
  - Only flip `verifyRecordCreator` to `true` permanently once steps 3–4 pass. Keep it out of any pushed commit until then.

- **Finding #4 (deferred to release):** `project.yml` entitlement declares `aps-environment: development`. TestFlight/App Store builds need `production`, paired with deploying the CloudKit schema to the Production environment (see the pre-TestFlight bullet above). Do NOT flip to `production` for day-to-day dev-device runs — a dev build carrying a production APS entitlement may not route development APNs pushes, breaking local push testing. Flip at archive time (or make it configuration-conditional), then `xcodegen generate`.
