# Recipient-Encrypted Friends Check-Ins — Design

2026-08-01 · branch `main` · approved by Norman

## Problem

Friends currently writes one `CheckIn` record per recipient to CloudKit's
public database. iCloud authentication and `creatorUserRecordID` validation
prevent anonymous writes and author-ID spoofing, but each record exposes the
author's display name, bar ID/name, and check-in time as plaintext to any app
user who can read the public database.

Keep Friends enabled, including requests, friendships, groups, per-friend
sharing controls, and the Tonight feed. Replace plaintext check-ins with
records that require an authenticated iCloud account to read and can be opened
only by their named recipient.

## Goals

- End-to-end encrypt each check-in payload on the sender's device for one
  recipient.
- Cryptographically authenticate the sender and record header.
- Keep the existing per-recipient fan-out and self-addressed copy.
- Preserve removal, TTL cleanup, unfriend revocation, optimistic UI, and feed
  behavior.
- Synchronize a user's encryption identity across their Apple devices through
  iCloud Keychain.
- Make the transition a hard privacy cutoff with no plaintext compatibility
  or fallback path.

## Non-goals

- Hiding the author, recipient, or transmission time from CloudKit. Those
  values remain routing metadata, and CloudKit also owns system creation and
  creator metadata.
- Encrypting profiles, friend requests, friendships, or local visit/drink
  history.
- Preventing an intended recipient from copying information after decryption.
- Adding a server, third-party service, contact discovery, or public directory.

## Security model

`CheckInV2` remains in CloudKit's public database, but its role grants require
an authenticated iCloud user for create and read. CloudKit access control is a
defense in depth measure, not recipient authorization: another authenticated
app user may be able to fetch a record but receives only ciphertext.

Recipient authorization is enforced by authenticated Hybrid Public Key
Encryption (HPKE) in CryptoKit. Use
`HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly` in authentication mode. A
recipient must possess the private key matching the record's
`recipientKeyID`. The authenticated HPKE sender public key and CloudKit's
immutable creator identity jointly bind the ciphertext to the claimed
`authorID`.

All identifiers and timestamps in the routing header are additional
authenticated data. Changing the author, recipient, protocol version, key IDs,
record ID, or timestamp makes decryption fail. A copied ciphertext cannot be
replayed under a different CloudKit record.

## Components

### `SocialKeyStore`

A small Security-framework adapter owns the account key:

- Store the raw `Curve25519.KeyAgreement.PrivateKey` representation as a
  synchronizable Keychain item.
- Scope the item by the stable CloudKit user record name and key ID so account
  switching never reuses another account's identity and an available previous
  key can survive a rotation through the six-hour record TTL.
- Set `kSecAttrSynchronizable = true` and
  `kSecAttrAccessibleWhenUnlocked`; do not use a `ThisDeviceOnly`
  accessibility class.
- Return typed states: ready, not found, temporarily unavailable, or corrupt.
- Derive `keyID` as a versioned, base64url-encoded truncated SHA-256 digest of
  the public key. The identifier locates a key; it is not secret.
- Never log private-key material or decrypted payloads.

The Keychain implementation sits behind a narrow storage interface so its
state machine can be tested with an in-memory implementation. CryptoKit,
rather than a custom primitive implementation, performs all cryptography.

### `SocialCheckInCrypto`

A pure envelope codec performs these operations:

- Canonically encode the authenticated header.
- Encode/decode the encrypted payload.
- Create one authenticated HPKE sender for one record, seal one payload, and
  return the encapsulated key plus ciphertext.
- Reconstruct an authenticated HPKE recipient and open the ciphertext using
  the same protocol constant and authenticated header.
- Reject malformed lengths, unsupported versions, inconsistent key IDs,
  invalid authentication tags, and payload/header mismatches.

No CloudKit, UI, persistence, or friend-list decisions live in this component.

### Profile keys

`Profile` gains three optional fields so previously cached profiles still
decode:

- `checkInCryptoVersion: Int64`
- `checkInKeyID: String`
- `checkInPublicKey: Data`

The fields are public key material. New clients require them before sending an
encrypted check-in but continue to support all non-check-in Friends behavior
when they are absent.

## Envelope format

Create each `CKRecord.ID` locally with a random record name before encryption.
The canonical authenticated header contains:

- protocol version
- CloudKit record name
- `authorID`
- `recipientID`
- `sentAt`, encoded at a defined integer precision
- sender key ID and raw public key
- recipient key ID

The encrypted JSON payload contains:

- author display name
- bar ID
- bar display name
- canonical check-in timestamp

`CheckInV2` stores these CloudKit fields:

| Field | Type | Visibility |
|---|---|---|
| `authorID` | String | Plaintext, queryable |
| `recipientID` | String | Plaintext, queryable |
| `sentAt` | Date | Plaintext, queryable and sortable |
| `protocolVersion` | Int64 | Plaintext |
| `senderKeyID` | String | Plaintext |
| `senderPublicKey` | Data | Plaintext |
| `recipientKeyID` | String | Plaintext |
| `encapsulatedKey` | Data | Plaintext cryptographic envelope material |
| `ciphertext` | Data | Encrypted and authenticated payload |

There are no plaintext author-name, bar-ID, or bar-name fields. The record
permissions are `CREATE, READ` for `_icloud` and `WRITE` for `_creator`.
Indexes remain limited to `authorID`, `recipientID`, and `sentAt`.

## Key lifecycle

After CloudKit account authentication:

1. Load the private key for the current CloudKit user ID.
2. If neither the profile nor Keychain has a key, generate and save a key,
   then publish its public fields on the profile.
3. If Keychain has exactly one valid account key but the profile does not,
   publish that local key. If multiple keys exist, publish the newest key whose
   creation completed locally and retain the others only through the record
   TTL.
4. If the profile advertises a key but the matching private key has not reached
   this device, retry Keychain synchronization. Do not automatically replace
   the profile key.
5. If a local key and the advertised profile key disagree, treat the profile as
   authoritative and follow the same synchronization wait. Only the explicit
   reset action may replace it.
6. While waiting, Friends and friend management remain available. Sharing and
   encrypted-feed decoding report that the security key is still syncing.

If iCloud Keychain was reset and retrying cannot recover the advertised key,
the user may explicitly reset the Friends security key. Reset generates and
publishes a replacement. Records encrypted to the lost recipient key remain
unreadable and expire normally. Existing outgoing records remain verifiable
because each record carries the authenticated sender public key it used.

Account switching clears the existing SocialStore caches as it does today but
does not delete another account's synchronizable Keychain item.

## Write flow

1. Require an available iCloud account, an onboarded profile, and a ready local
   key.
2. Compute the existing send-enabled recipient list.
3. Freshly fetch every selected recipient's profile and validate its supported
   public key.
4. If any selected friend lacks a valid supported key, create no records and
   report that the selected friends need to update. Never omit a recipient
   silently and never fall back to plaintext.
5. Add the sender as the self-copy recipient.
6. Preallocate one record ID per recipient, create and authenticate one HPKE
   envelope per record, then perform the existing non-atomic CloudKit batch
   save.
7. Retain every successfully saved record ID even after a partial CloudKit
   failure, preserving reliable retraction.
8. On full success, publish the same optimistic own row used today.

Cryptographic preparation is all-or-nothing and happens before CloudKit
writes. A CloudKit batch may still partially fail; the existing partial-fan-out
error and cleanup behavior remains.

## Read flow

Query `CheckInV2` by `recipientID == me` and the current Tonight window, sorted
by `sentAt`. For every result:

1. Require the record's `recipientID` to equal the authenticated user.
2. Require `authorID` to be either the current user or a current friend.
3. Require CloudKit's creator identity to match `authorID` (including the
   existing own-record handling).
4. Validate the protocol version, key IDs, public-key encoding, record ID, and
   timestamp bounds.
5. Select the local private key matching `recipientKeyID`.
6. Open authenticated HPKE using the sender public key and canonical header.
7. Decode the payload and require its canonical timestamp to match the header.
8. Convert it to the existing `FriendCheckIn` model and run the unchanged
   tombstone, optimistic-merge, friend-only, deduplication, and Tonight-window
   logic.

Invalid, unknown-version, misaddressed, expired, or undecryptable records are
dropped. The UI may show one aggregate, non-sensitive warning, but errors and
logs must not expose payload or key material.

## Removal, revocation, and expiry

- Keep delete-by-record-ID for fan-outs shared in the current launch.
- Keep the `authorID` plus narrow `sentAt` query fallback for an earlier-launch
  fan-out.
- Unfriending deletes the author's `CheckInV2` records addressed to that
  recipient.
- Startup TTL cleanup deletes the author's expired `CheckInV2` records.
- Tombstones and optimistic self-copy handling remain unchanged.
- New clients ignore all legacy `CheckIn` records. Before the production grants
  are revoked they may make a best-effort pass to delete records created by the
  current user, but the administrative purge is authoritative and the rollout
  does not rely on clients relaunching.

## Push behavior

Check-in pushes remain disabled. Remove the latent plaintext-dependent
subscription payload from the V2 path. If pushes are enabled in a future
release, CloudKit may send only a generic notification; the app must fetch and
decrypt before showing a name, bar, or bar deep link. Friend-request pushes are
unchanged.

## Hard-cutoff rollout

The CloudKit steps are operational release requirements, not optional follow-up
work:

1. Add and test the optional Profile key fields and new `CheckInV2` record type
   in the development schema.
2. Add the required V2 indexes and grants, then deploy the schema to
   Production before the binary.
3. Revoke legacy `CheckIn` create and read grants so old clients cannot create
   or consume new plaintext check-ins. Older binaries retain friend-management
   functionality but their check-in sharing stops.
4. Purge remaining legacy `CheckIn` records through CloudKit administration.
   Client-side TTL cleanup is insufficient because a device that never
   relaunches may leave records behind.
5. Release the V2 client. Production legacy record types remain in the schema
   because deployed CloudKit types cannot be deleted, but they have no runtime
   path or usable grants.

There is no mixed-mode period and no feature flag that restores plaintext.

## User-facing behavior

The Friends tab, requests, groups, toggles, invite codes, and Tonight layout do
not change. New messages are limited to:

- security key is still syncing
- explicit security-key reset confirmation
- selected friends need to update before this check-in can be shared
- some encrypted check-ins could not be opened

Reset confirmation states that active check-ins addressed to the old key may
become unreadable. It never implies that friend relationships or local history
will be deleted.

## Documentation and compliance

- Update `CLAUDE.md` with the V2 record, key lifecycle, envelope, hard-cutoff,
  and generic-push invariants.
- Update `docs/privacy.html`, `docs/support.html`, and
  `docs/appstore/index.html` to say that shared payloads are end-to-end
  encrypted, while routing metadata remains visible to Apple/CloudKit.
- Review `PrivacyInfo.xcprivacy`; the collected-data categories remain Name,
  User ID, and Other User Content unless implementation changes the declared
  collection behavior.
- Re-run the App Store Connect export-compliance determination for the use of
  CryptoKit HPKE. Do not change `ITSAppUsesNonExemptEncryption` based only on a
  code assumption; record the result of Apple's questionnaire before release.

## Testing

Implementation follows red-green-refactor. Unit tests cover:

- intended-recipient and self-copy round trips
- a different recipient private key
- a different authenticated sender key
- mutated ciphertext, encapsulated key, every authenticated header field, and
  CloudKit record name
- ciphertext copied to another record
- malformed key lengths, malformed payloads, and unknown protocol versions
- deterministic key-ID and canonical-header encoding
- first-use key generation and profile publication
- delayed Keychain synchronization without automatic rotation
- account isolation and explicit reset
- blocking the entire share when one enabled friend has no supported key
- partial CloudKit fan-out retention and removal
- V2 TTL cleanup, timestamp fallback removal, unfriend revocation, tombstones,
  optimistic self-copies, and Tonight filtering
- legacy records never entering the feed or write path

Verification also includes:

- the full unit-test suite and a clean app build
- a repository scan proving `CheckInV2` has no plaintext payload fields
- two devices using different iCloud accounts
- two devices using the same iCloud account and synchronized key
- delayed/disabled Keychain synchronization and explicit key reset
- production-like CloudKit grants proving anonymous reads fail, authenticated
  users receive only ciphertext, and legacy writes fail

## Success criteria

- Friends remains enabled and usable.
- Every newly shared check-in is a `CheckInV2` ciphertext addressed to exactly
  one selected recipient or the sender's self-copy.
- Only the matching recipient key opens the payload.
- Sender, header, and ciphertext tampering is rejected.
- No runtime path writes, reads, displays, pushes, or falls back to plaintext
  legacy check-ins.
- Removal and revocation delete the entire encrypted fan-out with the same
  reliability as the current implementation.
- Tests, build, documentation, schema checklist, privacy review, and export
  compliance determination are complete before release.
