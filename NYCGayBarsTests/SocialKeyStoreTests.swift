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
