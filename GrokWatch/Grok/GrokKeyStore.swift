//
//  GrokKeyStore.swift
//  GrokWatch
//
//  The user's own SpaceXSI API key, in the watch's Keychain and nowhere else. It never touches
//  UserDefaults, logs, or any server other than api.x.ai, and it is not backed up off the watch.
//
//  Every query is scoped by class + service + account. A delete with a broad query can remove
//  unrelated Keychain items, so never loosen these.
//

import Foundation
import Security

nonisolated enum GrokKeyStore {
    static let service = "com.myrhex.GrokWatch.xai-api-key"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        #if DEBUG
        if let override = DebugHooks.keyOverride { return override }
        #endif
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Grok: SpaceXSI API key"
        // Readable once the watch has been unlocked since it was turned on, so an answer that
        // finishes with the wrist down still works; never synced or restored to another device.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// "xai-…AB12": enough to recognize the key, not to use it.
    static func hint() -> String? {
        guard let key = read() else { return nil }
        #if DEBUG
        if key == GrokClient.simulatedKey { return "simulated" }
        #endif
        let tail = key.suffix(4)
        return key.hasPrefix("xai-") ? "xai-…\(tail)" : "…\(tail)"
    }
}
