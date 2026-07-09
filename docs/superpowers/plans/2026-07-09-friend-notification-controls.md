# Per-Friend Notification Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-friend toggles for who receives your check-ins (audience) and whose check-ins ping you (mute), plus doc-site/CLAUDE.md updates.

**Architecture:** `CheckIn` becomes per-recipient (one record per send-enabled friend, `recipientID` field). Push subscriptions gain `recipientID == me` and exist only for un-muted friends. Prefs are two sparse sets in UserDefaults, pure logic in `Logic/Social.swift`.

**Tech Stack:** Swift/SwiftUI, CloudKit, XCTest, xcodegen.

## Global Constraints

- Branch: `friends-checkins` (PR #1). Commit per task.
- Run `xcodegen generate` after adding files; build/test with `xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`.
- No schema migration needed (CloudKit schema never deployed).
- UI: `.contentPanel()` for static cards, 44pt targets, `Haptics.light()` on toggles, `.scaled` fonts.

---

### Task 1: SocialPrefs pure logic (TDD)

**Files:**
- Modify: `NYCGayBars/Logic/Social.swift` (append struct)
- Test: `NYCGayBarsTests/SocialTests.swift` (append cases)

**Interfaces — Produces:**
`SocialPrefs: Codable, Equatable` with `sendOff/getOff: Set<String>`, `sendsTo(_:)/getsFrom(_:) -> Bool`, `recipients(of:) -> [String]`, `subscribed(of:) -> [String]`, `mutating toggleSend(_:)/toggleGet(_:)/prune(keeping:)`.

- [ ] **Step 1: failing tests** — append to `SocialTests`:

```swift
// MARK: Per-friend notification prefs

func testPrefsDefaultOn() {
    let p = SocialPrefs()
    XCTAssertTrue(p.sendsTo("a"))
    XCTAssertTrue(p.getsFrom("a"))
    XCTAssertEqual(p.recipients(of: ["a", "b"]), ["a", "b"])
    XCTAssertEqual(p.subscribed(of: ["a", "b"]), ["a", "b"])
}

func testPrefsToggle() {
    var p = SocialPrefs()
    p.toggleSend("a"); p.toggleGet("b")
    XCTAssertFalse(p.sendsTo("a"))
    XCTAssertTrue(p.getsFrom("a"))
    XCTAssertFalse(p.getsFrom("b"))
    XCTAssertEqual(p.recipients(of: ["a", "b"]), ["b"])
    XCTAssertEqual(p.subscribed(of: ["a", "b"]), ["a"])
    p.toggleSend("a")
    XCTAssertTrue(p.sendsTo("a"))
}

func testPrefsPrune() {
    var p = SocialPrefs()
    p.toggleSend("gone"); p.toggleGet("gone"); p.toggleGet("kept")
    p.prune(keeping: ["kept"])
    XCTAssertTrue(p.sendOff.isEmpty)
    XCTAssertEqual(p.getOff, ["kept"])
}

func testPrefsCodableRoundTrip() throws {
    var p = SocialPrefs()
    p.toggleSend("a"); p.toggleGet("b")
    let back = try JSONDecoder().decode(SocialPrefs.self, from: JSONEncoder().encode(p))
    XCTAssertEqual(back, p)
}
```

- [ ] **Step 2: run, verify FAIL** (`-only-testing:NYCGayBarsTests/SocialTests`; expect "cannot find 'SocialPrefs'").
- [ ] **Step 3: implement** — append to `Logic/Social.swift`:

```swift
/// Per-friend notification preferences, device-local. Sparse "off" sets keyed
/// by friend ID so new friends default to both toggles on.
struct SocialPrefs: Codable, Equatable {
    /// Friends who should NOT receive my check-ins (no record addressed to them).
    var sendOff: Set<String> = []
    /// Friends whose check-ins should NOT ping me (no subscription; Tonight feed unaffected).
    var getOff: Set<String> = []

    func sendsTo(_ id: String) -> Bool { !sendOff.contains(id) }
    func getsFrom(_ id: String) -> Bool { !getOff.contains(id) }

    /// Friends who receive a shared check-in, preserving input order.
    func recipients(of friendIDs: [String]) -> [String] { friendIDs.filter(sendsTo) }
    /// Friends whose check-ins should have an alert subscription.
    func subscribed(of friendIDs: [String]) -> [String] { friendIDs.filter(getsFrom) }

    mutating func toggleSend(_ id: String) { sendOff.formSymmetricDifference([id]) }
    mutating func toggleGet(_ id: String) { getOff.formSymmetricDifference([id]) }

    /// Drop entries for IDs no longer in the friends list.
    mutating func prune(keeping ids: [String]) {
        sendOff.formIntersection(ids)
        getOff.formIntersection(ids)
    }
}
```

- [ ] **Step 4: run, verify PASS** (13 SocialTests green).
- [ ] **Step 5: commit** `feat: SocialPrefs per-friend toggle logic`.

### Task 2: CloudKit per-recipient check-ins + scoped subscriptions

**Files:**
- Modify: `NYCGayBars/Services/CloudKitSocial.swift`

**Interfaces — Produces (breaking changes consumed by Task 3):**
- `createCheckIn(author:bar:recipients:now:)` — batch-saves one record per recipient; no-op on empty.
- `tonightCheckIns(userID:now:)` — replaces `tonightCheckIns(friendIDs:)`; predicate `recipientID == me AND ts > cutoff`.
- `syncSubscriptions(userID:subscribedFriendIDs:)` — renamed param; check-in sub predicate `authorID == friend AND recipientID == me`.

- [ ] **Step 1: edit the three functions** (plus header doc comment noting `recipientID` + new index). Check-in creation:

```swift
/// Broadcast presence: one small record per recipient so unchecked/removed
/// friends never have a record addressed to them (their subscriptions can't fire).
func createCheckIn(author: FriendProfile, bar: Bar, recipients: [String], now: Date = Date()) async throws {
    guard !recipients.isEmpty else { return }
    let records = recipients.map { recipient in
        let rec = CKRecord(recordType: RT.checkIn)
        rec["authorID"] = author.id
        rec["authorName"] = author.displayName
        rec["recipientID"] = recipient
        rec["barId"] = bar.id
        rec["barName"] = bar.name
        rec["ts"] = now
        return rec
    }
    _ = try await db.modifyRecords(saving: records, deleting: [])
}
```

Tonight query:

```swift
/// Check-ins addressed to me inside the Tonight window, newest first.
func tonightCheckIns(userID: String, now: Date = Date()) async throws -> [FriendCheckIn] {
    let cutoff = now.addingTimeInterval(-Social.tonightWindow)
    let q = CKQuery(recordType: RT.checkIn,
                    predicate: NSPredicate(format: "recipientID == %@ AND ts > %@", userID, cutoff as NSDate))
    q.sortDescriptors = [NSSortDescriptor(key: "ts", ascending: false)]
    return try await records(q).compactMap(Self.checkIn(from:))
}
```

Subscription predicate + rename (`friendIDs:` → `subscribedFriendIDs:` in `syncSubscriptions`; pass `userID` through to `checkInSubscription(friendID:userID:)`):

```swift
predicate: NSPredicate(format: "authorID == %@ AND recipientID == %@", friendID, userID)
```

Also update the header comment's index list: `CheckIn.authorID/recipientID/ts (ts sortable)`.

- [ ] **Step 2: build** — expect errors only in `SocialStore` call sites (fixed in Task 3). If building now, fold Tasks 2+3 into one commit.
- [ ] **Step 3: commit with Task 3** (compiles only together).

### Task 3: SocialStore prefs + fan-out

**Files:**
- Modify: `NYCGayBars/Stores/SocialStore.swift`

**Interfaces — Produces (for Task 4 UI):**
- `prefs: SocialPrefs` (published, read-only), `toggleSend(_ friend: FriendProfile)`, `toggleGet(_ friend: FriendProfile) async`, existing `shareCheckIn(bar:) async -> Bool` now audience-aware.

- [ ] **Step 1: add state + persistence**

```swift
private static let prefsKey = "@gaybars/socialPrefs"
@Published private(set) var prefs = SocialPrefs()
// init: load like profile/friends
if let data = defaults.data(forKey: Self.prefsKey),
   let cached = try? JSONDecoder().decode(SocialPrefs.self, from: data) {
    prefs = cached
}
private func persistPrefs() {
    if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: Self.prefsKey) }
}
```

- [ ] **Step 2: toggles**

```swift
/// "Send to" toggle: unchecked friends get no record addressed to them.
func toggleSend(_ friend: FriendProfile) {
    prefs.toggleSend(friend.id)
    persistPrefs()
}

/// "Get from" toggle: mutes their pushes by dropping the subscription.
/// Tonight feed is unaffected.
func toggleGet(_ friend: FriendProfile) async {
    prefs.toggleGet(friend.id)
    persistPrefs()
    guard let me = userID else { return }
    try? await ck.syncSubscriptions(userID: me,
                                    subscribedFriendIDs: prefs.subscribed(of: friends.map(\.id)))
}
```

- [ ] **Step 3: update call sites**
  - `refresh()`: after friends fetched — `prefs.prune(keeping: ids); persistPrefs()`; then `syncSubscriptions(userID: me, subscribedFriendIDs: prefs.subscribed(of: ids))`; `tonight = try await ck.tonightCheckIns(userID: me)`.
  - `refreshTonight()`: needs `userID` instead of friend list — `guard let me = userID, onboarded`; `tonight = try await ck.tonightCheckIns(userID: me)`.
  - `shareCheckIn(bar:)`:

```swift
let recipients = prefs.recipients(of: friends.map(\.id))
guard !recipients.isEmpty else {
    errorMessage = friends.isEmpty
        ? "Add friends first to share check-ins."
        : "Sharing is switched off for all your friends."
    return false
}
try await ck.createCheckIn(author: me, bar: bar, recipients: recipients)
```

  - `removeFriend`: after removal — `prefs.prune(keeping: friends.map(\.id)); persistPrefs()`; sync call uses `subscribedFriendIDs: prefs.subscribed(of: friends.map(\.id))`.

- [ ] **Step 4: build + full tests green.**
- [ ] **Step 5: commit** `feat: per-recipient check-in fan-out + notification prefs` (Tasks 2+3).

### Task 4: Friend-row toggles UI

**Files:**
- Modify: `NYCGayBars/Screens/FriendsView.swift` (friends list rows + legend)

- [ ] **Step 1: toggle control + row** — in `FriendsView`:

```swift
private func prefToggle(on: Bool, onIcon: String, offIcon: String,
                        label: String, action: @escaping () -> Void) -> some View {
    Button {
        Haptics.light()
        action()
    } label: {
        Image(systemName: on ? onIcon : offIcon)
            .font(.scaled(14, weight: .semibold))
            .foregroundStyle(on ? Palette.primary : Palette.gray500)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
}
```

Friend row (replacing the name/remove HStack contents): name, `Spacer()`, then:

```swift
prefToggle(on: social.prefs.sendsTo(friend.id), onIcon: "paperplane.fill", offIcon: "paperplane",
           label: "Send your check-ins to \(friend.displayName): \(social.prefs.sendsTo(friend.id) ? "on" : "off")") {
    social.toggleSend(friend)
}
prefToggle(on: social.prefs.getsFrom(friend.id), onIcon: "bell.fill", offIcon: "bell.slash",
           label: "Get notified about \(friend.displayName): \(social.prefs.getsFrom(friend.id) ? "on" : "off")") {
    Task { await social.toggleGet(friend) }
}
```

(remove button stays last). Legend caption directly under the friends list, inside `friendsSection`'s non-empty branch:

```swift
Text("Paper plane: they get your check-ins. Bell: their check-ins notify you.")
    .font(.scaled(12)).foregroundStyle(Palette.gray500)
    .padding(.top, 8)
```

- [ ] **Step 2: build + tests green; commit** `feat: per-friend send/get toggles in Friends tab`.

### Task 5: Docs — privacy.html, support.html, appstore/index.html, CLAUDE.md

**Files:** `docs/privacy.html`, `docs/support.html`, `docs/appstore/index.html`, `CLAUDE.md`

- [ ] **Step 1: privacy.html** — bump date to July 9 2026; soften the two absolute claims; add Friends section after Location:
  - Intro ¶ → "…your data stays on your device. We do not operate a server, and unless you use the optional Friends feature the app makes no network requests at runtime."
  - "Data we collect" → "**None, unless you turn on Friends.** … If you use the optional Friends feature, the data described below is stored in Apple iCloud (CloudKit); we still operate no server of our own and use no analytics."
  - New `<h2>Friends (optional)</h2>`: display name + invite code + friend connections stored in iCloud; check-ins you explicitly share (display name, bar, time) are addressed only to the friends you've selected; per-friend controls (send/get toggles); pushes delivered by Apple; shared check-ins auto-deleted within ~24h; friends feature never touches drink history/location; requires iCloud; delete-the-app note.
- [ ] **Step 2: support.html** — update "Does the app need internet?" (only for optional Friends), add FAQ: how friend codes work; "Can I choose which friends get notified?" (both toggles explained); "How long do shared check-ins last?" (visible ~6h, deleted within 24h).
- [ ] **Step 3: appstore/index.html** — App Privacy card: replace "Data Not Collected" badge/instructions with Name + User ID + Other User Content (linked to user, no tracking, App Functionality), matching `PrivacyInfo.xcprivacy`; keep location non-collection note. Description: add friends bullet ("• Optional Friends: share a check-in and ping the friends you choose") and adjust PRIVATE BY DESIGN ¶ ("Friends is optional and runs on your iCloud — no accounts, no tracking, no third-party servers."). Age-rating hint: drop "No login/UGC" wording (friends-only sharing, no public content).
- [ ] **Step 4: CLAUDE.md** — add a "### Social layer (`Stores/SocialStore`, `Services/CloudKitSocial`)" subsection under Architecture: CloudKit public DB record types; one-Friendship-record-per-direction handshake; **per-recipient CheckIn fan-out** (audience control + revocation); subscription model (per-friend `authorID==F AND recipientID==me`, mute = no sub); `@gaybars/socialPrefs` sparse off-sets; UserDefaults cache keys; dashboard index list + deploy-to-production requirement; two-iCloud-account testing note; `docs/` pages must track privacy-relevant changes.
- [ ] **Step 5: commit** `docs: friends notification controls + CloudKit privacy updates`.

### Task 6: Verify + push

- [ ] **Step 1:** `xcodegen generate` (no new files, safety) + full `xcodebuild … test` — expect 45 tests, 0 failures.
- [ ] **Step 2:** simulator smoke (app launches, Friends tab gates on iCloud as before).
- [ ] **Step 3:** push branch (updates PR #1); comment on PR about schema addition (`CheckIn.recipientID` queryable index).
