import Foundation
import Security

enum KeychainError: LocalizedError {
    case notFound
    case denied
    case unreadable(OSStatus)
    case malformed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No Claude Code credentials in your keychain. Sign in with `claude` once."
        case .denied:
            return "Keychain access was denied. Allow Claude Usage in Keychain Access."
        case .unreadable(let status):
            return "Keychain returned \(status)."
        case .malformed:
            return "The stored credentials are not in a shape the app recognises."
        }
    }
}

struct OAuthCredentials {
    let accessToken: String
    let expiresAt: Date?
    let subscription: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

enum Keychain {
    static let service = "Claude Code-credentials"

    static func claudeCredentials() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: throw KeychainError.notFound
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw KeychainError.denied
        default: throw KeychainError.unreadable(status)
        }

        guard let data = item as? Data else { throw KeychainError.malformed }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> OAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw KeychainError.malformed }

        // Claude Code nests under claudeAiOauth; tolerate a flatter shape too.
        let scope = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard
            let token = (scope["accessToken"] ?? scope["access_token"]) as? String,
            !token.isEmpty
        else { throw KeychainError.malformed }

        var expiry: Date?
        if let millis = (scope["expiresAt"] ?? scope["expires_at"]) as? NSNumber {
            let value = millis.doubleValue
            expiry = Date(timeIntervalSince1970: value > 1e11 ? value / 1000 : value)
        }

        return OAuthCredentials(
            accessToken: token,
            expiresAt: expiry,
            subscription: (scope["subscriptionType"] ?? scope["subscription_type"]) as? String
        )
    }
}
