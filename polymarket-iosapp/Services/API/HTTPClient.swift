//
//  HTTPClient.swift
//  polymarket-iosapp
//

import Foundation

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URLが不正です"
        case .badStatus(let code): "サーバーエラー (HTTP \(code))"
        case .decoding: "レスポンスの解析に失敗しました"
        }
    }
}

nonisolated struct HTTPClient: Sendable {
    var session: URLSession = .shared

    func get<T: Decodable>(
        _ baseURL: URL,
        path: String,
        query: [URLQueryItem] = [],
        as type: T.Type = T.self
    ) async throws -> T {
        guard var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

nonisolated extension Error {
    /// Task のキャンセル（SwiftUI の .task 再実行など）による失敗か
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
