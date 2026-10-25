//
//  AnomalyDetector.swift
//  polymarket-iosapp
//
//  スナップショット履歴と約定履歴から「急変」を判定する純粋ロジック。
//

import Foundation

nonisolated struct AnomalyDetector: Sendable {
    let rules: AlertRules

    private var window: TimeInterval { rules.window }

    // MARK: Price

    /// ウィンドウ内の過去スナップショットのうち、現在価格から最も大きく乖離したものとの差（現在 − 過去）。
    /// 履歴がウィンドウの半分に満たない場合は `fallback`（Gamma の oneHourPriceChange 等）を返す。
    func windowPriceChange(history: [Snapshot], current: Snapshot, fallback: Double?) -> Double? {
        guard let price = current.price else { return nil }
        // ポーリング間隔の揺らぎを考慮して少しだけ広めに取る
        let inWindow = history.filter { snapshot in
            let age = current.t.timeIntervalSince(snapshot.t)
            return age > 0 && age <= window * 1.25 && snapshot.price != nil
        }
        guard let oldest = inWindow.min(by: { $0.t < $1.t }),
              current.t.timeIntervalSince(oldest.t) >= window * 0.5
        else { return fallback }

        let deltas = inWindow.compactMap { snapshot in snapshot.price.map { price - $0 } }
        return deltas.max { abs($0) < abs($1) }
    }

    func priceMove(change: Double?, currentPrice: Double?) -> Detection? {
        guard rules.priceChangeEnabled, let change, abs(change) >= rules.priceChangeThreshold else {
            return nil
        }
        return Detection(
            kind: .priceMove,
            magnitude: change,
            summary: "\(rules.windowLabel)で \(Fmt.points(change))（現在 \(Fmt.percent(currentPrice))）")
    }

    // MARK: Volume

    /// ウィンドウ内の出来高が 24h 平均ペースの `volumeSurgeMultiplier` 倍以上か
    func volumeSurge(history: [Snapshot], current: Snapshot, volume24h: Double?) -> Detection? {
        guard rules.volumeSurgeEnabled else { return nil }
        // ウィンドウ長以上前のうち最新のスナップショットを基準にする
        guard let reference = history.last(where: { current.t.timeIntervalSince($0.t) >= window * 0.8 })
        else { return nil }
        let span = current.t.timeIntervalSince(reference.t)
        // 長時間巡回していなかった場合は基準が古すぎるので判定しない
        guard span > 0, span <= window * 3 else { return nil }

        let windowVolume = max(current.volume - reference.volume, 0) * window / span
        let baseline = max((volume24h ?? 0) * window / 86_400, 1)
        let ratio = windowVolume / baseline
        guard windowVolume >= rules.minWindowVolume, ratio >= rules.volumeSurgeMultiplier else { return nil }
        return Detection(
            kind: .volumeSurge,
            magnitude: ratio,
            summary: "\(rules.windowLabel)の出来高 \(Fmt.usd(windowVolume))（通常の\(String(format: "%.1f", ratio))倍）")
    }

    // MARK: Traders

    func traderSurge(_ activity: TraderActivity) -> Detection? {
        guard rules.traderSurgeEnabled else { return nil }
        let ratio = Double(activity.recentTraders) / max(activity.baselineTraders, 1)
        guard activity.recentTraders >= rules.minRecentTraders, ratio >= rules.traderSurgeMultiplier else {
            return nil
        }
        return Detection(
            kind: .traderSurge,
            magnitude: ratio,
            summary: "\(rules.windowLabel)で\(activity.recentTraders)人が取引（通常の\(String(format: "%.1f", ratio))倍）")
    }
}

/// 約定履歴から求めた「直近ウィンドウ」と「その前のウィンドウ」のユニーク取引者数
nonisolated struct TraderActivity: Equatable, Sendable {
    let recentTraders: Int
    /// 直前ウィンドウ相当に換算したユニーク取引者数
    let baselineTraders: Double

    /// - Parameter truncated: API の取得上限に達していて、古い約定が欠けている可能性があるか
    static func compute(trades: [PMTrade], window: TimeInterval, now: Date, truncated: Bool) -> TraderActivity? {
        let recentStart = now.addingTimeInterval(-window)
        let baselineStart = now.addingTimeInterval(-2 * window)

        let recent = Set(trades.filter { $0.date >= recentStart }.map(\.proxyWallet))
        let older = Set(trades.filter { $0.date < recentStart && $0.date >= baselineStart }.map(\.proxyWallet))

        var span = window
        if truncated, let oldest = trades.map(\.date).min(), oldest > baselineStart {
            // 直前ウィンドウの一部しか取得できていないので、取得できた区間から換算する
            span = recentStart.timeIntervalSince(oldest)
            guard span >= window * 0.25 else { return nil }
        }
        return TraderActivity(
            recentTraders: recent.count,
            baselineTraders: Double(older.count) * window / span)
    }
}
