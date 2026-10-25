//
//  LossyDecoding.swift
//  polymarket-iosapp
//
//  Polymarket の API は数値を文字列で返したり、配列を JSON 文字列として
//  埋め込んで返したりするため、それらを寛容にデコードするためのヘルパー。
//

import Foundation

/// 要素のデコードに失敗しても配列全体を失敗させないためのラッパー
nonisolated struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

nonisolated extension KeyedDecodingContainer {
    /// `"123"` / `123` / `123.4` のいずれも String として取り出す
    func decodeLossyString(forKey key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func requireLossyString(forKey key: Key) throws -> String {
        guard let value = decodeLossyString(forKey: key) else {
            throw DecodingError.keyNotFound(
                key, .init(codingPath: codingPath, debugDescription: "missing \(key.stringValue)"))
        }
        return value
    }

    /// `0.5` / `"0.5"` のどちらも Double として取り出す
    func decodeLossyDouble(forKey key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func decodeLossyBool(forKey key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Bool(s) }
        return nil
    }

    /// `["a","b"]` と `"[\"a\",\"b\"]"`（JSON 文字列埋め込み）の両方に対応
    func decodeEmbeddedStringArray(forKey key: Key) -> [String] {
        if let array = try? decodeIfPresent([String].self, forKey: key) { return array }
        if let raw = try? decodeIfPresent(String.self, forKey: key),
           let data = raw.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }
        return []
    }

    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        (try? decodeIfPresent([Lossy<T>].self, forKey: key))?.compactMap { $0.value } ?? []
    }
}

nonisolated enum DateParsing {
    /// Gamma API の日付文字列（ISO8601、小数秒あり/なし、日付のみ）をパース
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = try? Date(string, strategy: .iso8601) { return d }
        if let d = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return d
        }
        if let d = try? Date(string, strategy: Date.ISO8601FormatStyle().year().month().day()) {
            return d
        }
        return nil
    }
}
