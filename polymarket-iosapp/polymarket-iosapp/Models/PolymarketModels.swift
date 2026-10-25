//
//  PolymarketModels.swift
//  polymarket-iosapp
//
//  Gamma API / CLOB API / Data API のレスポンスモデル。
//  https://docs.polymarket.com/
//

import Foundation

// MARK: - Gamma: Tag

nonisolated struct PMTag: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let slug: String

    init(id: String, label: String, slug: String) {
        self.id = id
        self.label = label
        self.slug = slug
    }

    enum CodingKeys: String, CodingKey { case id, label, slug }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.requireLossyString(forKey: .id)
        let slug = c.decodeLossyString(forKey: .slug)
        let label = c.decodeLossyString(forKey: .label)
        self.label = label ?? slug ?? id
        self.slug = slug ?? (label ?? id).lowercased()
    }
}

// MARK: - Gamma: Market

/// Polymarket のマーケット（基本的に Yes/No の二択）
nonisolated struct PMMarket: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let question: String
    let conditionId: String?
    let slug: String?
    let groupItemTitle: String?
    let description: String?
    let image: String?
    let icon: String?
    let endDate: String?
    let outcomes: [String]
    let outcomePrices: [Double]
    /// outcomes と同じ順序の CLOB トークン ID（価格履歴・将来の発注で使用）
    let clobTokenIds: [String]
    let volume: Double?
    let volume24hr: Double?
    let liquidity: Double?
    let oneHourPriceChange: Double?
    let oneDayPriceChange: Double?
    let oneWeekPriceChange: Double?
    let lastTradePrice: Double?
    let bestBid: Double?
    let bestAsk: Double?
    let active: Bool
    let closed: Bool
    /// `/markets/{id}` のレスポンスに含まれる親イベント
    let events: [PMEventSummary]

    enum CodingKeys: String, CodingKey {
        case id, question, conditionId, slug, groupItemTitle, description, image, icon, endDate
        case outcomes, outcomePrices, clobTokenIds
        case volume, volumeNum, volume24hr, liquidity, liquidityNum
        case oneHourPriceChange, oneDayPriceChange, oneWeekPriceChange
        case lastTradePrice, bestBid, bestAsk, active, closed, events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.requireLossyString(forKey: .id)
        question = c.decodeLossyString(forKey: .question) ?? ""
        conditionId = c.decodeLossyString(forKey: .conditionId)
        slug = c.decodeLossyString(forKey: .slug)
        groupItemTitle = c.decodeLossyString(forKey: .groupItemTitle)
        description = c.decodeLossyString(forKey: .description)
        image = c.decodeLossyString(forKey: .image)
        icon = c.decodeLossyString(forKey: .icon)
        endDate = c.decodeLossyString(forKey: .endDate)
        outcomes = c.decodeEmbeddedStringArray(forKey: .outcomes)
        outcomePrices = c.decodeEmbeddedStringArray(forKey: .outcomePrices).compactMap(Double.init)
        clobTokenIds = c.decodeEmbeddedStringArray(forKey: .clobTokenIds)
        volume = c.decodeLossyDouble(forKey: .volumeNum) ?? c.decodeLossyDouble(forKey: .volume)
        volume24hr = c.decodeLossyDouble(forKey: .volume24hr)
        liquidity = c.decodeLossyDouble(forKey: .liquidityNum) ?? c.decodeLossyDouble(forKey: .liquidity)
        oneHourPriceChange = c.decodeLossyDouble(forKey: .oneHourPriceChange)
        oneDayPriceChange = c.decodeLossyDouble(forKey: .oneDayPriceChange)
        oneWeekPriceChange = c.decodeLossyDouble(forKey: .oneWeekPriceChange)
        lastTradePrice = c.decodeLossyDouble(forKey: .lastTradePrice)
        bestBid = c.decodeLossyDouble(forKey: .bestBid)
        bestAsk = c.decodeLossyDouble(forKey: .bestAsk)
        active = c.decodeLossyBool(forKey: .active) ?? true
        closed = c.decodeLossyBool(forKey: .closed) ?? false
        events = c.decodeLossyArray(PMEventSummary.self, forKey: .events)
    }

    static func == (lhs: PMMarket, rhs: PMMarket) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// 先頭アウトカム（通常 "Yes"）の価格 = 市場の示す確率
    var yesPrice: Double? { outcomePrices.first ?? lastTradePrice }

    var displayName: String {
        if let title = groupItemTitle, !title.isEmpty { return title }
        return question
    }

    var endDateValue: Date? { DateParsing.parse(endDate) }

    var isTradable: Bool { active && !closed }
}

nonisolated struct PMEventSummary: Decodable, Hashable, Sendable {
    let id: String
    let title: String
    let slug: String?

    enum CodingKeys: String, CodingKey { case id, title, slug }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.requireLossyString(forKey: .id)
        title = c.decodeLossyString(forKey: .title) ?? ""
        slug = c.decodeLossyString(forKey: .slug)
    }
}

// MARK: - Gamma: Event

/// 1つ以上のマーケットをまとめたイベント（例: 「2028年米大統領選」）
nonisolated struct PMEvent: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let slug: String?
    let description: String?
    let image: String?
    let icon: String?
    let endDate: String?
    let volume: Double?
    let volume24hr: Double?
    let liquidity: Double?
    let commentCount: Int?
    let tags: [PMTag]
    var markets: [PMMarket]

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, image, icon, endDate
        case volume, volume24hr, liquidity, commentCount, tags, markets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.requireLossyString(forKey: .id)
        title = c.decodeLossyString(forKey: .title) ?? ""
        slug = c.decodeLossyString(forKey: .slug)
        description = c.decodeLossyString(forKey: .description)
        image = c.decodeLossyString(forKey: .image)
        icon = c.decodeLossyString(forKey: .icon)
        endDate = c.decodeLossyString(forKey: .endDate)
        volume = c.decodeLossyDouble(forKey: .volume)
        volume24hr = c.decodeLossyDouble(forKey: .volume24hr)
        liquidity = c.decodeLossyDouble(forKey: .liquidity)
        commentCount = c.decodeLossyDouble(forKey: .commentCount).map { Int($0) }
        tags = c.decodeLossyArray(PMTag.self, forKey: .tags)
        markets = c.decodeLossyArray(PMMarket.self, forKey: .markets)
    }

    static func == (lhs: PMEvent, rhs: PMEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var tradableMarkets: [PMMarket] { markets.filter(\.isTradable) }

    /// 一覧に代表として表示するマーケット（最も確率の高いもの）
    var leadingMarket: PMMarket? {
        let candidates = tradableMarkets.isEmpty ? markets : tradableMarkets
        if candidates.count <= 1 { return candidates.first }
        return candidates.max { ($0.yesPrice ?? 0) < ($1.yesPrice ?? 0) }
    }

    var endDateValue: Date? { DateParsing.parse(endDate) }

    var webURL: URL? {
        guard let slug else { return nil }
        return URL(string: "https://polymarket.com/event/\(slug)")
    }
}

// MARK: - Gamma: Search

nonisolated struct PMSearchResult: Decodable, Sendable {
    let events: [PMEvent]
    let tags: [PMTag]

    enum CodingKeys: String, CodingKey { case events, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = c.decodeLossyArray(PMEvent.self, forKey: .events)
        tags = c.decodeLossyArray(PMTag.self, forKey: .tags)
    }
}

// MARK: - CLOB: Price history

nonisolated struct PricePoint: Decodable, Identifiable, Hashable, Sendable {
    /// UNIX 秒
    let t: Double
    let p: Double

    var id: Double { t }
    var date: Date { Date(timeIntervalSince1970: t) }
}

nonisolated struct PriceHistoryResponse: Decodable, Sendable {
    let history: [PricePoint]
}

nonisolated enum PriceInterval: String, CaseIterable, Identifiable, Sendable {
    case hour = "1h"
    case sixHours = "6h"
    case day = "1d"
    case week = "1w"
    case month = "1m"
    case max = "max"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: "1H"
        case .sixHours: "6H"
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .max: "ALL"
        }
    }

    /// データ点の間隔（分）
    var fidelity: Int {
        switch self {
        case .hour: 1
        case .sixHours: 5
        case .day: 15
        case .week: 60
        case .month: 180
        case .max: 720
        }
    }
}

// MARK: - Data API: Trades

nonisolated struct PMTrade: Decodable, Sendable {
    let proxyWallet: String
    let side: String?
    let size: Double?
    let price: Double?
    /// UNIX 秒
    let timestamp: Double

    enum CodingKeys: String, CodingKey { case proxyWallet, side, size, price, timestamp }

    init(proxyWallet: String, timestamp: Double, side: String? = nil, size: Double? = nil, price: Double? = nil) {
        self.proxyWallet = proxyWallet
        self.timestamp = timestamp
        self.side = side
        self.size = size
        self.price = price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxyWallet = try c.requireLossyString(forKey: .proxyWallet)
        side = c.decodeLossyString(forKey: .side)
        size = c.decodeLossyDouble(forKey: .size)
        price = c.decodeLossyDouble(forKey: .price)
        timestamp = c.decodeLossyDouble(forKey: .timestamp) ?? 0
    }

    var date: Date { Date(timeIntervalSince1970: timestamp) }
}
