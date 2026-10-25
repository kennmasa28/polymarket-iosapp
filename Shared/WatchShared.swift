//
//  WatchShared.swift
//  polymarket-iosapp / PolymarketWatch / PolymarketWatchWidget
//
//  iPhone アプリ・Watch アプリ・Watch ウィジェット（文字盤のコンプリケーション）で共有するコード。
//  iPhone のお気に入り → WatchConnectivity → Watch アプリが App Group に保存 → ウィジェットが読み出して表示。
//

import Foundation

nonisolated enum WatchShared {
    /// Watch アプリとウィジェット拡張で共有する App Group
    static let appGroup = "group.kengo.shibata.polymarket-iosapp"
    static let favoritesContextKey = "favorites"
    static let widgetKind = "MarketPriceComplication"
}

/// iPhone でお気に入り登録したマーケット
nonisolated struct FavoriteMarket: Codable, Hashable, Identifiable, Sendable {
    /// Gamma のマーケット ID
    let id: String
    /// 文字盤用の短い名前
    var title: String
    var question: String

    init(id: String, title: String, question: String) {
        self.id = id
        self.title = title
        self.question = question
    }

    /// 文字盤に収まるよう短くした名前
    static func shortTitle(from text: String, maxLength: Int = 22) -> String {
        var title = text
        for prefix in ["Will the ", "Will ", "Who will "] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
            break
        }
        if title.hasSuffix("?") { title.removeLast() }
        return title.count > maxLength ? String(title.prefix(maxLength - 1)) + "…" : title
    }
}

/// 文字盤に表示する価格
nonisolated struct MarketQuote: Codable, Hashable, Sendable {
    let marketId: String
    let title: String
    /// Yes 価格（0〜1）
    let price: Double
    /// 24時間の変化（確率ポイント）
    let dayChange: Double?
    let updatedAt: Date

    var percentText: String { String(format: "%.0f%%", price * 100) }

    var changeText: String {
        guard let dayChange else { return "" }
        let arrow = dayChange > 0.0005 ? "▲" : (dayChange < -0.0005 ? "▼" : "")
        return "\(arrow)\(String(format: "%.1f", abs(dayChange) * 100))"
    }

    static let placeholder = MarketQuote(
        marketId: "", title: "Bitcoin $150k", price: 0.62, dayChange: 0.031, updatedAt: .now)
}

/// App Group の UserDefaults に保存するストア
nonisolated enum SharedStore {
    private static let favoritesKey = "favorites"
    private static let quotesKey = "quotes"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WatchShared.appGroup) }

    static func favorites() -> [FavoriteMarket] {
        guard let data = defaults?.data(forKey: favoritesKey) else { return [] }
        return (try? JSONDecoder().decode([FavoriteMarket].self, from: data)) ?? []
    }

    static func saveFavorites(_ favorites: [FavoriteMarket]) {
        defaults?.set(try? JSONEncoder().encode(favorites), forKey: favoritesKey)
    }

    /// 通信できないときに表示する直近の価格
    static func cachedQuote(for marketId: String) -> MarketQuote? {
        guard let data = defaults?.data(forKey: quotesKey),
              let quotes = try? JSONDecoder().decode([String: MarketQuote].self, from: data)
        else { return nil }
        return quotes[marketId]
    }

    static func cacheQuotes(_ newQuotes: [MarketQuote]) {
        var quotes: [String: MarketQuote] = [:]
        if let data = defaults?.data(forKey: quotesKey),
           let saved = try? JSONDecoder().decode([String: MarketQuote].self, from: data) {
            quotes = saved
        }
        for quote in newQuotes { quotes[quote.marketId] = quote }
        defaults?.set(try? JSONEncoder().encode(quotes), forKey: quotesKey)
    }
}

private nonisolated struct GammaQuoteMarket: Decodable {
    let id: String
    let outcomePrices: [Double]
    let oneDayPriceChange: Double?

    enum CodingKeys: String, CodingKey { case id, outcomePrices, oneDayPriceChange }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try? c.decode(String.self, forKey: .id) {
            self.id = id
        } else {
            self.id = String(try c.decode(Int.self, forKey: .id))
        }
        // outcomePrices は "[\"0.62\", \"0.38\"]" のような JSON 文字列で返る
        if let raw = try? c.decode(String.self, forKey: .outcomePrices),
           let strings = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) {
            outcomePrices = strings.compactMap(Double.init)
        } else {
            outcomePrices = ((try? c.decode([String].self, forKey: .outcomePrices)) ?? []).compactMap(Double.init)
        }
        oneDayPriceChange = try? c.decode(Double.self, forKey: .oneDayPriceChange)
    }
}

/// 一部の要素がデコードできなくても配列全体を失敗させない
private nonisolated struct FailableQuoteMarket: Decodable {
    let value: GammaQuoteMarket?

    init(from decoder: Decoder) {
        value = try? GammaQuoteMarket(from: decoder)
    }
}

/// Gamma API から価格だけを取得する軽量クライアント（Watch 用）
nonisolated enum QuoteFetcher {
    static func quotes(for favorites: [FavoriteMarket]) async throws -> [MarketQuote] {
        guard !favorites.isEmpty,
              var components = URLComponents(string: "https://gamma-api.polymarket.com/markets")
        else { return [] }
        components.queryItems = favorites.map { URLQueryItem(name: "id", value: $0.id) }
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        let markets = try JSONDecoder().decode([FailableQuoteMarket].self, from: data).compactMap(\.value)
        let byId = Dictionary(markets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let now = Date()
        let quotes = favorites.compactMap { favorite -> MarketQuote? in
            guard let market = byId[favorite.id], let price = market.outcomePrices.first else { return nil }
            return MarketQuote(
                marketId: favorite.id, title: favorite.title, price: price,
                dayChange: market.oneDayPriceChange, updatedAt: now)
        }
        SharedStore.cacheQuotes(quotes)
        return quotes
    }
}
