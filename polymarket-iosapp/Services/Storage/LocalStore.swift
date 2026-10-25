//
//  LocalStore.swift
//  polymarket-iosapp
//
//  Application Support 配下に JSON ファイルとして保存する簡易ストレージ。
//  ※ 秘密鍵などの機密情報はここではなく Keychain に保存すること（Trading/WalletKeyStore.swift）。
//

import Foundation

nonisolated enum LocalStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appending(path: "PolymarketMonitor", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = directory.appending(path: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("LocalStore: failed to decode \(fileName): \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to fileName: String) {
        let url = directory.appending(path: fileName)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("LocalStore: failed to save \(fileName): \(error)")
        }
    }

    static func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
    }
}
