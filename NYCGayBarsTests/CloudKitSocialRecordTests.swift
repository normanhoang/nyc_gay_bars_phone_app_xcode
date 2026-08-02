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

    func testCheckInNotificationCarriesNoPlaintextDesiredFields() {
        let info = CloudKitSocial.checkInNotificationInfo()
        XCTAssertEqual(info.alertLocalizationKey, "FRIEND_CHECKIN_GENERIC_ALERT")
        XCTAssertNil(info.alertLocalizationArgs)
        XCTAssertNil(info.desiredKeys)
    }
}
