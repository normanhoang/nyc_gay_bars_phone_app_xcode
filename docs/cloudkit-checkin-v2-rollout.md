# CloudKit CheckInV2 rollout runbook

This is an **operator runbook**, not a script. Every step under a "CloudKit
Console" heading is a manual action taken by a human with dashboard access to
the `iCloud.com.normanhoang.nycgaybars` container — nothing in the app or its
build process performs these steps automatically, and none of them should be
checked off until actually done in the Console for the environment named.
Treat each one as a release gate: shipping a build against a schema that
hasn't had these steps applied breaks Friends (wrong/missing schema) or leaves
plaintext check-ins reachable (skipped legacy revocation).

Background: as of this change, Friends check-ins are recipient-encrypted —
the author display name, bar id, and bar name are sealed with authenticated
HPKE (`HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly`, CryptoKit) on the
sender's device before anything is written to CloudKit. The record type is
`CheckInV2`; the legacy plaintext `CheckIn` type is no longer written or read
by the app at all. This runbook is what actually retires `CheckIn` in
production and stands up `CheckInV2`.

## 1. Schema: `CheckInV2` record type

Verify (or create, in Development first) exactly this shape in CloudKit
Console → Schema → Record Types:

```text
RECORD TYPE CheckInV2 (
    authorID STRING QUERYABLE,
    recipientID STRING QUERYABLE,
    sentAt TIMESTAMP QUERYABLE SORTABLE,
    protocolVersion INT64,
    senderKeyID STRING,
    senderPublicKey BYTES,
    recipientKeyID STRING,
    encapsulatedKey BYTES,
    ciphertext BYTES,
    GRANT WRITE TO "_creator",
    GRANT CREATE, READ TO "_icloud"
);
```

Notes on why the shape looks like this:
- The nine fields are exactly the app's transport fields (`Services/CloudKitSocial.swift`,
  `record(from:)`/`envelope(from:)`) — every one of them is plaintext routing
  metadata or an opaque HPKE byte blob. There is no field anywhere in this
  record type for a display name or bar name; the encrypted `ciphertext` field
  is the only place that content exists.
- `GRANT CREATE, READ TO "_icloud"` (not `"World"`) means only a signed-in
  iCloud user can create or read `CheckInV2` records at all — CloudKit itself
  rejects unauthenticated requests before the app's own `recipientID`/`authorID`
  filtering ever runs. It does **not** scope reads to the record's own
  recipient: any authenticated user of this container can query and see the
  routing metadata and ciphertext of any `CheckInV2` record (see §7). Privacy
  here comes from the ciphertext being unreadable without the recipient's
  private key, not from CloudKit's own access control.
- The record type auto-creates the first time the app writes to it in the
  Development environment. Development schema is **not** what ships — see §4
  for pushing this to Production.
- Required queryable indexes: `authorID`, `recipientID`, and `sentAt` (with
  `sentAt` also sortable). These back the Tonight feed query, the per-friend
  push subscriptions, and both removal paths (by record id and by
  timestamp-window fallback). Missing any of them breaks Friends silently in
  a build that talks to that environment.

## 2. Schema: `Profile` optional fields

`Profile` already exists; verify it carries these three optional fields
(auto-created the first time a device publishes a check-in key — see
`CloudKitSocial.createProfile`/`updateProfileKey`):

- `checkInCryptoVersion` (INT64) — currently always `2`.
- `checkInKeyID` (STRING) — `"v2." + <base64url digest of the public key>`.
- `checkInPublicKey` (BYTES) — the raw Curve25519 public key.

No special grants beyond `Profile`'s existing ones are needed for these three
— they ride along with the rest of the profile record.

## 3. Development-environment two-device test

The simulator has no iCloud account, so this cannot be exercised solo. Before
touching Production, verify against the **Development** environment with two
physical devices signed into two different iCloud accounts (per the
CLAUDE.md note on CloudKit dashboard testing):

1. Device A and Device B become friends (invite code or QR).
2. Device A shares a check-in. Confirm it appears in Device B's Tonight feed
   with the correct display name and bar — i.e., that Device B could decrypt
   it — and that it also appears in Device A's own Tonight feed (the
   self-addressed copy).
3. In CloudKit Console (Development → Data), open the raw `CheckInV2` records
   this produced and confirm there are exactly as many records as recipients
   (friend + self), each with only the nine transport fields — no display
   name or bar name visible anywhere in the record.
4. On Device A, remove the check-in from Tonight and confirm every copy
   (Device A's own row and Device B's feed row) disappears.
5. Un-share: turn off Device A's send toggle for Device B, share again from
   Device A, and confirm Device B's Friends tab shows nothing.

Only proceed to Production once all five behave as described.

## 4. CloudKit Console: deploy schema to Production

CloudKit Console → this container → **Deploy Schema Changes** → push
Development's `CheckInV2` record type (and the `Profile` field additions from
§2) to Production. Confirm the deployed Production schema matches §1
verbatim, including the queryable/sortable flags — the deploy tool carries
grants and field types over, but re-check them post-deploy since production
schema changes are not reversible without a new deploy.

This must happen before any TestFlight or App Store build that talks to
Production is distributed. A production build against an undeployed
`CheckInV2` schema fails every check-in write/read silently client-side (per
the existing CLAUDE.md note on CloudKit dashboard testing).

## 5. CloudKit Console: revoke legacy `CheckIn` grants

The app no longer writes or reads the legacy `CheckIn` record type — the only
remaining touchpoint is `CloudKitSocial.deleteLegacyCheckIns`, a best-effort,
client-triggered sweep of a device's *own* leftover legacy records on
`start()` (already wrapped in `try?`, so it degrades silently once this step
lands). In **Production**, edit the legacy `CheckIn` record type's security
roles:

- Remove `GRANT CREATE, READ TO "_icloud"` entirely — no signed-in user
  should be able to create a new legacy check-in or read someone else's.
- Keep (or add, if not already present) `GRANT READ, WRITE TO "_creator"` —
  a device still needs to query and delete its *own* legacy records for the
  sweep above to keep working; removing this entirely would turn the sweep
  into silent no-ops forever, leaving old plaintext records live.

After this change, verify (§7–§9 below) before considering the cutover done.

## 6. Administrative purge of remaining legacy records

`deleteLegacyCheckIns` only runs for a device that still launches the app, so
any legacy `CheckIn` record whose author has stopped using the app (deleted
it, switched devices without ever relaunching post-cutover, etc.) will never
be swept client-side. After §5's grant revocation, do a one-time
administrative purge of whatever legacy `CheckIn` records remain: CloudKit
Console → Data → query the `CheckIn` record type with no predicate (an admin
console session is not bound by the record-level grants above) and bulk
delete everything returned. This is a manual, one-time action — there is no
code path that performs it, and it does not need to be repeated once the
type is empty (new legacy records can no longer be created per §5).

## 7. Verify: anonymous-read rejection

Confirm `GRANT CREATE, READ TO "_icloud"` actually means what it says on
`CheckInV2` — an unauthenticated request (no signed-in iCloud user) must be
rejected, not merely filtered. Using a CloudKit Web Services request (or any
client) with no user token, attempt to query `CheckInV2`; it must fail with a
permission/authentication error, not return an empty or partial result set
(an empty result on an unauthenticated query would silently mask a
misconfigured grant that actually allowed `"World"` access).

## 8. Verify: authenticated ciphertext-only inspection

From a second, authenticated iCloud test account with no friendship to the
account that shared it, fetch a live `CheckInV2` record directly (Console or
a CloudKit Web Services request) and confirm the only readable content is the
nine transport fields — `authorID`, `recipientID`, `sentAt`,
`protocolVersion`, `senderKeyID`, `senderPublicKey`, `recipientKeyID`,
`encapsulatedKey`, `ciphertext` — with `ciphertext` opaque bytes and no
decoded display name or bar name anywhere in the response. This confirms the
encryption boundary holds against any authenticated user of the container,
not only against users outside it.

## 9. Verify: old-client write rejection

After §5, confirm that a request attempting to `CREATE` a record of the
legacy `CheckIn` type is rejected (permission error), simulating what would
happen if an old, pre-cutover build somehow still tried to write one. This is
the check that the revoked `"_icloud"` create grant from §5 is actually in
effect in Production, not just staged.

## 10. Export compliance (tie-in, not performed here)

This runbook does not cover App Store Connect's export-compliance
questionnaire — see `docs/appstore/index.html`'s Export Compliance section
for that gate. In short: CryptoKit HPKE is a new encryption algorithm/library
introduced by this change, so the questionnaire must be answered again from
scratch on the next upload; `ITSAppUsesNonExemptEncryption` in
`NYCGayBars/Info.plist` stays exactly as-is until the account holder has gone
through that questionnaire and recorded Apple's determination. Nothing in
this repository infers or asserts that determination.

## Release gate checklist

- **Status (2026-08-15):** §§1–9 completed. The signed `NYCGayBars` app (`com.normanhoang.nycgaybars`, version 1.2.0, build 19) was installed and verified on Norman’s iPhone and iPhoneA.

- [x] §1 — `CheckInV2` schema verified in Development, matches the block above verbatim
- [x] §2 — `Profile`'s three check-in key fields present
- [x] §3 — two-device Development test passed (all five behaviors)
- [x] §4 — schema deployed to Production, re-verified post-deploy
- [x] §5 — legacy `CheckIn` grants revoked in Production
- [x] §6 — administrative purge of remaining legacy `CheckIn` records done
- [x] §7 — anonymous read of `CheckInV2` confirmed rejected
- [x] §8 — authenticated non-friend fetch confirmed ciphertext-only
- [x] §9 — legacy `CheckIn` create confirmed rejected
- [ ] §10 — App Store Connect encryption questionnaire rerun; `ITSAppUsesNonExemptEncryption` decision recorded by the account holder
