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
        XCTAssertThrowsError(try SocialCheckInCrypto.open(envelope, recipientPrivateKey: recipient))
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
