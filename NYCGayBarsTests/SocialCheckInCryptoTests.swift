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

    func testKeyIDIncludesVersionAndDeterministicDigest() {
        XCTAssertEqual(SocialCheckInCrypto.keyID(for: Data()),
                       "v2.47DEQpj8HBSa-_TImW-5JA")
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

    func testFractionalEnvelopeTimestampCannotOpen() throws {
        let original = try envelope()
        XCTAssertThrowsError(try SocialCheckInCrypto.open(
            original.replacing(sentAt: original.sentAt.addingTimeInterval(0.5)),
            recipientPrivateKey: recipient)) { error in
            XCTAssertEqual(error as? SocialCheckInCrypto.CryptoError, .invalidTimestamp)
        }
    }

    func testInvalidEnvelopeTimestampsCannotOpen() throws {
        let original = try envelope()
        let invalidSeconds = [Double.nan, Double.infinity, -Double.infinity,
                              Double(Int64.max)]
        for seconds in invalidSeconds {
            XCTAssertThrowsError(try SocialCheckInCrypto.open(
                original.replacing(sentAt: Date(timeIntervalSince1970: seconds)),
                recipientPrivateKey: recipient)) { error in
                XCTAssertEqual(error as? SocialCheckInCrypto.CryptoError, .invalidTimestamp)
            }
        }
    }

    func testSealRejectsInvalidTimestamps() {
        let identity = CheckInPublicIdentity(
            version: SocialCheckInCrypto.version,
            keyID: SocialCheckInCrypto.keyID(for: recipient.publicKey.rawRepresentation),
            publicKey: recipient.publicKey.rawRepresentation)
        let invalidSeconds = [Double.nan, Double.infinity, -Double.infinity,
                              Double(Int64.max)]
        for seconds in invalidSeconds {
            XCTAssertThrowsError(try SocialCheckInCrypto.seal(
                recordName: "invalid-time", authorID: "author", recipientID: "recipient",
                sentAt: Date(timeIntervalSince1970: seconds), senderPrivateKey: sender,
                recipient: identity, authorName: "Alex", barID: "stonewall",
                barName: "Stonewall Inn")) { error in
                XCTAssertEqual(error as? SocialCheckInCrypto.CryptoError, .invalidTimestamp)
            }
        }
    }

    func testChangedRecipientKeyCannotOpen() throws {
        let original = try envelope()
        XCTAssertThrowsError(try SocialCheckInCrypto.open(
            original.replacing(recipientKeyID: "wrong"), recipientPrivateKey: recipient))
    }

    func testChangedEncapsulatedKeyCannotOpen() throws {
        let original = try envelope()
        var changedKey = original.encapsulatedKey
        changedKey[changedKey.startIndex] ^= 0x01
        XCTAssertEqual(changedKey.count, original.encapsulatedKey.count)
        XCTAssertThrowsError(try SocialCheckInCrypto.open(
            original.replacing(encapsulatedKey: changedKey), recipientPrivateKey: recipient))
    }

    func testMalformedEncapsulatedKeyCannotOpen() throws {
        let original = try envelope()
        XCTAssertThrowsError(try SocialCheckInCrypto.open(
            original.replacing(encapsulatedKey: Data([0])), recipientPrivateKey: recipient))
    }

    func testMalformedSenderPublicKeyCannotOpen() throws {
        let malformed = Data([1, 2, 3])
        let changed = try envelope().replacing(
            senderKeyID: SocialCheckInCrypto.keyID(for: malformed), senderPublicKey: malformed)
        XCTAssertThrowsError(try SocialCheckInCrypto.open(changed, recipientPrivateKey: recipient))
    }

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

    func testOpenAllDropsUnknownAuthorAndTamperedRecords() throws {
        let mine = try envelope()
        var ciphertext = mine.ciphertext
        ciphertext[ciphertext.startIndex] ^= 0x01
        let result = SocialCheckInCrypto.openAll(
            [mine, mine.replacing(ciphertext: ciphertext)],
            recipientID: "recipient", allowedAuthorIDs: ["stranger"],
            privateKeysByID: [mine.recipientKeyID: recipient])
        XCTAssertTrue(result.checkIns.isEmpty)
        XCTAssertEqual(result.failureCount, 2)
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
