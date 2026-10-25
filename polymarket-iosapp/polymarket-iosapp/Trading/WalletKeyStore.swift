//
//  WalletKeyStore.swift
//  polymarket-iosapp
//
//  ウォレット秘密鍵の保存先。UserDefaults や JSON ファイルには絶対に保存しない。
//  Keychain に「この端末のみ・ロック解除中のみ」アクセス可能な属性で保存する。
//  （現時点では UI から未使用。売買機能の実装時に利用する）
//

import Foundation
import Security

protocol WalletKeyStore {
    func hasKey() -> Bool
    func save(privateKey: String) throws
    func load() throws -> String?
    func delete() throws
}

nonisolated enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): "Keychain エラー (\(status))"
        }
    }
}

final class KeychainWalletKeyStore: WalletKeyStore {
    private let service = "kengo.shibata.polymarket-iosapp.wallet"
    private let account = "primary"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func hasKey() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = false
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func save(privateKey: String) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(privateKey.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
