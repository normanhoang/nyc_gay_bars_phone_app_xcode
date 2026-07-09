# Per-Friend Notification Controls — Design

2026-07-09 · branch `friends-checkins` · approved by Norman

## Problem

V1 friends feature is all-or-nothing: every friend gets every shared check-in,
and every friend's check-in pings you. Users need per-friend control over both
directions. Also: v1 couldn't revoke a removed friend's notifications
(public-DB subscription pointed at `authorID` alone).

## Semantics (user-approved: "audience + mute")

Per friend, two toggles, both default ON:

| Toggle | Off means |
|---|---|
| **Send to** | Friend gets nothing from you — no push, and your check-in never appears in their Tonight feed. True audience control. |
| **Get from** | Mute — no push from them, but their check-ins still appear in your Tonight feed. |

## Data model (user-approved: per-recipient records)

`CheckIn` gains `recipientID`. Sharing creates one record per send-enabled
friend (single batch save). No migration — schema was never deployed.

- Push subscription per friend: `authorID == <friend> AND recipientID == <me>`;
  muted friends have no subscription (mute = delete sub).
- Tonight feed query: `recipientID == <me> AND ts > cutoff` (replaces
  `authorID IN friends`).
- Revocation fixed: unchecked/removed friends never have a record addressed to
  them; their stale subscription can never fire (recipientID never matches).
- Dashboard indexes: `CheckIn.recipientID` queryable (in addition to
  `authorID` — still used by TTL cleanup).

## Prefs storage

Device-local UserDefaults `@gaybars/socialPrefs`, JSON:
`{ "sendOff": [friendID], "getOff": [friendID] }` — sparse sets, so new
friends default on. Pure logic (recipient computation, subscription-set
computation, toggle, pruning) in `Logic/Social.swift`, unit-tested.

## Store

- `SocialStore.prefs` published; `toggleSend(_:)`, `toggleGet(_:)`
  (get-toggle re-runs `syncSubscriptions`).
- `shareCheckIn` fans out to `friends − sendOff`; returns failure when the
  recipient set is empty (share button shows why).
- `removeFriend` prunes that ID from both sets.

## UI (FriendsView)

Friend row: name + two 44pt icon toggles — `paperplane`(.fill) send,
`bell`(.fill) get; magenta when on, `.slash` + gray when off; `Haptics.light`
on toggle; VoiceOver labels ("Send check-ins to Sam: on"). One legend caption
under the YOUR FRIENDS section.

## Docs

- `docs/privacy.html`: new "Friends (optional)" section — CloudKit storage,
  what's shared (display name, bar, per-recipient), 24h deletion, toggles,
  updated date. Soften "no network requests" claims to "unless you use
  Friends".
- `docs/support.html`: FAQ — Friends needs iCloud + internet; codes; the two
  toggles.
- `docs/appstore/index.html`: App Privacy section → Name / User ID / Other
  User Content (linked, not tracking) matching PrivacyInfo.xcprivacy; friends
  bullet in description; push-notification note.
- `CLAUDE.md`: social layer architecture notes (stores/service/record model,
  per-recipient fan-out, prefs key, docs pages).

## Testing

TDD for new Logic functions. Full suite green. Simulator smoke (iCloud gate
still fine). Live two-account flows remain on the PR checklist.
