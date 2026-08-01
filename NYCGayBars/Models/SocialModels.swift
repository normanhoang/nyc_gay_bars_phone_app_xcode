import CryptoKit
import Foundation

struct CheckInPublicIdentity: Equatable, Codable {
    let version: Int64
    let keyID: String
    let publicKey: Data
}

/// A user's public friends-feature profile (CloudKit `Profile` record).
/// `id` is the owner's CloudKit user record name. Codable so the own profile
/// and friends list can be cached in UserDefaults for instant/offline launch.
struct FriendProfile: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    /// Short invite code others enter to send this user a friend request.
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

/// An incoming/outgoing friend request (CloudKit `FriendRequest` record).
struct FriendRequestItem: Identifiable, Equatable {
    /// CloudKit record name (needed so the sender can delete it).
    let id: String
    let fromID: String
    let fromName: String
    let toID: String
    /// Server-stamped creation date; a Friendship record only counts as this
    /// request's acceptance if it was created after this.
    let created: Date
}

/// A friend's shared check-in, decoded from a CloudKit `CheckIn` record.
struct FriendCheckIn: Identifiable, Equatable {
    let id: String
    let authorID: String
    let authorName: String
    let barId: String
    let barName: String
    let date: Date
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
