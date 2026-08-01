import CryptoKit
import Security
import XCTest
@testable import NYCGayBars

final class SocialKeyStoreTests: XCTestCase {
    private var service: String!
    private var store: SocialKeyStore!

    override func setUp() {
        super.setUp()
        service = "SocialKeyStoreTests.\(UUID().uuidString)"
        store = SocialKeyStore(service: service)
    }

    override func tearDown() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as Any,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        store = nil
        service = nil
        super.tearDown()
    }

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
        let key = SocialKeyMaterial.generate(createdAt: Date(timeIntervalSince1970: 10))
        try store.save(key, userID: "account")
        XCTAssertEqual(try store.keys(userID: "account"), [key])
        XCTAssertTrue(try store.keys(userID: "other").isEmpty)
    }

    func testDuplicateSaveUpdatesExistingAccountKey() throws {
        let key = try fixedKey(seed: 1, createdAt: Date(timeIntervalSince1970: 10))
        let updated = key.retired(at: Date(timeIntervalSince1970: 20))
        try store.save(key, userID: "account")
        try store.save(updated, userID: "account")
        XCTAssertEqual(try store.keys(userID: "account"), [updated])
    }

    func testMalformedKeychainMaterialIsRejected() throws {
        let valid = try fixedKey(seed: 1, createdAt: Date(timeIntervalSince1970: 10))
        let malformedPrivateKey = SocialKeyMaterial(
            keyID: "v2.malformed", privateKeyData: Data([1]),
            createdAt: Date(timeIntervalSince1970: 20), retiredAt: nil)
        try store.save(valid, userID: "account")
        try addRaw(account: "account|invalid-json", data: Data("not-json".utf8))
        try addRaw(account: "account|v2.malformed",
                   data: JSONEncoder().encode(malformedPrivateKey))
        XCTAssertEqual(try store.keys(userID: "account"), [valid])
    }

    func testValidPayloadUnderMismatchedAccountSuffixIsRejected() throws {
        let key = try fixedKey(seed: 1, createdAt: Date(timeIntervalSince1970: 10))
        try addRaw(account: "account|different-key-id", data: JSONEncoder().encode(key))
        XCTAssertTrue(try store.keys(userID: "account").isEmpty)
    }

    func testDeleteAndDeleteAllPreserveOtherUsersAndServices() throws {
        let first = try fixedKey(seed: 1, createdAt: Date(timeIntervalSince1970: 10))
        let second = try fixedKey(seed: 2, createdAt: Date(timeIntervalSince1970: 20))
        let otherUserKey = SocialKeyMaterial.generate(createdAt: Date(timeIntervalSince1970: 30))
        let otherService = SocialKeyStore(service: service + ".other")
        let otherServiceKey = SocialKeyMaterial.generate(createdAt: Date(timeIntervalSince1970: 40))
        defer { try? otherService.deleteAll(userID: "account") }

        try store.save(first, userID: "account")
        try store.save(second, userID: "account")
        try store.save(otherUserKey, userID: "other")
        try otherService.save(otherServiceKey, userID: "account")

        try store.delete(keyID: first.keyID, userID: "account")
        XCTAssertEqual(try store.keys(userID: "account"), [second])
        try store.deleteAll(userID: "account")
        XCTAssertTrue(try store.keys(userID: "account").isEmpty)
        XCTAssertEqual(try store.keys(userID: "other"), [otherUserKey])
        XCTAssertEqual(try otherService.keys(userID: "account"), [otherServiceKey])
    }

    func testKeysSortDeterministicallyByCreationDateThenKeyID() throws {
        let later = SocialKeyMaterial.generate(createdAt: Date(timeIntervalSince1970: 20))
        let lowerID = try fixedKey(seed: 1, createdAt: Date(timeIntervalSince1970: 10))
        let higherID = try fixedKey(seed: 2, createdAt: Date(timeIntervalSince1970: 10))
        try store.save(later, userID: "account")
        try store.save(higherID, userID: "account")
        try store.save(lowerID, userID: "account")
        XCTAssertEqual(try store.keys(userID: "account"), [lowerID, higherID, later])
    }

    func testRetiredKeyPrunesOnlyAfterRecordTTL() {
        let now = Date()
        let current = SocialKeyMaterial.generate(createdAt: now)
            .retired(at: now.addingTimeInterval(-Social.checkInTTL - 1))
        let unretired = SocialKeyMaterial.generate(createdAt: now)
        let recent = SocialKeyMaterial.generate(createdAt: now).retired(at: now.addingTimeInterval(-60))
        let boundary = SocialKeyMaterial.generate(createdAt: now)
            .retired(at: now.addingTimeInterval(-Social.checkInTTL))
        let stale = SocialKeyMaterial.generate(createdAt: now)
            .retired(at: now.addingTimeInterval(-Social.checkInTTL - 1))
        XCTAssertEqual(SocialKeyResolution.prunableKeyIDs(
            [current, unretired, recent, boundary, stale],
            currentKeyID: current.keyID, now: now), [stale.keyID])
    }

    private func fixedKey(seed: UInt8, createdAt: Date) throws -> SocialKeyMaterial {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: Data(repeating: seed, count: 32))
        let keyIDs: [UInt8: String] = [
            1: "v2.GpLyOFLckI2XMWo7E1eCgQ",
            2: "v2.z6VwxlO9ISsQqctVH9ehtA",
        ]
        return SocialKeyMaterial(keyID: try XCTUnwrap(keyIDs[seed]),
                                 privateKeyData: privateKey.rawRepresentation,
                                 createdAt: createdAt, retiredAt: nil)
    }

    private func addRaw(account: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as Any,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanTrue as Any,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
            kSecValueData: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
