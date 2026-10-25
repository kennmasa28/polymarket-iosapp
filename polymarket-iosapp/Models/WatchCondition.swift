//
//  WatchCondition.swift
//  polymarket-iosapp
//
//  ユーザーが UI から設定する監視条件とアプリ設定。ローカルに JSON で保存する。
//  将来フィールドを追加しても既存の保存データを読めるよう、
//  デコードは全項目 decodeIfPresent + デフォルト値で行う。
//

import Foundation

/// 急変検知のルール
nonisolated struct AlertRules: Codable, Hashable, Sendable {
    /// 検知ウィンドウ（分）。全ルール共通
    var windowMinutes = 60

    var priceChangeEnabled = true
    /// 確率ポイントの絶対値（0.05 = 5pt = 5¢）
    var priceChangeThreshold = 0.05

    var volumeSurgeEnabled = true
    /// ウィンドウ内出来高が 24h 平均ペースの何倍になったら通知するか
    var volumeSurgeMultiplier = 3.0
    /// これ未満のウィンドウ出来高（USD）は無視
    var minWindowVolume = 1_000.0

    var traderSurgeEnabled = false
    /// ウィンドウ内のユニーク取引者数が直前ウィンドウの何倍になったら通知するか
    var traderSurgeMultiplier = 3.0
    /// これ未満の取引者数は無視
    var minRecentTraders = 20

    static let windowChoices = [5, 15, 30, 60, 180, 360, 1440]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertRules()
        windowMinutes = (try? c.decodeIfPresent(Int.self, forKey: .windowMinutes)) ?? d.windowMinutes
        priceChangeEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .priceChangeEnabled)) ?? d.priceChangeEnabled
        priceChangeThreshold = (try? c.decodeIfPresent(Double.self, forKey: .priceChangeThreshold)) ?? d.priceChangeThreshold
        volumeSurgeEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .volumeSurgeEnabled)) ?? d.volumeSurgeEnabled
        volumeSurgeMultiplier = (try? c.decodeIfPresent(Double.self, forKey: .volumeSurgeMultiplier)) ?? d.volumeSurgeMultiplier
        minWindowVolume = (try? c.decodeIfPresent(Double.self, forKey: .minWindowVolume)) ?? d.minWindowVolume
        traderSurgeEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .traderSurgeEnabled)) ?? d.traderSurgeEnabled
        traderSurgeMultiplier = (try? c.decodeIfPresent(Double.self, forKey: .traderSurgeMultiplier)) ?? d.traderSurgeMultiplier
        minRecentTraders = (try? c.decodeIfPresent(Int.self, forKey: .minRecentTraders)) ?? d.minRecentTraders
    }

    var window: TimeInterval { TimeInterval(windowMinutes) * 60 }
    var windowLabel: String { Fmt.windowLabel(minutes: windowMinutes) }

    /// スナップショット履歴が足りないときに使う Gamma 提供の変化量
    func fallbackPriceChange(for market: PMMarket) -> Double? {
        switch windowMinutes {
        case 60: market.oneHourPriceChange
        case 1440: market.oneDayPriceChange
        default: nil
        }
    }
}

/// 監視条件（タグ・キーワード・閾値の組み合わせ）
nonisolated struct WatchCondition: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var isEnabled = true
    /// いずれかのタグに属するイベント（空なら出来高上位の全イベント）
    var tags: [PMTag] = []
    /// いずれかを含む（空なら制限なし）
    var keywords: [String] = []
    /// いずれかを含むものは除外
    var excludedKeywords: [String] = []
    var minVolume24h: Double = 0
    var minLiquidity: Double = 0
    var rules = AlertRules()

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "条件"
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        tags = (try? c.decodeIfPresent([PMTag].self, forKey: .tags)) ?? []
        keywords = (try? c.decodeIfPresent([String].self, forKey: .keywords)) ?? []
        excludedKeywords = (try? c.decodeIfPresent([String].self, forKey: .excludedKeywords)) ?? []
        minVolume24h = (try? c.decodeIfPresent(Double.self, forKey: .minVolume24h)) ?? 0
        minLiquidity = (try? c.decodeIfPresent(Double.self, forKey: .minLiquidity)) ?? 0
        rules = (try? c.decodeIfPresent(AlertRules.self, forKey: .rules)) ?? AlertRules()
    }

    var summary: String {
        var parts: [String] = []
        parts.append(tags.isEmpty ? "全カテゴリ" : tags.map(\.label).joined(separator: ", "))
        if !keywords.isEmpty { parts.append("「\(keywords.joined(separator: "/"))」") }
        if minVolume24h > 0 { parts.append("24h≥\(Fmt.usd(minVolume24h))") }
        return parts.joined(separator: " · ")
    }

    static var sample: WatchCondition {
        var condition = WatchCondition(name: "出来高上位")
        condition.minVolume24h = 50_000
        return condition
    }
}

/// アプリ全体の設定
nonisolated struct AppSettings: Codable, Hashable, Sendable {
    var conditions: [WatchCondition] = [.sample]
    var monitoringEnabled = true
    var notificationsEnabled = true
    /// フォアグラウンドでのポーリング間隔（分）。バックグラウンドは iOS が最短 15 分程度で調整する
    var pollIntervalMinutes = 5
    /// 同一マーケット・同一種別の再通知を抑制する時間（分）
    var cooldownMinutes = 60
    /// 1 条件あたりに取得するイベント数の上限（タグごと）
    var maxEventsPerCondition = 300
    /// 1 回の巡回で参加者数を調べるマーケット数の上限（Data API 呼び出し回数）
    var maxTraderChecksPerCycle = 25
    /// お気に入り（Apple Watch の文字盤に表示）
    var favorites: [FavoriteMarket] = []

    static let pollIntervalChoices = [1, 2, 5, 10, 15, 30, 60]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        conditions = (try? c.decodeIfPresent([WatchCondition].self, forKey: .conditions)) ?? d.conditions
        monitoringEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .monitoringEnabled)) ?? d.monitoringEnabled
        notificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? d.notificationsEnabled
        pollIntervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .pollIntervalMinutes)) ?? d.pollIntervalMinutes
        cooldownMinutes = (try? c.decodeIfPresent(Int.self, forKey: .cooldownMinutes)) ?? d.cooldownMinutes
        maxEventsPerCondition = (try? c.decodeIfPresent(Int.self, forKey: .maxEventsPerCondition)) ?? d.maxEventsPerCondition
        maxTraderChecksPerCycle = (try? c.decodeIfPresent(Int.self, forKey: .maxTraderChecksPerCycle)) ?? d.maxTraderChecksPerCycle
        favorites = (try? c.decodeIfPresent([FavoriteMarket].self, forKey: .favorites)) ?? d.favorites
    }
}
