//
//  AgentModels.swift
//  polymarket-iosapp
//
//  AI エージェントによる自動売買の設定・判断・ログ・ガードレール。
//  AI（OpenAI）は「買う／売る／キープ」と希望額を提案するだけで、
//  実際に発注するかどうか・金額・価格の上限はすべてここ（AgentGuardrails）で設定値に照らして決める。
//

import Foundation

nonisolated enum AgentMode: String, Codable, CaseIterable, Sendable {
    /// 判断と見積もりだけ行い、注文は出さない
    case paper
    /// 実際に注文を出す
    case live

    var label: String { self == .paper ? "シミュレーション" : "実取引" }
}

nonisolated struct AgentSettings: Codable, Hashable, Sendable {
    var enabled = false
    var mode: AgentMode = .paper
    /// OpenAI のモデル名
    var model = "gpt-5.6-luna"
    /// 強気度 0（慎重）〜 1（強気）
    var aggressiveness = 0.5
    /// 1 回の買い注文の上限（USDC）
    var maxTradeUSDC = 5.0
    /// 1 日（端末のローカル日付）の買い注文の合計上限（USDC）
    var dailyBudgetUSDC = 20.0
    /// この確信度未満の判断は実行しない
    var minConfidence = 0.65
    /// 買ってよい価格の範囲（確率 0〜1）
    var minBuyPrice = 0.05
    var maxBuyPrice = 0.90
    /// 現在価格から許容する約定価格のずれ（確率ポイント）
    var maxSlippage = 0.03
    var allowBuy = true
    var allowSell = true
    /// どの種類のアラートで判断させるか
    var triggerKinds: Set<AlertKind> = [.priceMove]
    /// 1 回の巡回で AI に判断させる最大件数（API 料金の上限）
    var maxEvaluationsPerCycle = 3
    /// 同じマーケットを再判断するまでの間隔（分）
    var marketCooldownMinutes = 120
    /// 追加の指示（投資方針など）
    var instructions = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AgentSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        mode = (try? c.decodeIfPresent(AgentMode.self, forKey: .mode)) ?? d.mode
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? d.model
        aggressiveness = (try? c.decodeIfPresent(Double.self, forKey: .aggressiveness)) ?? d.aggressiveness
        maxTradeUSDC = (try? c.decodeIfPresent(Double.self, forKey: .maxTradeUSDC)) ?? d.maxTradeUSDC
        dailyBudgetUSDC = (try? c.decodeIfPresent(Double.self, forKey: .dailyBudgetUSDC)) ?? d.dailyBudgetUSDC
        minConfidence = (try? c.decodeIfPresent(Double.self, forKey: .minConfidence)) ?? d.minConfidence
        minBuyPrice = (try? c.decodeIfPresent(Double.self, forKey: .minBuyPrice)) ?? d.minBuyPrice
        maxBuyPrice = (try? c.decodeIfPresent(Double.self, forKey: .maxBuyPrice)) ?? d.maxBuyPrice
        maxSlippage = (try? c.decodeIfPresent(Double.self, forKey: .maxSlippage)) ?? d.maxSlippage
        allowBuy = (try? c.decodeIfPresent(Bool.self, forKey: .allowBuy)) ?? d.allowBuy
        allowSell = (try? c.decodeIfPresent(Bool.self, forKey: .allowSell)) ?? d.allowSell
        triggerKinds = (try? c.decodeIfPresent(Set<AlertKind>.self, forKey: .triggerKinds)) ?? d.triggerKinds
        maxEvaluationsPerCycle = (try? c.decodeIfPresent(Int.self, forKey: .maxEvaluationsPerCycle)) ?? d.maxEvaluationsPerCycle
        marketCooldownMinutes = (try? c.decodeIfPresent(Int.self, forKey: .marketCooldownMinutes)) ?? d.marketCooldownMinutes
        instructions = (try? c.decodeIfPresent(String.self, forKey: .instructions)) ?? d.instructions
    }

    var aggressivenessLabel: String {
        switch aggressiveness {
        case ..<0.34: "慎重"
        case ..<0.67: "標準"
        default: "強気"
        }
    }
}

/// AI が返す判断（OpenAI の Structured Outputs で JSON スキーマを強制）
nonisolated struct AgentDecision: Codable, Equatable, Sendable {
    nonisolated enum Action: String, Codable, Sendable {
        case buy, sell, hold

        var label: String {
            switch self {
            case .buy: "購入"
            case .sell: "売却"
            case .hold: "キープ"
            }
        }
    }

    let action: Action
    /// 対象アウトカム（0 = 先頭、通常 Yes）
    let outcomeIndex: Int
    /// 0〜1
    let confidence: Double
    /// 購入時に使いたい USDC
    let amountUsdc: Double
    /// 売却時に保有株数の何割を売るか（0〜1）
    let sellFraction: Double
    /// 購入: 払ってよい最高価格 / 売却: 受け入れる最低価格（0〜1）
    let limitPrice: Double
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case action, confidence, reasoning
        case outcomeIndex = "outcome_index"
        case amountUsdc = "amount_usdc"
        case sellFraction = "sell_fraction"
        case limitPrice = "limit_price"
    }

    /// OpenAI に渡す JSON スキーマ（strict モード: 全項目必須・追加項目禁止）
    static var jsonSchema: [String: Any] {
        func field(_ type: String, _ description: String) -> [String: Any] {
            ["type": type, "description": description]
        }
        let properties: [String: Any] = [
            "action": ["type": "string", "enum": ["buy", "sell", "hold"]] as [String: Any],
            "outcome_index": field("integer", "対象アウトカムの番号（0 または 1）"),
            "confidence": field("number", "判断の確信度 0〜1"),
            "amount_usdc": field("number", "購入時に使う USDC（購入以外は 0）"),
            "sell_fraction": field("number", "売却時に保有株数の何割を売るか 0〜1（売却以外は 0）"),
            "limit_price": field("number", "購入: 払ってよい最高価格 / 売却: 受け入れる最低価格（0〜1）。キープは 0"),
            "reasoning": field("string", "判断理由（日本語で 2〜4 文）"),
        ]
        let required: [String] = [
            "action", "outcome_index", "confidence", "amount_usdc", "sell_fraction", "limit_price", "reasoning",
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": required,
            "properties": properties,
        ]
    }
}

/// 判断に使うマーケットの状態
nonisolated struct AgentMarketContext: Sendable {
    let marketId: String
    let question: String
    let outcomes: [String]
    let prices: [Double]
    let tokenIds: [String]
    /// トークン ID → 保有株数
    let heldShares: [String: Double]
    /// 取得できなければ nil（ロック中など）
    let balance: Double?
    /// 今日すでに使った買い注文の金額（USDC）
    let spentToday: Double
}

/// ガードレールを通した後の実行計画
nonisolated enum AgentPlan: Equatable, Sendable {
    case buy(outcomeIndex: Int, tokenId: String, usdc: Double, maxPrice: Double)
    case sell(outcomeIndex: Int, tokenId: String, shares: Double, minPrice: Double)
    case hold(reason: String)
}

nonisolated enum AgentGuardrails {
    /// 最小の買い注文額（USDC）
    static let minimumBuyUSDC = 1.0

    /// 価格は 0.0001 刻み（CLOB の最小ティック）にそろえる
    private static func roundPrice(_ price: Double) -> Double {
        (price * 10_000).rounded() / 10_000
    }

    /// AI の判断を設定値で検証・制限して、実行してよい計画にする。条件を満たさなければ hold
    static func plan(decision: AgentDecision, context: AgentMarketContext, settings: AgentSettings) -> AgentPlan {
        if decision.action == .hold { return .hold(reason: "AI の判断: キープ") }
        guard decision.confidence >= settings.minConfidence else {
            return .hold(reason: String(
                format: "確信度 %.0f%% が設定の下限 %.0f%% 未満", decision.confidence * 100, settings.minConfidence * 100))
        }
        let index = decision.outcomeIndex
        guard context.tokenIds.indices.contains(index), context.prices.indices.contains(index) else {
            return .hold(reason: "対象アウトカムが不正です")
        }
        let tokenId = context.tokenIds[index]
        let price = context.prices[index]

        switch decision.action {
        case .buy:
            guard settings.allowBuy else { return .hold(reason: "購入は設定で無効です") }
            guard price >= settings.minBuyPrice, price <= settings.maxBuyPrice else {
                return .hold(reason: String(
                    format: "現在価格 %.1f¢ が購入範囲 %.0f〜%.0f¢ の外", price * 100,
                    settings.minBuyPrice * 100, settings.maxBuyPrice * 100))
            }
            let remaining = max(settings.dailyBudgetUSDC - context.spentToday, 0)
            let cap = min(settings.maxTradeUSDC, remaining, context.balance ?? .infinity)
            let usdc = (min(decision.amountUsdc, cap) * 100).rounded(.down) / 100
            guard usdc >= minimumBuyUSDC else {
                return .hold(reason: String(format: "使える金額が不足（今日の残り予算 $%.2f）", remaining))
            }
            // 上限価格: AI の指定・設定の最高価格・現在価格＋許容ずれ のうち最も低いもの
            var maxPrice = min(settings.maxBuyPrice, price + settings.maxSlippage)
            if decision.limitPrice > 0 { maxPrice = min(maxPrice, decision.limitPrice) }
            guard maxPrice >= price else {
                return .hold(reason: String(format: "AI の上限価格 %.1f¢ が現在価格より低い", decision.limitPrice * 100))
            }
            return .buy(outcomeIndex: index, tokenId: tokenId, usdc: usdc, maxPrice: roundPrice(maxPrice))

        case .sell:
            guard settings.allowSell else { return .hold(reason: "売却は設定で無効です") }
            let held = context.heldShares[tokenId] ?? 0
            guard held >= 0.01 else { return .hold(reason: "このアウトカムを保有していません") }
            let fraction = min(max(decision.sellFraction, 0), 1)
            let shares = (held * fraction * 100).rounded(.down) / 100
            guard shares >= 0.01 else { return .hold(reason: "売却数量が 0 です") }
            var minPrice = max(price - settings.maxSlippage, 0.001)
            if decision.limitPrice > 0 { minPrice = max(minPrice, decision.limitPrice) }
            guard minPrice <= price else {
                return .hold(reason: String(format: "AI の下限価格 %.1f¢ が現在価格より高い", decision.limitPrice * 100))
            }
            return .sell(outcomeIndex: index, tokenId: tokenId, shares: shares, minPrice: roundPrice(minPrice))

        case .hold:
            return .hold(reason: "AI の判断: キープ")
        }
    }
}

nonisolated enum AgentExecutionStatus: String, Codable, Sendable {
    /// 実際に注文した
    case executed
    /// シミュレーション（見積もりのみ）
    case simulated
    /// キープ、またはガードレールで見送り
    case skipped
    /// 実取引モードだがウォレットがロック中で注文できなかった
    case pendingUnlock
    case failed

    var label: String {
        switch self {
        case .executed: "注文済み"
        case .simulated: "シミュレーション"
        case .skipped: "見送り"
        case .pendingUnlock: "ロック中で未実行"
        case .failed: "失敗"
        }
    }
}

nonisolated struct AgentLogEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var marketId: String
    var question: String
    var trigger: String
    var action: AgentDecision.Action
    var outcome: String?
    var confidence: Double
    var reasoning: String
    var status: AgentExecutionStatus
    var detail: String
    var mode: AgentMode
    /// 購入額または売却額（USDC）
    var usdc: Double?
    var shares: Double?
    var price: Double?
}
