# Recipient-Encrypted Check-Ins Handoff

## Resume location

- Worktree: `/Users/normanhoang/repos/nyc_gay_bars _xcode/.worktrees/recipient-encrypted-check-ins`
- Branch: `feat/recipient-encrypted-check-ins`
- Implementation HEAD at pause: `910fda384400e696ac3b5006b3c4b21ab1365f8c`
- Task 4 base: `910fda384400e696ac3b5006b3c4b21ab1365f8c`
- Worktree was clean when Task 4 was interrupted; the Task 4 agent had made no source changes.

Use the branch tip when resuming because this handoff file may be committed after
the implementation HEAD above.

## Source of truth

- Design: `docs/superpowers/specs/2026-08-01-recipient-encrypted-check-ins-design.md`
- Plan: `docs/superpowers/plans/2026-08-01-recipient-encrypted-check-ins.md`
- SDD ledger: `.superpowers/sdd/2026-08-01-recipient-encrypted-check-ins/progress.md`
- Next brief: `.superpowers/sdd/2026-08-01-recipient-encrypted-check-ins/task-4-brief.md`

Resume with `superpowers:subagent-driven-development`. Trust the ledger and Git
history, do not redispatch completed tasks, and continue at Task 4.

## Completed work

| Task | Commits | Review status |
| --- | --- | --- |
| 1. Public identity and envelope contracts | `a6e20f0` | Clean |
| 2. Authenticated HPKE codec | `7d750e3`, `3367149` | Fix round 1 clean |
| 3. Synchronizable Keychain store | `89f3b48`, `910fda3` | Fix round 1 clean |

Relevant branch history after the worktree-safety commit:

```text
910fda3 fix(security): bind stored keys to accounts
89f3b48 feat(security): sync Friends keys in Keychain
3367149 fix(security): validate HPKE metadata
7d750e3 feat(security): add authenticated HPKE codec
a6e20f0 feat(security): add encrypted check-in contracts
```

Latest verification evidence:

- Task 3 focused Keychain tests: 11 passed, 0 failed.
- Full suite after Task 3: 149 passed, 0 failed.
- Command: `xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test`
- Simulator tests require access to CoreSimulator and Xcode DerivedData outside
  the filesystem sandbox.

## Binding decisions

- Friends remains enabled.
- Check-in payloads use authenticated HPKE with
  `HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly`.
- Key IDs use `v2.<base64url-digest>`.
- `openAll` and `OpenResult` remain deferred to Task 6, preserving its planned
  RED/GREEN boundary.
- Envelope timestamps are finite, range-safe, and canonical integer seconds;
  fractional public envelope timestamps are rejected.
- Private Curve25519 keys live only in synchronizable Keychain items scoped by
  CloudKit user ID and key ID.
- Legacy plaintext check-ins have no read/display fallback. Task 4 temporarily
  keeps legacy methods only so the project builds; Task 6 removes their runtime
  path.
- `CheckInV2` must require a present, matching CloudKit creator stamp. A missing
  creator is rejected; `__defaultOwner__` remains valid for an own record.
- If any enabled recipient lacks a valid V2 public key, Task 6 writes zero
  records and shows an update-required error.

## Deferred Minor findings

- Task 2: split unsupported recipient-version errors from invalid key-ID errors
  and assert the exact error.
- Task 2: assert `barName`, `authorID`, and record-derived `id` in the HPKE
  round-trip test.
- Task 3: a successful Keychain call with an unexpected top-level result shape
  should surface an error instead of becoming an empty key set.

These are ledgered for the final whole-branch review; they do not block Task 4.

## Exact resume point

Task 4 is in progress in the plan but no implementation work exists yet. Start a
fresh Task 4 implementer from the generated `task-4-brief.md` with base set to
the current branch tip. Required boundary:

- Add failing local `CKRecord` mapping and strict V2 creator-gate tests first.
- Add Profile public-key publication and opaque `CheckInV2` create/query/delete
  operations.
- Store only the nine planned V2 fields and use `sentAt`, not legacy `ts`.
- Keep legacy call sites buildable until Task 6; do not display or fall back to
  legacy records.
- Regenerate the Xcode project, run focused tests and the full suite, commit,
  package the exact task diff, and run independent spec-and-quality review.

After Task 4, continue Tasks 5–9 without skipping their per-task review gates.
Task 9's two-account/two-device, production CloudKit, legacy-grant revocation,
purge, and App Store export-compliance steps remain manual release gates and
must not be reported complete from local tests.
