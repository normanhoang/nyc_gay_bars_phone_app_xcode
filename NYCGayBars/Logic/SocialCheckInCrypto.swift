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
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func keyID(for publicKey: Data) -> String {
        "v2." + Data(SHA256.hash(data: publicKey).prefix(16)).base64EncodedString()
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
        let seconds = try timestampSeconds(sentAt, requireCanonical: false)
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
        let seconds = try timestampSeconds(envelope.sentAt, requireCanonical: true)
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

    private static func timestampSeconds(_ date: Date, requireCanonical: Bool) throws -> Int64 {
        let interval = date.timeIntervalSince1970
        guard interval.isFinite else { throw CryptoError.invalidTimestamp }
        let canonical = interval.rounded(.down)
        guard let seconds = Int64(exactly: canonical),
              !requireCanonical || interval == canonical else {
            throw CryptoError.invalidTimestamp
        }
        return seconds
    }
}
