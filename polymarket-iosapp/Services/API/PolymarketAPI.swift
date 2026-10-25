//
//  PolymarketAPI.swift
//  polymarket-iosapp
//
//  読み取り系は認証不要の公開 API のみを使う。
//  - Gamma API: イベント/マーケット/タグ/検索のメタデータ
//  - CLOB API : 価格履歴（将来はここに認証付きの発注 API を追加する）
//  - Data API : 約定履歴（参加者数の推定に使用）
//

import Foundation

// MARK: - Gamma

nonisolated struct EventQuery: Sendable {
    var tagId: String?
    var limit = 100
    var offset = 0
    var order = "volume24hr"
    var ascending = false
}

nonisolated struct GammaAPI: Sendable {
    static let baseURL = URL(string: "https://gamma-api.polymarket.com")!
    var http = HTTPClient()

    /// アクティブなイベント一覧（マーケットを含む）
    func events(_ query: EventQuery) async throws -> [PMEvent] {
        var items: [URLQueryItem] = [
            .init(name: "active", value: "true"),
            .init(name: "closed", value: "false"),
            .init(name: "archived", value: "false"),
            .init(name: "limit", value: String(query.limit)),
            .init(name: "offset", value: String(query.offset)),
            .init(name: "order", value: query.order),
            .init(name: "ascending", value: query.ascending ? "true" : "false"),
        ]
        if let tagId = query.tagId {
            items.append(.init(name: "tag_id", value: tagId))
        }
        let result: [Lossy<PMEvent>] = try await http.get(Self.baseURL, path: "events", query: items)
        return result.compactMap(\.value)
    }

    /// ページングして最大 `maxCount` 件のイベントを取得
    func allEvents(tagId: String?, maxCount: Int, pageSize: Int = 100) async throws -> [PMEvent] {
        var all: [PMEvent] = []
        var offset = 0
        while all.count < maxCount {
            let limit = min(pageSize, maxCount - all.count)
            let page = try await events(EventQuery(tagId: tagId, limit: limit, offset: offset))
            all.append(contentsOf: page)
            if page.count < limit { break }
            offset += page.count
        }
        return all
    }

    func market(id: String) async throws -> PMMarket {
        try await http.get(Self.baseURL, path: "markets/\(id)")
    }

    func tags(limit: Int = 500, offset: Int = 0) async throws -> [PMTag] {
        let result: [Lossy<PMTag>] = try await http.get(
            Self.baseURL, path: "tags",
            query: [.init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))])
        return result.compactMap(\.value)
    }

    func allTags(maxCount: Int = 3000) async throws -> [PMTag] {
        var all: [PMTag] = []
        let pageSize = 500
        while all.count < maxCount {
            let page = try await tags(limit: pageSize, offset: all.count)
            all.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        return all
    }

    func search(_ text: String) async throws -> PMSearchResult {
        try await http.get(
            Self.baseURL, path: "public-search",
            query: [
                .init(name: "q", value: text),
                .init(name: "limit_per_type", value: "20"),
                .init(name: "events_status", value: "active"),
            ])
    }
}

// MARK: - CLOB

nonisolated struct ClobAPI: Sendable {
    static let baseURL = URL(string: "https://clob.polymarket.com")!
    var http = HTTPClient()

    func priceHistory(tokenId: String, interval: PriceInterval) async throws -> [PricePoint] {
        let response: PriceHistoryResponse = try await http.get(
            Self.baseURL, path: "prices-history",
            query: [
                .init(name: "market", value: tokenId),
                .init(name: "interval", value: interval.rawValue),
                .init(name: "fidelity", value: String(interval.fidelity)),
            ])
        return response.history
    }
}

// MARK: - Data API

nonisolated struct DataAPI: Sendable {
    static let baseURL = URL(string: "https://data-api.polymarket.com")!
    static let maxTradesPerRequest = 500
    var http = HTTPClient()

    /// 指定マーケットの直近の約定（新しい順）
    func trades(conditionId: String, limit: Int = DataAPI.maxTradesPerRequest) async throws -> [PMTrade] {
        let result: [Lossy<PMTrade>] = try await http.get(
            Self.baseURL, path: "trades",
            query: [
                .init(name: "market", value: conditionId),
                .init(name: "limit", value: String(limit)),
            ])
        return result.compactMap(\.value)
    }
}
