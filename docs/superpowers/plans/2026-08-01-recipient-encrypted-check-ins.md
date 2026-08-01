# Recipient-Encrypted Friends Check-Ins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Friends enabled while replacing public plaintext check-ins with iCloud-authenticated, recipient-only authenticated HPKE envelopes.

**Architecture:** A focused CryptoKit codec seals one `CheckInV2` payload per recipient and authenticates the public routing header. A synchronizable Keychain store owns each CloudKit account's Curve25519 private key; Profiles publish only the matching public identity. `CloudKitSocial` transports opaque envelopes, while `SocialStore` coordinates key readiness, recipient preflight, decryption, and the existing fan-out lifecycle.

**Tech Stack:** Swift 5, SwiftUI, CryptoKit HPKE, Security/Keychain Services, CloudKit public database, XCTest, XcodeGen, iOS 26.

## Global Constraints

- Follow `docs/superpowers/specs/2026-08-01-recipient-encrypted-check-ins-design.md` exactly; there is no plaintext compatibility or fallback path.
- Use `HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly` in authenticated mode. Do not implement cryptographic primitives.
- Keep plaintext CloudKit fields limited to author/recipient routing, second-precision send time, protocol/key identifiers, sender public key, encapsulated key, and ciphertext.
- `CheckInV2` reads and creates require the CloudKit `_icloud` role; only `_creator` may write existing records.
- Friends, requests, friendships, groups, toggles, and local visit/drink data remain behaviorally unchanged.
- Keep the 3-hour Tonight window, 6-hour cleanup TTL, self-addressed copy, record-ID removal, timestamp fallback, tombstones, and optimistic row.
- If any enabled friend lacks a valid V2 public key, write zero records and show an update-required error. Never silently omit recipients.
- Store private keys only in synchronizable Keychain items scoped by CloudKit user ID and key ID. Never log secrets or decrypted payloads.
- Do not hand-edit `NYCGayBars.xcodeproj`; run `xcodegen generate` whenever source/test files are added.
- Run tests with `xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test`.
- Commit only files belonging to the current task; preserve unrelated worktree changes.

---

## File Structure

- Create `NYCGayBars/Logic/SocialCheckInCrypto.swift`: canonical envelope format, key IDs, authenticated HPKE seal/open, batch validation.
- Create `NYCGayBars/Services/SocialKeyStore.swift`: synchronizable Keychain persistence and pure key-resolution state machine.
- Create `NYCGayBarsTests/SocialCheckInCryptoTests.swift`: envelope security and recipient-selection tests.
- Create `NYCGayBarsTests/SocialKeyStoreTests.swift`: key lifecycle and isolated Keychain integration tests.
- Create `NYCGayBarsTests/CloudKitSocialRecordTests.swift`: Profile and `CheckInV2` field mapping tests without network access.
- Modify `NYCGayBars/Models/SocialModels.swift`: optional Profile public identity and opaque encrypted-envelope models.
- Modify `NYCGayBars/Services/CloudKitSocial.swift`: Profile key publication, V2 envelope CRUD, legacy purge, and generic subscriptions.
- Modify `NYCGayBars/Stores/SocialStore.swift`: key bootstrap/reset, encrypted share/read flows, and V2 removal.
- Modify `NYCGayBars/Screens/FriendsView.swift`: key-sync/reset/update-required messaging and encryption copy.
- Modify `NYCGayBars/NYCGayBarsApp.swift`: generic check-in push navigation to Friends instead of plaintext bar deep links.
- Modify `NYCGayBars/en.lproj/Localizable.strings`: generic future check-in notification text.
- Modify `CLAUDE.md`, `docs/privacy.html`, `docs/support.html`, and `docs/appstore/index.html`: encrypted social-layer behavior and disclosures.
- Create `docs/cloudkit-checkin-v2-rollout.md`: exact CloudKit schema/index/grant, purge, and verification runbook.
- Regenerate `NYCGayBars.xcodeproj/project.pbxproj` with XcodeGen after new Swift files are added.

---

### Task 1: Public identity and encrypted-envelope contracts

**Files:**
- Modify: `NYCGayBars/Models/SocialModels.swift:3-33`
- Create: `NYCGayBars/Logic/SocialCheckInCrypto.swift` with the key-ID helper completed by Task 2
- Modify: `NYCGayBarsTests/SocialTests.swift:1-40`
- Regenerate: `NYCGayBars.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `CheckInPublicIdentity`, `EncryptedCheckInEnvelope`, and optional Profile fields `checkInCryptoVersion`, `checkInKeyID`, `checkInPublicKey`.
- Produces: `FriendProfile.checkInIdentity` and `FriendProfile.renamed(to:)`.
- Consumed by: Tasks 2–6.

- [ ] **Step 1: Add failing compatibility and validation tests**

```swift
import CryptoKit

func testLegacyProfileDecodesWithoutCheckInKey() throws {
    let data = #"{"id":"a","displayName":"Alex","code":"ABC234"}"#.data(using: .utf8)!
    let profile = try JSONDecoder().decode(FriendProfile.self, from: data)
    XCTAssertNil(profile.checkInIdentity)
}

func testProfileBuildsValidCheckInIdentity() throws {
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    let publicKey = privateKey.publicKey.rawRepresentation
    let keyID = SocialCheckInCrypto.keyID(for: publicKey)
    let profile = FriendProfile(id: "a", displayName: "Alex", code: "ABC234",
                                checkInCryptoVersion: 2, checkInKeyID: keyID,
                                checkInPublicKey: publicKey)
    XCTAssertEqual(profile.checkInIdentity,
                   CheckInPublicIdentity(version: 2, keyID: keyID, publicKey: publicKey))
}

func testRenamePreservesCheckInIdentity() {
    let profile = FriendProfile(id: "a", displayName: "Old", code: "ABC234",
                                checkInCryptoVersion: 2, checkInKeyID: "key",
                                checkInPublicKey: Data(repeating: 1, count: 32))
    XCTAssertEqual(profile.renamed(to: "New").checkInKeyID, "key")
}

func testProfileRejectsUnsupportedOrMalformedIdentity() {
    let malformed = Data([1, 2, 3])
    let profile = FriendProfile(
        id: "a", displayName: "Alex", code: "ABC234",
        checkInCryptoVersion: 99,
        checkInKeyID: SocialCheckInCrypto.keyID(for: malformed),
        checkInPublicKey: malformed)
    XCTAssertNil(profile.checkInIdentity)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/SocialTests
```

Expected: compile failure because Profile key fields, `CheckInPublicIdentity`, and `SocialCheckInCrypto` do not exist.

- [ ] **Step 3: Add explicit backwards-compatible Profile initialization and envelope value types**

```swift
import CryptoKit
import Foundation

struct CheckInPublicIdentity: Equatable, Codable {
    let version: Int64
    let keyID: String
    let publicKey: Data
}

struct FriendProfile: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    let code: String
    let checkInCryptoVersion: Int64?
    let checkInKeyID: String?
    let checkInPublicKey: Data?

    init(id: String, displayName: String, code: String,
         checkInCryptoVersion: Int64? = nil, checkInKeyID: String? = nil,
         checkInPublicKey: Data? = nil) {
        self.id = id
        self.displayName = displayName
        self.code = code
        self.checkInCryptoVersion = checkInCryptoVersion
        self.checkInKeyID = checkInKeyID
        self.checkInPublicKey = checkInPublicKey
    }

    var checkInIdentity: CheckInPublicIdentity? {
        guard let version = checkInCryptoVersion, let keyID = checkInKeyID,
              let publicKey = checkInPublicKey,
              version == SocialCheckInCrypto.version,
              keyID == SocialCheckInCrypto.keyID(for: publicKey),
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)) != nil
        else { return nil }
        return .init(version: version, keyID: keyID, publicKey: publicKey)
    }

    func renamed(to name: String) -> FriendProfile {
        FriendProfile(id: id, displayName: name, code: code,
                      checkInCryptoVersion: checkInCryptoVersion,
                      checkInKeyID: checkInKeyID, checkInPublicKey: checkInPublicKey)
    }
}

struct EncryptedCheckInEnvelope: Identifiable, Equatable {
    var id: String { recordName }
    let recordName: String
    let authorID: String
    let recipientID: String
    let sentAt: Date
    let protocolVersion: Int64
    let senderKeyID: String
    let senderPublicKey: Data
    let recipientKeyID: String
    let encapsulatedKey: Data
    let ciphertext: Data
}
```

Create `SocialCheckInCrypto.swift` with the final key-ID algorithm; Task 2 adds
the envelope operations without changing this function:

```swift
import CryptoKit
import Foundation

enum SocialCheckInCrypto {
    static let version: Int64 = 2

    static func keyID(for publicKey: Data) -> String {
        Data(SHA256.hash(data: publicKey).prefix(16)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run `xcodegen generate`, then the Task 1 command again. Expected: all existing
`SocialTests` plus the three new cases pass.

- [ ] **Step 5: Commit**

```bash
git add NYCGayBars/Models/SocialModels.swift NYCGayBars/Logic/SocialCheckInCrypto.swift NYCGayBarsTests/SocialTests.swift NYCGayBars.xcodeproj/project.pbxproj
git commit -m "feat(security): add encrypted check-in contracts"
```

### Task 2: Authenticated HPKE codec

**Files:**
- Create/complete: `NYCGayBars/Logic/SocialCheckInCrypto.swift`
- Create: `NYCGayBarsTests/SocialCheckInCryptoTests.swift`
- Regenerate: `NYCGayBars.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `SocialCheckInCrypto.version`, `keyID(for:)`, `normalized(_:)`, `seal(...)`, `open(...)`, and `openAll(...)`.
- Consumes: `CheckInPublicIdentity`, `EncryptedCheckInEnvelope`, `FriendCheckIn` from Task 1.
- Consumed by: Tasks 4–6.

- [ ] **Step 1: Add focused failing security tests**

```swift
import CryptoKit
import XCTest
@testable import NYCGayBars

final class SocialCheckInCryptoTests: XCTestCase {
    private let sender = Curve25519.KeyAgreement.PrivateKey()
    private let recipient = Curve25519.KeyAgreement.PrivateKey()
    private let sentAt = Date(timeIntervalSince1970: 1_800_000_000.75)

    private func envelope() throws -> EncryptedCheckInEnvelope {
        let recipientIdentity = CheckInPublicIdentity(
            version: SocialCheckInCrypto.version,
            keyID: SocialCheckInCrypto.keyID(for: recipient.publicKey.rawRepresentation),
            publicKey: recipient.publicKey.rawRepresentation)
        return try SocialCheckInCrypto.seal(
            recordName: "checkin-v2-one", authorID: "author", recipientID: "recipient",
            sentAt: sentAt, senderPrivateKey: sender, recipient: recipientIdentity,
            authorName: "Alex", barID: "stonewall", barName: "Stonewall Inn")
    }

    func testIntendedRecipientRoundTripsAuthenticatedPayload() throws {
        let opened = try SocialCheckInCrypto.open(envelope(), recipientPrivateKey: recipient)
        XCTAssertEqual(opened.authorName, "Alex")
        XCTAssertEqual(opened.barId, "stonewall")
        XCTAssertEqual(opened.date, SocialCheckInCrypto.normalized(sentAt))
    }

    func testWrongRecipientCannotOpen() throws {
        XCTAssertThrowsError(try SocialCheckInCrypto.open(
            envelope(), recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey()))
    }

    func testMutatedCiphertextCannotOpen() throws {
        var envelope = try envelope()
        var ciphertext = envelope.ciphertext
        ciphertext[ciphertext.startIndex] ^= 0x01
        envelope = envelope.replacing(ciphertext: ciphertext)
        XCTAssertThrowsError(try SocialCheckInCrypto.open(envelope(), recipientPrivateKey: recipient))
    }

    func testChangedRecipientHeaderCannotOpen() throws {
        let changed = try envelope().replacing(recipientID: "someone-else")
        XCTAssertThrowsError(try SocialCheckInCrypto.open(changed, recipientPrivateKey: recipient))
    }

    func testRecordNameReplayCannotOpen() throws {
        let replay = try envelope().replacing(recordName: "checkin-v2-replay")
        XCTAssertThrowsError(try SocialCheckInCrypto.open(replay, recipientPrivateKey: recipient))
    }

    func testChangedSenderPublicKeyCannotOpen() throws {
        let other = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let changed = try envelope().replacing(
            senderKeyID: SocialCheckInCrypto.keyID(for: other), senderPublicKey: other)
        XCTAssertThrowsError(try SocialCheckInCrypto.open(changed, recipientPrivateKey: recipient))
    }

    func testUnknownVersionCannotOpen() throws {
        XCTAssertThrowsError(try SocialCheckInCrypto.open(
            envelope().replacing(protocolVersion: 99), recipientPrivateKey: recipient))
    }
}

private extension EncryptedCheckInEnvelope {
    func replacing(recordName: String? = nil, authorID: String? = nil,
                   recipientID: String? = nil, sentAt: Date? = nil,
                   protocolVersion: Int64? = nil, senderKeyID: String? = nil,
                   senderPublicKey: Data? = nil, recipientKeyID: String? = nil,
                   encapsulatedKey: Data? = nil, ciphertext: Data? = nil)
        -> EncryptedCheckInEnvelope {
        EncryptedCheckInEnvelope(
            recordName: recordName ?? self.recordName,
            authorID: authorID ?? self.authorID,
            recipientID: recipientID ?? self.recipientID,
            sentAt: sentAt ?? self.sentAt,
            protocolVersion: protocolVersion ?? self.protocolVersion,
            senderKeyID: senderKeyID ?? self.senderKeyID,
            senderPublicKey: senderPublicKey ?? self.senderPublicKey,
            recipientKeyID: recipientKeyID ?? self.recipientKeyID,
            encapsulatedKey: encapsulatedKey ?? self.encapsulatedKey,
            ciphertext: ciphertext ?? self.ciphertext)
    }
}
```

- [ ] **Step 2: Regenerate and verify RED**

```bash
xcodegen generate
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/SocialCheckInCryptoTests
```

Expected: compile failures for missing `seal`, `open`, and `normalized`.

- [ ] **Step 3: Implement canonical header and authenticated HPKE**

```swift
import CryptoKit
import Foundation

enum SocialCheckInCrypto {
    static let version: Int64 = 2
    private static let info = Data("com.normanhoang.nycgaybars.checkin.v2".utf8)
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    enum CryptoError: Error, Equatable {
        case unsupportedVersion, invalidKeyID, invalidTimestamp, payloadMismatch
    }

    private struct Header: Codable {
        let protocolVersion: Int64
        let recordName: String
        let authorID: String
        let recipientID: String
        let sentAtSeconds: Int64
        let senderKeyID: String
        let senderPublicKey: Data
        let recipientKeyID: String
    }

    private struct Payload: Codable {
        let authorName: String
        let barID: String
        let barName: String
        let sentAtSeconds: Int64
    }

    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: TimeInterval(Int64(date.timeIntervalSince1970.rounded(.down))))
    }

    static func keyID(for publicKey: Data) -> String {
        Data(SHA256.hash(data: publicKey).prefix(16)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func seal(recordName: String, authorID: String, recipientID: String,
                     sentAt: Date, senderPrivateKey: Curve25519.KeyAgreement.PrivateKey,
                     recipient: CheckInPublicIdentity, authorName: String,
                     barID: String, barName: String) throws -> EncryptedCheckInEnvelope {
        guard recipient.version == version,
              recipient.keyID == keyID(for: recipient.publicKey) else { throw CryptoError.invalidKeyID }
        let senderPublicKey = senderPrivateKey.publicKey.rawRepresentation
        let seconds = Int64(normalized(sentAt).timeIntervalSince1970)
        let header = Header(protocolVersion: version, recordName: recordName,
                            authorID: authorID, recipientID: recipientID,
                            sentAtSeconds: seconds,
                            senderKeyID: keyID(for: senderPublicKey),
                            senderPublicKey: senderPublicKey,
                            recipientKeyID: recipient.keyID)
        let aad = try canonical(header)
        let plaintext = try canonical(Payload(authorName: authorName, barID: barID,
                                              barName: barName, sentAtSeconds: seconds))
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipient.publicKey)
        var sender = try HPKE.Sender(recipientKey: recipientKey, ciphersuite: suite,
                                     info: info, authenticatedBy: senderPrivateKey)
        let ciphertext = try sender.seal(plaintext, authenticating: aad)
        return EncryptedCheckInEnvelope(
            recordName: recordName, authorID: authorID, recipientID: recipientID,
            sentAt: Date(timeIntervalSince1970: TimeInterval(seconds)),
            protocolVersion: version, senderKeyID: header.senderKeyID,
            senderPublicKey: senderPublicKey, recipientKeyID: recipient.keyID,
            encapsulatedKey: sender.encapsulatedKey, ciphertext: ciphertext)
    }

    static func open(_ envelope: EncryptedCheckInEnvelope,
                     recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey) throws -> FriendCheckIn {
        guard envelope.protocolVersion == version else { throw CryptoError.unsupportedVersion }
        guard envelope.senderKeyID == keyID(for: envelope.senderPublicKey),
              envelope.recipientKeyID == keyID(for: recipientPrivateKey.publicKey.rawRepresentation)
        else { throw CryptoError.invalidKeyID }
        let seconds = Int64(envelope.sentAt.timeIntervalSince1970)
        let header = Header(protocolVersion: envelope.protocolVersion,
                            recordName: envelope.recordName, authorID: envelope.authorID,
                            recipientID: envelope.recipientID, sentAtSeconds: seconds,
                            senderKeyID: envelope.senderKeyID,
                            senderPublicKey: envelope.senderPublicKey,
                            recipientKeyID: envelope.recipientKeyID)
        let senderKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: envelope.senderPublicKey)
        var recipient = try HPKE.Recipient(
            privateKey: recipientPrivateKey, ciphersuite: suite, info: info,
            encapsulatedKey: envelope.encapsulatedKey, authenticatedBy: senderKey)
        let payload = try JSONDecoder().decode(
            Payload.self, from: recipient.open(envelope.ciphertext, authenticating: try canonical(header)))
        guard payload.sentAtSeconds == seconds else { throw CryptoError.payloadMismatch }
        return FriendCheckIn(id: envelope.recordName, authorID: envelope.authorID,
                             authorName: payload.authorName, barId: payload.barID,
                             barName: payload.barName,
                             date: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
```

- [ ] **Step 4: Add remaining mutations, then run focused tests**

```swift
func testChangedAuthorAndTimestampCannotOpen() throws {
    let original = try envelope()
    XCTAssertThrowsError(try SocialCheckInCrypto.open(
        original.replacing(authorID: "forged"), recipientPrivateKey: recipient))
    XCTAssertThrowsError(try SocialCheckInCrypto.open(
        original.replacing(sentAt: original.sentAt.addingTimeInterval(1)),
        recipientPrivateKey: recipient))
}

func testChangedRecipientKeyAndEncapsulatedKeyCannotOpen() throws {
    let original = try envelope()
    XCTAssertThrowsError(try SocialCheckInCrypto.open(
        original.replacing(recipientKeyID: "wrong"), recipientPrivateKey: recipient))
    XCTAssertThrowsError(try SocialCheckInCrypto.open(
        original.replacing(encapsulatedKey: Data([0])), recipientPrivateKey: recipient))
}

func testMalformedSenderPublicKeyCannotOpen() throws {
    let malformed = Data([1, 2, 3])
    let changed = try envelope().replacing(
        senderKeyID: SocialCheckInCrypto.keyID(for: malformed), senderPublicKey: malformed)
    XCTAssertThrowsError(try SocialCheckInCrypto.open(changed, recipientPrivateKey: recipient))
}
```

Run the Task 2 test command. Expected: all codec tests pass with no warnings.

- [ ] **Step 5: Commit**

```bash
git add NYCGayBars/Logic/SocialCheckInCrypto.swift NYCGayBarsTests/SocialCheckInCryptoTests.swift NYCGayBars.xcodeproj/project.pbxproj
git commit -m "feat(security): add authenticated HPKE codec"
```

### Task 3: Synchronizable Keychain store and resolution state

**Files:**
- Create: `NYCGayBars/Services/SocialKeyStore.swift`
- Create: `NYCGayBarsTests/SocialKeyStoreTests.swift`
- Regenerate: `NYCGayBars.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `SocialKeyMaterial`, `SocialKeyResolution`, `SocialKeyStoring`, and `SocialKeyStore`.
- Consumed by: Task 5 and Task 6.

- [ ] **Step 1: Add failing pure-state and isolated-Keychain tests**

```swift
import CryptoKit
import XCTest
@testable import NYCGayBars

final class SocialKeyStoreTests: XCTestCase {
    func testNoProfileAndNoLocalKeyGenerates() {
        XCTAssertEqual(SocialKeyResolution.resolve(profileKeyID: nil, localKeys: []), .generate)
    }

    func testProfileKeyMissingLocallyWaitsInsteadOfRotating() {
        XCTAssertEqual(SocialKeyResolution.resolve(profileKeyID: "published", localKeys: []),
                       .waitForSync(keyID: "published"))
    }

    func testMatchingProfileAndLocalKeyIsReady() {
        let key = SocialKeyMaterial.generate(createdAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(SocialKeyResolution.resolve(profileKeyID: key.keyID, localKeys: [key]),
                       .ready(keyID: key.keyID))
    }

    func testProfileMismatchWaitsForPublishedKey() {
        let local = SocialKeyMaterial.generate(createdAt: Date())
        XCTAssertEqual(SocialKeyResolution.resolve(profileKeyID: "published", localKeys: [local]),
                       .waitForSync(keyID: "published"))
    }

    func testSynchronizableStoreRoundTripsAccountKey() throws {
        let service = "SocialKeyStoreTests.\(UUID().uuidString)"
        let store = SocialKeyStore(service: service)
        let key = SocialKeyMaterial.generate(createdAt: Date(timeIntervalSince1970: 10))
        defer { try? store.deleteAll(userID: "account") }
        try store.save(key, userID: "account")
        XCTAssertEqual(try store.keys(userID: "account"), [key])
        XCTAssertTrue(try store.keys(userID: "other").isEmpty)
    }

    func testRetiredKeyPrunesOnlyAfterRecordTTL() {
        let now = Date()
        let current = SocialKeyMaterial.generate(createdAt: now)
        let recent = SocialKeyMaterial.generate(createdAt: now).retired(at: now.addingTimeInterval(-60))
        let stale = SocialKeyMaterial.generate(createdAt: now)
            .retired(at: now.addingTimeInterval(-Social.checkInTTL - 1))
        XCTAssertEqual(SocialKeyResolution.prunableKeyIDs(
            [current, recent, stale], currentKeyID: current.keyID, now: now), [stale.keyID])
    }
}
```

- [ ] **Step 2: Regenerate and verify RED**

```bash
xcodegen generate
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/SocialKeyStoreTests
```

Expected: compile failure because the key-store types do not exist.

- [ ] **Step 3: Implement the key material and pure resolution table**

```swift
import CryptoKit
import Foundation
import Security

struct SocialKeyMaterial: Equatable, Codable {
    let keyID: String
    let privateKeyData: Data
    let createdAt: Date
    let retiredAt: Date?

    static func generate(createdAt: Date = Date()) -> SocialKeyMaterial {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return .init(keyID: SocialCheckInCrypto.keyID(for: key.publicKey.rawRepresentation),
                     privateKeyData: key.rawRepresentation, createdAt: createdAt,
                     retiredAt: nil)
    }

    func retired(at date: Date) -> SocialKeyMaterial {
        .init(keyID: keyID, privateKeyData: privateKeyData,
              createdAt: createdAt, retiredAt: retiredAt ?? date)
    }

    var privateKey: Curve25519.KeyAgreement.PrivateKey {
        get throws { try .init(rawRepresentation: privateKeyData) }
    }

    var publicIdentity: CheckInPublicIdentity {
        get throws {
            let key = try privateKey
            return .init(version: SocialCheckInCrypto.version, keyID: keyID,
                         publicKey: key.publicKey.rawRepresentation)
        }
    }
}

enum SocialKeyResolution: Equatable {
    case generate
    case publish(keyID: String)
    case ready(keyID: String)
    case waitForSync(keyID: String)

    static func resolve(profileKeyID: String?, localKeys: [SocialKeyMaterial]) -> SocialKeyResolution {
        if let profileKeyID {
            return localKeys.contains(where: { $0.keyID == profileKeyID })
                ? .ready(keyID: profileKeyID) : .waitForSync(keyID: profileKeyID)
        }
        guard let newest = localKeys.filter({ $0.retiredAt == nil })
            .max(by: { $0.createdAt < $1.createdAt }) else { return .generate }
        return .publish(keyID: newest.keyID)
    }

    static func prunableKeyIDs(_ keys: [SocialKeyMaterial], currentKeyID: String,
                               now: Date) -> Set<String> {
        Set(keys.compactMap { key in
            guard key.keyID != currentKeyID, let retiredAt = key.retiredAt,
                  now.timeIntervalSince(retiredAt) > Social.checkInTTL else { return nil }
            return key.keyID
        })
    }
}

protocol SocialKeyStoring {
    func keys(userID: String) throws -> [SocialKeyMaterial]
    func save(_ key: SocialKeyMaterial, userID: String) throws
    func delete(keyID: String, userID: String) throws
    func deleteAll(userID: String) throws
}
```

Implement `SocialKeyStore` with `kSecClassGenericPassword`, service
`com.normanhoang.nycgaybars.social-checkin-key`, account
`<userID>|<keyID>`, JSON `kSecValueData`, `kSecAttrSynchronizable = true`, and
`kSecAttrAccessibleWhenUnlocked`. Queries use `kSecAttrSynchronizableAny`,
`kSecMatchLimitAll`, `kSecReturnAttributes`, and `kSecReturnData`. Treat
`errSecItemNotFound` as an empty result and surface every other status as a
typed `KeychainError(status:)`.

Use this concrete item shape and save path:

```swift
struct SocialKeyStore: SocialKeyStoring {
    struct KeychainError: Error, Equatable { let status: OSStatus }
    private let service: String

    init(service: String = "com.normanhoang.nycgaybars.social-checkin-key") {
        self.service = service
    }

    func save(_ key: SocialKeyMaterial, userID: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID + "|" + key.keyID,
            kSecAttrSynchronizable: kCFBooleanTrue as Any,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: try JSONEncoder().encode(key),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError(status: update) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }
}
```

`keys(userID:)` fetches every item for the exact service, filters returned
account attributes to the exact `<userID>|` prefix, decodes
`SocialKeyMaterial`, rejects entries whose private key cannot decode or whose
derived public-key ID differs from the stored `keyID`, and sorts by
`createdAt`. `delete(keyID:userID:)` deletes one exact service/account pair.
`deleteAll(userID:)` enumerates
that filtered result and deletes each exact service/account pair, so it never
deletes another account or another test service.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Task 3 command. Expected: all resolution and isolated Keychain cases pass.

- [ ] **Step 5: Commit**

```bash
git add NYCGayBars/Services/SocialKeyStore.swift NYCGayBarsTests/SocialKeyStoreTests.swift NYCGayBars.xcodeproj/project.pbxproj
git commit -m "feat(security): sync Friends keys in Keychain"
```

### Task 4: CloudKit Profile keys and opaque `CheckInV2` transport

**Files:**
- Modify: `NYCGayBars/Services/CloudKitSocial.swift:4-461`
- Create: `NYCGayBarsTests/CloudKitSocialRecordTests.swift`
- Regenerate: `NYCGayBars.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `createProfile(userID:displayName:identity:)`, `updateProfileKey(userID:identity:)`, `createCheckIns(_:)`, `tonightCheckInEnvelopes(userID:now:)`, `deleteCheckInV2(authorID:recipientID:)`, `deleteCheckInV2(authorID:at:attempts:)`, `deleteCheckInV2(recordNames:)`, `deleteExpiredCheckInV2(authorID:now:)`, and `deleteLegacyCheckIns(authorID:)`.
- Consumes: Task 1 envelope/Profile types.
- Consumed by: Tasks 5–7.

- [ ] **Step 1: Add failing local CKRecord mapping tests**

```swift
import CloudKit
import XCTest
@testable import NYCGayBars

final class CloudKitSocialRecordTests: XCTestCase {
    func testProfileRoundTripsPublicIdentity() throws {
        let rec = CKRecord(recordType: "Profile", recordID: .init(recordName: "profile-a"))
        rec["userID"] = "a"; rec["displayName"] = "Alex"; rec["code"] = "ABC234"
        rec["checkInCryptoVersion"] = Int64(2)
        rec["checkInKeyID"] = "key"
        rec["checkInPublicKey"] = Data(repeating: 1, count: 32)
        let profile = try XCTUnwrap(CloudKitSocial.profile(from: rec))
        XCTAssertEqual(profile.checkInKeyID, "key")
    }

    func testV2RecordContainsNoPlaintextPayloadFields() throws {
        let envelope = EncryptedCheckInEnvelope(
            recordName: "v2", authorID: "a", recipientID: "b", sentAt: Date(),
            protocolVersion: 2, senderKeyID: "sender", senderPublicKey: Data([1]),
            recipientKeyID: "recipient", encapsulatedKey: Data([2]), ciphertext: Data([3]))
        let rec = CloudKitSocial.record(from: envelope)
        XCTAssertEqual(Set(rec.allKeys()), Set(["authorID", "recipientID", "sentAt",
            "protocolVersion", "senderKeyID", "senderPublicKey", "recipientKeyID",
            "encapsulatedKey", "ciphertext"]))
        XCTAssertNil(rec["authorName"]); XCTAssertNil(rec["barId"]); XCTAssertNil(rec["barName"])
        XCTAssertEqual(CloudKitSocial.envelope(from: rec), envelope)
    }

    func testV2CreatorGateRequiresMatchingStampedCreator() {
        XCTAssertFalse(CloudKitSocial.creatorMatchesV2(creatorID: nil, claimedID: "a"))
        XCTAssertFalse(CloudKitSocial.creatorMatchesV2(creatorID: "attacker", claimedID: "a"))
        XCTAssertTrue(CloudKitSocial.creatorMatchesV2(creatorID: "a", claimedID: "a"))
        XCTAssertTrue(CloudKitSocial.creatorMatchesV2(
            creatorID: "__defaultOwner__", claimedID: "a"))
    }
}
```

- [ ] **Step 2: Regenerate and verify RED**

```bash
xcodegen generate
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test -only-testing:NYCGayBarsTests/CloudKitSocialRecordTests
```

Expected: compile failures for the inaccessible/missing mapping functions.

- [ ] **Step 3: Replace the plaintext check-in record path**

Use distinct record-type constants:

```swift
private enum RT {
    static let profile = "Profile"
    static let request = "FriendRequest"
    static let friendship = "Friendship"
    static let legacyCheckIn = "CheckIn"
    static let checkInV2 = "CheckInV2"
}
```

Make `profile(from:)`, `record(from:)`, and `envelope(from:)` internal for
`@testable` access. `record(from:)` must use the envelope's preallocated record
name and only the nine asserted fields. Keep field decoding separate from the
creator check so local records remain unit-testable; the live query path must
call strict `creatorMatchesV2(creatorID:claimedID:)` before decoding.

Update profile creation/mapping:

```swift
func createProfile(userID: String, displayName: String,
                   identity: CheckInPublicIdentity) async throws -> FriendProfile

func updateProfileKey(userID: String,
                      identity: CheckInPublicIdentity) async throws -> FriendProfile {
    let rec = try await db.record(for: profileRecordID(userID))
    rec["checkInCryptoVersion"] = identity.version
    rec["checkInKeyID"] = identity.keyID
    rec["checkInPublicKey"] = identity.publicKey
    return Self.profile(from: try await db.save(rec))!
}

static func profile(from rec: CKRecord) -> FriendProfile? {
    guard let userID = rec["userID"] as? String,
          let name = rec["displayName"] as? String,
          let code = rec["code"] as? String else { return nil }
    return FriendProfile(
        id: userID, displayName: name, code: code,
        checkInCryptoVersion: rec["checkInCryptoVersion"] as? Int64,
        checkInKeyID: rec["checkInKeyID"] as? String,
        checkInPublicKey: rec["checkInPublicKey"] as? Data)
}

static func record(from envelope: EncryptedCheckInEnvelope) -> CKRecord {
    let rec = CKRecord(recordType: RT.checkInV2,
                       recordID: .init(recordName: envelope.recordName))
    rec["authorID"] = envelope.authorID
    rec["recipientID"] = envelope.recipientID
    rec["sentAt"] = envelope.sentAt
    rec["protocolVersion"] = envelope.protocolVersion
    rec["senderKeyID"] = envelope.senderKeyID
    rec["senderPublicKey"] = envelope.senderPublicKey
    rec["recipientKeyID"] = envelope.recipientKeyID
    rec["encapsulatedKey"] = envelope.encapsulatedKey
    rec["ciphertext"] = envelope.ciphertext
    return rec
}

static func envelope(from rec: CKRecord) -> EncryptedCheckInEnvelope? {
    guard let authorID = rec["authorID"] as? String,
          let recipientID = rec["recipientID"] as? String,
          let sentAt = rec["sentAt"] as? Date,
          let version = rec["protocolVersion"] as? Int64,
          let senderKeyID = rec["senderKeyID"] as? String,
          let senderPublicKey = rec["senderPublicKey"] as? Data,
          let recipientKeyID = rec["recipientKeyID"] as? String,
          let encapsulatedKey = rec["encapsulatedKey"] as? Data,
          let ciphertext = rec["ciphertext"] as? Data else { return nil }
    return .init(recordName: rec.recordID.recordName, authorID: authorID,
                 recipientID: recipientID, sentAt: sentAt,
                 protocolVersion: version, senderKeyID: senderKeyID,
                 senderPublicKey: senderPublicKey, recipientKeyID: recipientKeyID,
                 encapsulatedKey: encapsulatedKey, ciphertext: ciphertext)
}

static func creatorMatchesV2(creatorID: String?, claimedID: String) -> Bool {
    guard let creatorID else { return false }
    return creatorID == claimedID || creatorID == "__defaultOwner__"
}
```

Add opaque envelope operations alongside the legacy methods so this task stays
buildable and reviewable on its own:

```swift
func createCheckIns(_ envelopes: [EncryptedCheckInEnvelope]) async throws
    -> (saved: [CKRecord.ID], failure: Error?)

func tonightCheckInEnvelopes(userID: String, now: Date = Date()) async throws
    -> [EncryptedCheckInEnvelope]
```

The live query maps records only after:

```swift
records.compactMap { rec in
    guard Self.creatorMatchesV2(creatorID: rec.creatorUserRecordID?.recordName,
                                claimedID: rec["authorID"] as? String ?? "")
    else { return nil }
    return Self.envelope(from: rec)
}
```

The V2 query uses `CheckInV2`, `recipientID == userID`, and `sentAt > cutoff`,
sorted by `sentAt`. Add `deleteCheckInV2(authorID:recipientID:)`,
`deleteCheckInV2(authorID:at:attempts:)`,
`deleteCheckInV2(recordNames:)`, and
`deleteExpiredCheckInV2(authorID:now:)`; each targets `CheckInV2` and uses
`sentAt` where the old implementation used `ts`. Add a
best-effort `deleteLegacyCheckIns(authorID:)` querying legacy `CheckIn` by
`authorID`; callers ignore permission errors because the production cutoff
revokes legacy grants.

Keep the old plaintext methods only until Task 6 switches every call site in
one green step. Task 6 then removes the old writer, reader, rename, and
plaintext record decoder completely.

- [ ] **Step 4: Run mapping tests, then full tests**

Run the Task 4 command, followed by the full test command. Expected: mapping
tests and the existing suite pass because the legacy call sites remain intact
until Task 6.

- [ ] **Step 5: Commit when call sites compile**

```bash
git add NYCGayBars/Services/CloudKitSocial.swift NYCGayBarsTests/CloudKitSocialRecordTests.swift NYCGayBars.xcodeproj/project.pbxproj
git commit -m "feat(cloudkit): transport encrypted check-ins"
```

### Task 5: SocialStore key bootstrap, synchronization wait, and reset

**Files:**
- Modify: `NYCGayBars/Stores/SocialStore.swift:10-130,314-356,750-825`
- Modify: `NYCGayBarsTests/SocialTests.swift`

**Interfaces:**
- Produces: `CheckInSecurityState`, published `checkInSecurityState`, `resetCheckInKey()`, and a ready private `checkInKey`.
- Consumes: Tasks 1, 3, and 4.
- Consumed by: Tasks 6–7.

- [ ] **Step 1: Add failing tests for rename preservation and the exact sync-to-reset threshold**

```swift
func testRenamedProfilePreservesEncryptionIdentity() {
    let profile = FriendProfile(id: "me", displayName: "Before", code: "ABC234",
                                checkInCryptoVersion: 2, checkInKeyID: "key",
                                checkInPublicKey: Data(repeating: 7, count: 32))
    let renamed = profile.renamed(to: "After")
    XCTAssertEqual(renamed.displayName, "After")
    XCTAssertEqual(renamed.checkInCryptoVersion, 2)
    XCTAssertEqual(renamed.checkInKeyID, "key")
    XCTAssertEqual(renamed.checkInPublicKey, Data(repeating: 7, count: 32))
}

func testKeySyncRetryRequiresThreeAttemptsAndSixSeconds() {
    XCTAssertFalse(SocialKeySyncRetry.shouldOfferReset(attempts: 2, elapsed: 10))
    XCTAssertFalse(SocialKeySyncRetry.shouldOfferReset(attempts: 3, elapsed: 5.9))
    XCTAssertTrue(SocialKeySyncRetry.shouldOfferReset(attempts: 3, elapsed: 6))
}
```

- [ ] **Step 2: Run `SocialTests` and verify RED**

Use the Task 1 focused test command. Expected: compile failure because
`SocialKeySyncRetry` does not exist.

- [ ] **Step 3: Add key state and bootstrap logic**

```swift
// File scope, immediately before SocialStore.
enum CheckInSecurityState: Equatable {
    case unknown, ready, syncing, resetRequired
}

enum SocialKeySyncRetry {
    static func shouldOfferReset(attempts: Int, elapsed: TimeInterval) -> Bool {
        attempts >= 3 && elapsed >= 6
    }
}

// Stored properties inside SocialStore.
@Published private(set) var checkInSecurityState: CheckInSecurityState = .unknown
private let keyStore: any SocialKeyStoring = SocialKeyStore()
private var checkInKey: SocialKeyMaterial?
```

Implement the exact bootstrap loop and explicit reset as the only mismatch
recovery:

```swift
private func prepareCheckInKey(userID: String, profile current: FriendProfile?) async throws {
    let started = Date()
    var attempts = 0
    while true {
        let localKeys = try keyStore.keys(userID: userID)
        switch SocialKeyResolution.resolve(profileKeyID: current?.checkInKeyID,
                                            localKeys: localKeys) {
        case .generate:
            let key = SocialKeyMaterial.generate()
            try keyStore.save(key, userID: userID)
            checkInKey = key
            checkInSecurityState = .ready
            if current != nil {
                profile = try await ck.updateProfileKey(userID: userID,
                                                        identity: key.publicIdentity)
                persistProfile()
            }
            return
        case .publish(let keyID), .ready(let keyID):
            guard let key = localKeys.first(where: { $0.keyID == keyID }) else { continue }
            checkInKey = key
            checkInSecurityState = .ready
            if current?.checkInKeyID == nil, current != nil {
                profile = try await ck.updateProfileKey(userID: userID,
                                                        identity: key.publicIdentity)
                persistProfile()
            }
            return
        case .waitForSync:
            attempts += 1
            checkInSecurityState = .syncing
            let elapsed = Date().timeIntervalSince(started)
            if SocialKeySyncRetry.shouldOfferReset(attempts: attempts, elapsed: elapsed) {
                checkInSecurityState = .resetRequired
                return
            }
            try await Task.sleep(nanoseconds: attempts == 1 ? 2_000_000_000 : 4_000_000_000)
        }
    }
}
```

A later `start` or manual refresh repeats the same three reads so delayed
Keychain synchronization can still recover the published key. Neither path
overwrites a mismatched profile key.

```swift
func resetCheckInKey() async {
    guard let me = userID else { return }
    do {
        if let previous = checkInKey {
            try keyStore.save(previous.retired(at: Date()), userID: me)
        }
        let key = SocialKeyMaterial.generate()
        try keyStore.save(key, userID: me)
        profile = try await ck.updateProfileKey(userID: me, identity: key.publicIdentity)
        checkInKey = key
        checkInSecurityState = .ready
        persistProfile()
        await refreshTonight()
    } catch {
        errorMessage = friendlyError(error)
    }
}
```

After any key becomes ready, mark noncurrent, nonretired local keys retired at
the current time. Delete only IDs returned by
`SocialKeyResolution.prunableKeyIDs(_:currentKeyID:now:)`. This preserves an
available previous recipient key through the full six-hour record TTL while
preventing indefinite key accumulation.

Call key preparation after fetching an existing profile in `start()`. For a new
user, generate/save before `createProfile` and pass the public identity into
CloudKit profile creation. Change optimistic rename to
`profile = current.renamed(to: name)` and remove the legacy check-in rename.
On account change, clear in-memory key state but do not delete Keychain items.

- [ ] **Step 4: Build and run `SocialTests`**

Expected: compile succeeds, rename test passes, and the iCloud-unavailable path does not access Keychain.

- [ ] **Step 5: Commit**

```bash
git add NYCGayBars/Stores/SocialStore.swift NYCGayBarsTests/SocialTests.swift
git commit -m "feat(social): bootstrap encrypted check-in keys"
```

### Task 6: Encrypted share, feed, removal, and recipient preflight

**Files:**
- Modify: `NYCGayBars/Logic/SocialCheckInCrypto.swift`
- Modify: `NYCGayBars/Stores/SocialStore.swift:173-310,501-675`
- Modify: `NYCGayBarsTests/SocialCheckInCryptoTests.swift`

**Interfaces:**
- Produces: the complete encrypted Friends check-in runtime path.
- Consumes: all interfaces from Tasks 1–5.

- [ ] **Step 1: Add failing batch-validation tests**

```swift
func testOpenAllKeepsOnlyAddressedAllowedAuthenticatedRecords() throws {
    let mine = try envelope()
    let result = SocialCheckInCrypto.openAll(
        [mine], recipientID: "recipient", allowedAuthorIDs: ["author"],
        privateKeysByID: [mine.recipientKeyID: recipient])
    XCTAssertEqual(result.checkIns.map(\.id), [mine.id])
    XCTAssertEqual(result.failureCount, 0)
}

func testOpenAllCountsWrongRecipientAndUnknownKeyWithoutThrowing() throws {
    let mine = try envelope()
    let result = SocialCheckInCrypto.openAll(
        [mine.replacing(recipientID: "other")], recipientID: "recipient",
        allowedAuthorIDs: ["author"], privateKeysByID: [:])
    XCTAssertTrue(result.checkIns.isEmpty)
    XCTAssertEqual(result.failureCount, 1)
}
```

- [ ] **Step 2: Run codec tests and verify RED**

Expected: compile failure because `openAll` and its result type do not exist.

- [ ] **Step 3: Implement strict batch opening**

```swift
struct OpenResult {
    let checkIns: [FriendCheckIn]
    let failureCount: Int
}

static func openAll(_ envelopes: [EncryptedCheckInEnvelope], recipientID: String,
                    allowedAuthorIDs: Set<String>,
                    privateKeysByID: [String: Curve25519.KeyAgreement.PrivateKey]) -> OpenResult {
    var opened: [FriendCheckIn] = []
    var failures = 0
    for envelope in envelopes {
        guard envelope.recipientID == recipientID,
              allowedAuthorIDs.contains(envelope.authorID),
              let key = privateKeysByID[envelope.recipientKeyID],
              let checkIn = try? open(envelope, recipientPrivateKey: key) else {
            failures += 1
            continue
        }
        opened.append(checkIn)
    }
    return .init(checkIns: opened, failureCount: failures)
}
```

- [ ] **Step 4: Replace `shareCheckIn` with encrypted all-or-nothing preparation**

Freshly fetch selected profiles, preserve input order, and reject the entire
share if any ID is absent or has an invalid/unsupported identity:

```swift
let recipientIDs = prefs.recipients(of: friends.map(\.id))
let fetched = try await ck.profiles(userIDs: recipientIDs)
let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
let missing = recipientIDs.filter { byID[$0]?.checkInIdentity == nil }
guard missing.isEmpty else {
    errorMessage = "\(missing.count) selected friend\(missing.count == 1 ? "" : "s") need to update before you can share."
    return false
}
guard let key = checkInKey, case .ready = checkInSecurityState,
      let selfIdentity = profile?.checkInIdentity else {
    errorMessage = "Your Friends security key is still syncing."
    return false
}
let sentAt = SocialCheckInCrypto.normalized(Date())
let targets = recipientIDs.compactMap { id in byID[id]?.checkInIdentity.map { (id, $0) } }
    + [(me.id, selfIdentity)]
let envelopes = try targets.map { id, identity in
    try SocialCheckInCrypto.seal(
        recordName: "checkin-v2-\(UUID().uuidString.lowercased())",
        authorID: me.id, recipientID: id, sentAt: sentAt,
        senderPrivateKey: key.privateKey, recipient: identity,
        authorName: me.displayName, barID: bar.id, barName: bar.name)
}
let (saved, failure) = try await ck.createCheckIns(envelopes)
```

Retain IDs on partial saves and publish the existing optimistic own row only on
full success. There is no call to the legacy writer.

- [ ] **Step 5: Replace fetch/decrypt and point all lifecycle operations at V2**

In `performRefresh` and `refreshTonight`, fetch
`tonightCheckInEnvelopes(userID:)`, load all local account keys whose IDs occur
in the envelopes, call `openAll` with current friends plus `me`, and pass only
opened `FriendCheckIn` values into the unchanged `rebuildTonight`. Set one
aggregate info message when `failureCount > 0`; do not include IDs or crypto
errors.

Use one helper from both fetch paths:

```swift
private func decryptCheckIns(_ envelopes: [EncryptedCheckInEnvelope], me: String,
                             friendIDs: Set<String>) throws -> [FriendCheckIn] {
    let needed = Set(envelopes.map(\.recipientKeyID))
    let pairs = try keyStore.keys(userID: me)
        .filter { needed.contains($0.keyID) }
        .map { ($0.keyID, try $0.privateKey) }
    let result = SocialCheckInCrypto.openAll(
        envelopes, recipientID: me, allowedAuthorIDs: friendIDs.union([me]),
        privateKeysByID: Dictionary(uniqueKeysWithValues: pairs))
    if result.failureCount > 0 {
        infoMessage = "Some encrypted check-ins couldn't be opened."
    }
    return result.checkIns
}
```

Use `deleteCheckInV2(authorID:recipientID:)` for unfriend revocation,
`deleteCheckInV2(recordNames:)` for retained fan-outs,
`deleteCheckInV2(authorID:at:attempts:)` for timestamp fallback, and
`deleteExpiredCheckInV2(authorID:now:)` for TTL cleanup. On `start`, call
`try? await ck.deleteLegacyCheckIns(authorID: me)` as defense in depth, but do
not query legacy records for display.

- [ ] **Step 6: Run codec tests, `SocialTests`, then the full suite**

Expected: all tests pass; source search below returns only migration/docs references:

```bash
rg -n 'rec\["(authorName|barId|barName)"\]|RT\.checkIn\b|tonightCheckIns\(' NYCGayBars
```

- [ ] **Step 7: Commit**

```bash
git add NYCGayBars/Logic/SocialCheckInCrypto.swift NYCGayBars/Stores/SocialStore.swift NYCGayBarsTests/SocialCheckInCryptoTests.swift
git commit -m "feat(social): encrypt recipient check-in flow"
```

### Task 7: Key recovery UI and generic notification path

**Files:**
- Modify: `NYCGayBars/Screens/FriendsView.swift:32-287,487-503`
- Modify: `NYCGayBars/Services/CloudKitSocial.swift:324-377`
- Modify: `NYCGayBars/NYCGayBarsApp.swift:24-52`
- Modify: `NYCGayBars/en.lproj/Localizable.strings`
- Modify: `NYCGayBarsTests/CloudKitSocialRecordTests.swift`

**Interfaces:**
- Consumes: `checkInSecurityState` and `resetCheckInKey()` from Task 5.
- Produces: visible sync/reset behavior and a future-safe generic push.

- [ ] **Step 1: Add key-state banners and explicit reset confirmation**

Add `@State private var showKeyResetConfirm = false`. Under the existing error
and info banners, render `.syncing` as non-destructive copy and
`.resetRequired` as a compact content panel with a button:

```swift
if social.checkInSecurityState == .syncing {
    infoBanner("Your Friends security key is syncing from iCloud. Friend management still works.")
        .padding(.bottom, 12)
} else if social.checkInSecurityState == .resetRequired {
    VStack(alignment: .leading, spacing: 8) {
        Text("Your Friends security key couldn't be recovered.")
            .font(.scaled(14, weight: .semibold)).foregroundStyle(.white)
        Button("Reset security key") { showKeyResetConfirm = true }
            .font(.scaled(14, weight: .bold)).foregroundStyle(Palette.primary)
    }
    .padding(12).contentPanel().padding(.bottom, 12)
}
```

Add a confirmation dialog whose destructive action calls
`await social.resetCheckInKey()` and whose message says active check-ins sent
to the old key may become unreadable; friendships and local history remain.
Update onboarding/footer copy to state that shared name/bar payloads are
end-to-end encrypted for selected friends.

```swift
.confirmationDialog("Reset Friends security key?",
                    isPresented: $showKeyResetConfirm,
                    titleVisibility: .visible) {
    Button("Reset security key", role: .destructive) {
        Task { await social.resetCheckInKey() }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Active check-ins sent to the old key may become unreadable. Your friendships and local history won't be deleted.")
}
```

- [ ] **Step 2: Add and run a failing generic-push test**

```swift
func testCheckInNotificationCarriesNoPlaintextDesiredFields() {
    let info = CloudKitSocial.checkInNotificationInfo()
    XCTAssertEqual(info.alertLocalizationKey, "FRIEND_CHECKIN_GENERIC_ALERT")
    XCTAssertNil(info.alertLocalizationArgs)
    XCTAssertNil(info.desiredKeys)
}
```

Run `CloudKitSocialRecordTests`. Expected: compile failure because
`checkInNotificationInfo()` does not exist.

- [ ] **Step 3: Remove plaintext-dependent check-in push payloads**

Point a future check-in subscription at `CheckInV2`, keep the
`authorID/recipientID` predicate, use localization key
`FRIEND_CHECKIN_GENERIC_ALERT`, and remove alert args and `desiredKeys`:

```strings
"FRIEND_CHECKIN_GENERIC_ALERT" = "A friend shared a check-in";
```

```swift
static func checkInNotificationInfo() -> CKSubscription.NotificationInfo {
    let info = CKSubscription.NotificationInfo()
    info.alertLocalizationKey = "FRIEND_CHECKIN_GENERIC_ALERT"
    info.soundName = "default"
    info.category = checkInCategory
    return info
}
```

In `AppDelegate.didReceive`, treat both request and check-in subscription IDs
as Friends-tab navigation. Remove the `barId` payload read and direct bar-sheet
deep link for check-in notifications. Current `Social.checkInPushEnabled`
remains `false`.

- [ ] **Step 4: Build and run the focused test, then the full suite**

Expected: build/test passes and `rg -n 'FRIEND_CHECKIN_ALERT|desiredKeys = \["barId"' NYCGayBars` returns no matches.

- [ ] **Step 5: Commit**

```bash
git add NYCGayBars/Screens/FriendsView.swift NYCGayBars/Services/CloudKitSocial.swift NYCGayBars/NYCGayBarsApp.swift NYCGayBars/en.lproj/Localizable.strings NYCGayBarsTests/CloudKitSocialRecordTests.swift
git commit -m "feat(friends): add encryption recovery UI"
```

### Task 8: Privacy documentation and CloudKit hard-cutoff runbook

**Files:**
- Modify: `CLAUDE.md:73-84`
- Modify: `docs/privacy.html`
- Modify: `docs/support.html`
- Modify: `docs/appstore/index.html`
- Create: `docs/cloudkit-checkin-v2-rollout.md`
- Review without changing unless declarations differ: `NYCGayBars/PrivacyInfo.xcprivacy`, `project.yml`, `NYCGayBars/Info.plist`

**Interfaces:**
- Produces: operator-ready schema deployment and accurate user disclosures.

- [ ] **Step 1: Update repository architecture guidance**

Replace plaintext `CheckIn` notes with `CheckInV2`, authenticated HPKE,
synchronizable Keychain, public routing metadata, encrypted payload fields,
recipient preflight, generic push, lost-key behavior, and the no-fallback
invariant. Preserve the eventual-consistency, handshake, fan-out removal, and
3h/6h notes that remain valid.

- [ ] **Step 2: Update privacy/support/store copy**

State precisely:

```text
Shared check-in names and bar details are encrypted on the sender's device for
each selected friend and decrypted on that friend's device. Apple iCloud still
stores routing metadata identifying the sender, recipient, and send time.
```

Update the privacy-policy date. Keep Name, User ID, and Other User Content as
linked App Functionality data in App Store copy and the privacy manifest; do
not claim that routing metadata is hidden from Apple.

- [ ] **Step 3: Write the exact production runbook**

Include this V2 schema shape and verify it in CloudKit Console before release:

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

Also list the three optional Profile fields, development-environment two-device
test, production schema deployment, legacy `CheckIn` create/read grant
revocation, administrative purge, anonymous-read rejection, authenticated
ciphertext-only inspection, and old-client write rejection. Mark the CloudKit
operations as manual release gates; do not claim local code performed them.

- [ ] **Step 4: Record export-compliance gate**

Document that App Store Connect's encryption questionnaire must be rerun for
CryptoKit HPKE before release. Keep `ITSAppUsesNonExemptEncryption` unchanged
until the account holder records Apple's determination; do not infer a legal
classification from the implementation.

- [ ] **Step 5: Verify disclosure consistency and commit**

```bash
rg -n -i 'end-to-end|routing metadata|CheckInV2|HPKE|Keychain|export compliance' CLAUDE.md docs NYCGayBars/PrivacyInfo.xcprivacy project.yml
git diff --check
git add CLAUDE.md docs/privacy.html docs/support.html docs/appstore/index.html docs/cloudkit-checkin-v2-rollout.md
git commit -m "docs(security): document encrypted check-ins"
```

### Task 9: Full verification and manual release gates

**Files:**
- Regenerate: `NYCGayBars.xcodeproj/project.pbxproj`
- Update only if XcodeGen output changes: generated project file

**Interfaces:**
- Verifies the complete implementation; produces no new feature behavior.

- [ ] **Step 1: Regenerate and verify the tracked project**

```bash
xcodegen generate
git diff --check
```

- [ ] **Step 2: Run focused security tests**

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test \
  -only-testing:NYCGayBarsTests/SocialCheckInCryptoTests \
  -only-testing:NYCGayBarsTests/SocialKeyStoreTests \
  -only-testing:NYCGayBarsTests/CloudKitSocialRecordTests
```

Expected: zero test failures and no warnings containing plaintext payloads or key bytes.

- [ ] **Step 3: Run the full test suite and clean build**

```bash
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
xcodebuild -scheme NYCGayBars -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' clean build
```

Expected: both commands exit 0.

- [ ] **Step 4: Prove the V2 source path has no plaintext fields or fallback**

```bash
rg -n 'CheckInV2|ciphertext|encapsulatedKey' NYCGayBars
rg -n 'rec\["(authorName|barId|barName)"\]|FRIEND_CHECKIN_ALERT|RT\.checkIn\b' NYCGayBars
```

Expected: the first command shows the V2 implementation; the second has no runtime matches. Legacy names may appear only in the isolated administrative deletion function or documentation, never the V2 writer/reader.

- [ ] **Step 5: Review the exact diff against the design**

Confirm every success criterion in the design has a code path, automated test,
or explicitly marked manual release gate. Confirm no unrelated refactor or
formatting entered the diff.

- [ ] **Step 6: Commit generated-project changes if any**

```bash
git add NYCGayBars.xcodeproj/project.pbxproj
git commit -m "build: register encrypted check-in sources"
```

Skip this commit when XcodeGen produced no remaining diff.

- [ ] **Step 7: Perform device and CloudKit gates before release**

Use two different iCloud accounts to verify recipient-only round trips,
removal, revocation, and update-required blocking. Use two devices on one
account to verify Keychain synchronization, delayed sync, and explicit reset.
Then execute `docs/cloudkit-checkin-v2-rollout.md` in production and record the
App Store Connect export-compliance result. These external actions require the
account holder and are not represented as completed by local tests.
