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
