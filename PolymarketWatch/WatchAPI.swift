//
//  WatchAPI.swift
//  PolymarketWatch
//
//  Watch アプリ用の軽量な Polymarket API クライアント（Gamma: マーケット/イベント、CLOB: 価格履歴）。
//

import Foundation

// MARK: - Lossy decoding（iPhone 側のヘルパーと名前が衝突しないよう fileprivate）

fileprivate extension KeyedDecodingContainer {
    func watchString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }

    func watchDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    /// `["a"]` と `"[\"a\"]"`（JSON 文字列埋め込み）の両方に対応
    func watchStrings(_ key: Key) -> [String] {
        if let array = try? decodeIfPresent([String].self, forKey: key) { return array }
        if let raw = try? decodeIfPresent(String.self, forKey: key),
           let array = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) {
            return array
        }
        return []
    }
}

private struct WatchFailable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) { value = try? T(from: decoder) }
}

// MARK: - Models

/// 詳細画面に出すマーケット情報（Gamma `/markets/{id}`）
struct WatchMarketDetail: Decodable, Sendable {
    let id: String
    let question: String
    let groupItemTitle: String?
    let eventTitle: String?
    let imageURL: String?
    let outcomes: [String]
    let prices: [Double]
    let tokenIds: [String]
    let oneHourChange: Double?
    let oneDayChange: Double?
    let oneWeekChange: Double?
    let volume24h: Double?
    let volume: Double?
    let liquidity: Double?
    let endDate: Date?
    let rules: String?

    private enum CodingKeys: String, CodingKey {
        case id, question, groupItemTitle, image, icon, outcomes, outcomePrices, clobTokenIds
        case oneHourPriceChange, oneDayPriceChange, oneWeekPriceChange
        case volume24hr, volumeNum, volume, liquidityNum, liquidity, endDate, description, events
    }

    private struct EventSummary: Decodable {
        let title: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.watchString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "id"))
        }
        self.id = id
        question = c.watchString(.question) ?? ""
        groupItemTitle = c.watchString(.groupItemTitle).flatMap { $0.isEmpty ? nil : $0 }
        let events = (try? c.decodeIfPresent([EventSummary].self, forKey: .events)) ?? []
        eventTitle = events.first?.title
        imageURL = c.watchString(.icon) ?? c.watchString(.image)
        outcomes = c.watchStrings(.outcomes)
        prices = c.watchStrings(.outcomePrices).compactMap(Double.init)
        tokenIds = c.watchStrings(.clobTokenIds)
        oneHourChange = c.watchDouble(.oneHourPriceChange)
        oneDayChange = c.watchDouble(.oneDayPriceChange)
        oneWeekChange = c.watchDouble(.oneWeekPriceChange)
        volume24h = c.watchDouble(.volume24hr)
        volume = c.watchDouble(.volumeNum) ?? c.watchDouble(.volume)
        liquidity = c.watchDouble(.liquidityNum) ?? c.watchDouble(.liquidity)
        endDate = c.watchString(.endDate).flatMap { try? Date($0, strategy: .iso8601) }
        rules = c.watchString(.description)
    }

    /// 複数マーケットのイベントでは選択肢名（例: "↑ $150,000"）、単独なら質問文
    var displayName: String { groupItemTitle ?? question }
}

struct WatchPricePoint: Decodable, Identifiable, Sendable {
    let t: Double
    let p: Double
    var id: Double { t }
    var date: Date { Date(timeIntervalSince1970: t) }
}

private struct WatchPriceHistory: Decodable {
    let history: [WatchPricePoint]
}

enum WatchChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1d"
    case week = "1w"
    case month = "1m"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: "1日"
        case .week: "1週"
        case .month: "1月"
        }
    }
    /// データ点の間隔（分）。Watch では点を少なめにする
    var fidelity: Int {
        switch self {
        case .day: 30
        case .week: 180
        case .month: 720
        }
    }
}

/// トレンド一覧の 1 行（Gamma `/events` の代表マーケット）
struct WatchTrendingItem: Identifiable, Sendable {
    let id: String
    let marketId: String
    let eventTitle: String
    let marketTitle: String?
    let imageURL: String?
    let price: Double?
    let dayChange: Double?
    let volume24h: Double?
}

/// トレンド用のマーケット（Gamma `/markets`）。イベント配下の全マーケットを含む `/events` より
/// レスポンスがずっと小さいので、メモリの少ない Watch ではこちらを使う
private struct WatchTrendMarket: Decodable {
    let id: String
    let question: String
    let groupItemTitle: String?
    let eventTitle: String?
    let imageURL: String?
    let price: Double?
    let dayChange: Double?
    let volume24h: Double?

    private enum CodingKeys: String, CodingKey {
        case id, question, groupItemTitle, outcomePrices, oneDayPriceChange, icon, image, volume24hr, events
    }

    private struct EventSummary: Decodable {
        let title: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.watchString(.id) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "id"))
        }
        self.id = id
        question = c.watchString(.question) ?? ""
        groupItemTitle = c.watchString(.groupItemTitle).flatMap { $0.isEmpty ? nil : $0 }
        eventTitle = ((try? c.decodeIfPresent([WatchFailable<EventSummary>].self, forKey: .events)) ?? [])
            .compactMap(\.value).first?.title
        imageURL = c.watchString(.icon) ?? c.watchString(.image)
        price = c.watchStrings(.outcomePrices).compactMap(Double.init).first
        dayChange = c.watchDouble(.oneDayPriceChange)
        volume24h = c.watchDouble(.volume24hr)
    }
}

// MARK: - Client

enum WatchAPI {
    private static let gamma = URL(string: "https://gamma-api.polymarket.com")!
    private static let clob = URL(string: "https://clob.polymarket.com")!

    private static func get<T: Decodable>(_ base: URL, _ path: String, _ query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func market(id: String) async throws -> WatchMarketDetail {
        try await get(gamma, "markets/\(id)", [])
    }

    static func priceHistory(tokenId: String, range: WatchChartRange) async throws -> [WatchPricePoint] {
        let response: WatchPriceHistory = try await get(clob, "prices-history", [
            URLQueryItem(name: "market", value: tokenId),
            URLQueryItem(name: "interval", value: range.rawValue),
            URLQueryItem(name: "fidelity", value: String(range.fidelity)),
        ])
        return response.history
    }

    /// 24h 出来高上位のマーケット。同じイベントのマーケットは出来高が最大のもの 1 件にまとめる
    static func trending(limit: Int = 12) async throws -> [WatchTrendingItem] {
        let markets: [WatchFailable<WatchTrendMarket>] = try await get(gamma, "markets", [
            URLQueryItem(name: "active", value: "true"),
            URLQueryItem(name: "closed", value: "false"),
            URLQueryItem(name: "order", value: "volume24hr"),
            URLQueryItem(name: "ascending", value: "false"),
            URLQueryItem(name: "limit", value: String(limit * 2)),
        ])
        var seenEvents = Set<String>()
        var items: [WatchTrendingItem] = []
        for market in markets.compactMap(\.value) {
            let eventTitle = market.eventTitle ?? market.question
            guard seenEvents.insert(eventTitle).inserted else { continue }
            items.append(WatchTrendingItem(
                id: market.id, marketId: market.id, eventTitle: eventTitle,
                marketTitle: eventTitle == market.question ? nil : (market.groupItemTitle ?? market.question),
                imageURL: market.imageURL, price: market.price, dayChange: market.dayChange,
                volume24h: market.volume24h))
            if items.count >= limit { break }
        }
        return items
    }
}
