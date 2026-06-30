import Foundation
import Security

/// Foundation-only Keychain wrapper for the user's OpenAI API key.
///
/// Stays `Security`-only (never `import FoundationModels`) so this file remains in the
/// headless smoke compile set — the same Foundation-only discipline as
/// `OpenAILightingService` / `FallbackLightingService`. The key never lives in the binary,
/// never in `UserDefaults`; the only sanctioned store is the Keychain.
///
/// The item is a generic password keyed on a fixed `service`/`account`
/// (`"tw.iosclub.LumaStage.openai-key"`) and protected with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the tightest reasonable class for a
/// foreground-only secret: readable only while the device is unlocked, never written to a
/// backup, never migrated to another device.
///
/// `SecItem*` is unreliable headlessly (no keychain daemon), so the smoke tests do **not**
/// exercise this type directly — `OpenAILightingService` reads the key through an injectable
/// `apiKeyProvider` (defaulting to `OpenAIKeychain.load`) that the tests stub. These methods
/// keep the pinned synchronous signatures the call sites depend on.
enum OpenAIKeychain {
    /// Shared service/account identifier for the single OpenAI key item.
    private static let identifier = "tw.iosclub.LumaStage.openai-key"

    /// Base query selecting exactly the one generic-password item this wrapper owns.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identifier,
            kSecAttrAccount as String: identifier
        ]
    }

    /// Upsert the API key. Uses the add-or-update pattern (`SecItemAdd`, then `SecItemUpdate`
    /// on `errSecDuplicateItem`) rather than delete-then-add, so an existing item is replaced
    /// atomically without a window in which no key exists. An empty string is treated as a
    /// clear so callers can `store("")` to forget the key.
    static func store(_ key: String) {
        guard !key.isEmpty else {
            delete()
            return
        }

        guard let data = key.data(using: .utf8) else {
            return
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Item already present — update its value (and re-assert accessibility) in place.
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            _ = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        default:
            // Other failures (e.g. errSecInteractionNotAllowed when locked) are non-fatal:
            // the key simply isn't stored, and `availability` will report it as missing.
            return
        }
    }

    /// Read the stored API key, or `nil` if none is set or it can't be read right now.
    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            // errSecInteractionNotAllowed (locked) and any other error: treat as "no key".
            return nil
        }
    }

    /// Remove the stored API key. A missing item is treated as success (idempotent).
    static func delete() {
        let status = SecItemDelete(baseQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            return
        }
    }
}
