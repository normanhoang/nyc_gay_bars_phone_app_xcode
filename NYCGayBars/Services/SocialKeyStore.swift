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

struct SocialKeyStore: SocialKeyStoring {
    struct KeychainError: Error, Equatable { let status: OSStatus }

    private let service: String

    init(service: String = "com.normanhoang.nycgaybars.social-checkin-key") {
        self.service = service
    }

    func keys(userID: String) throws -> [SocialKeyMaterial] {
        try items(userID: userID).compactMap { item in
            guard let key = try? JSONDecoder().decode(SocialKeyMaterial.self, from: item.data),
                  let privateKey = try? key.privateKey,
                  SocialCheckInCrypto.keyID(for: privateKey.publicKey.rawRepresentation) == key.keyID,
                  item.account == userID + "|" + key.keyID
            else { return nil }
            return key
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.keyID < $1.keyID
        }
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

    func delete(keyID: String, userID: String) throws {
        try delete(account: userID + "|" + keyID)
    }

    func deleteAll(userID: String) throws {
        for item in try items(userID: userID) {
            try delete(account: item.account)
        }
    }

    private func items(userID: String) throws -> [(account: String, data: Data)] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: kCFBooleanTrue as Any,
            kSecReturnData: kCFBooleanTrue as Any,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status: status) }

        let prefix = userID + "|"
        return (result as? [[String: Any]] ?? []).compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(prefix),
                  let data = item[kSecValueData as String] as? Data
            else { return nil }
            return (account, data)
        }
    }

    private func delete(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
