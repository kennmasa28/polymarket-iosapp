//
//  WalletKeyStore.swift
//  polymarket-iosapp
//
//  ウォレット秘密鍵などの Keychain 保存。UserDefaults や JSON ファイルには絶対に保存しない。
//  秘密鍵は「この端末のみ・パスコード設定時のみ」かつ読み出しのたびに Face ID / パスコードを要求する。
//

import Foundation
import LocalAuthentication
import Security

nonisolated enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case accessControlUnavailable
    case passcodeNotSet
    case userCanceled

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): "Keychain エラー (\(status))"
        case .accessControlUnavailable: "Keychain のアクセス制御を作成できませんでした"
        case .passcodeNotSet: "秘密鍵を保護するため、端末にパスコードを設定してください"
        case .userCanceled: "認証がキャンセルされました"
        }
    }
}

nonisolated struct KeychainItem: Sendable {
    let service: String
    let account: String
    /// true なら読み出しのたびに Face ID / Touch ID / パスコードを要求する
    let requiresUserPresence: Bool

    static let privateKey = KeychainItem(
        service: "kengo.shibata.polymarket-iosapp.wallet", account: "privateKey", requiresUserPresence: true)
    static let clobCredentials = KeychainItem(
        service: "kengo.shibata.polymarket-iosapp.wallet", account: "clobCredentials", requiresUserPresence: false)

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ data: Data) throws {
        try delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        if requiresUserPresence {
            #if targetEnvironment(simulator)
            // シミュレータはパスコード/生体認証を前提にできないため保護レベルを下げる
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            #else
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil)
            else { throw KeychainError.accessControlUnavailable }
            query[kSecAttrAccessControl as String] = access
            #endif
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return
        case errSecAuthFailed, errSecNotAvailable: throw KeychainError.passcodeNotSet
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    /// `requiresUserPresence` の項目は認証 UI が出てブロックするため、メインスレッド外から呼ぶこと
    func load(reason: String? = nil) throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let reason {
            let context = LAContext()
            context.localizedReason = reason
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        case errSecUserCanceled: throw KeychainError.userCanceled
        default: throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
