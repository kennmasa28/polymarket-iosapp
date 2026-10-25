//
//  MarketMonitor.swift
//  polymarket-iosapp
//
//  有効な監視条件に一致するマーケットを全件取得し、スナップショット履歴と比較して
//  急変（価格・出来高・参加者）を検知して通知する。
//  フォアグラウンドでは一定間隔、バックグラウンドでは BGAppRefreshTask から呼ばれる。
//

import Foundation
import Observation

nonisolated enum MonitorTrigger: String, Sendable {
    case manual, foreground, background
}

@Observable
final class MarketMonitor {
    private(set) var isRunning = false
    private(set) var lastRunAt: Date?
    private(set) var lastSummary: String?
    private(set) var lastErrors: [String] = []
    /// 条件 ID → 一致マーケット
    private(set) var marketsByCondition: [UUID: [MonitoredMarket]] = [:]

    private let services: AppServices
    private let settings: SettingsStore
    private let snapshots: SnapshotStore
    private let alerts: AlertStore

    init(services: AppServices, settings: SettingsStore, snapshots: SnapshotStore, alerts: AlertStore) {
        self.services = services
        self.settings = settings
        self.snapshots = snapshots
        self.alerts = alerts
    }

    private struct Candidate {
        let item: MonitoredMarket
        let condition: WatchCondition
    }

    func runCycle(trigger: MonitorTrigger) async {
        guard !isRunning else { return }
        let config = settings.value
        let conditions = config.conditions.filter(\.isEnabled)
        guard !conditions.isEmpty else {
            marketsByCondition = [:]
            lastSummary = "有効な監視条件がありません"
            return
        }

        isRunning = true
        defer { isRunning = false }

        let now = Date()
        let fetcher = EventFetcher(gamma: services.gamma)
        var cache: [String: [PMEvent]] = [:]
        var results: [UUID: [MonitoredMarket]] = [:]
        var latest: [String: Snapshot] = [:]
        var pending: [AlertRecord] = []
        var traderCandidates: [Candidate] = []
        var errors: [String] = []

        for condition in conditions {
            do {
                let events = try await fetcher.events(
                    for: condition, maxEventsPerTag: config.maxEventsPerCondition, cache: &cache)
                let detector = AnomalyDetector(rules: condition.rules)
                var items = ConditionMatcher.monitoredMarkets(in: events, condition: condition)

                for index in items.indices {
                    let market = items[index].market
                    let current = Snapshot(t: now, price: market.yesPrice, volume: market.volume ?? 0)
                    let history = snapshots.history(for: market.id)
                    latest[market.id] = current

                    let change = detector.windowPriceChange(
                        history: history, current: current,
                        fallback: condition.rules.fallbackPriceChange(for: market))
                    items[index].windowChange = change

                    let detections = [
                        detector.priceMove(change: change, currentPrice: market.yesPrice),
                        detector.volumeSurge(history: history, current: current, volume24h: market.volume24hr),
                    ].compactMap { $0 }
                    pending += detections.map { makeRecord($0, item: items[index], condition: condition, now: now) }

                    if condition.rules.traderSurgeEnabled, market.conditionId != nil {
                        traderCandidates.append(Candidate(item: items[index], condition: condition))
                    }
                }
                results[condition.id] = items
            } catch {
                if error.isCancellation { return }
                errors.append("\(condition.name): \(error.localizedDescription)")
                // 取得に失敗した条件は前回の結果を表示し続ける
                results[condition.id] = marketsByCondition[condition.id]
            }
        }

        pending += await detectTraderSurges(
            traderCandidates, limit: config.maxTraderChecksPerCycle, now: now)

        snapshots.record(latest, now: now)
        marketsByCondition = results
        lastRunAt = now
        lastErrors = errors

        let fired = alerts.register(pending, cooldownMinutes: config.cooldownMinutes, now: now)
        if config.notificationsEnabled && !fired.isEmpty {
            await NotificationService.deliver(fired)
        }
        lastSummary = "\(latest.count)件を監視・新規アラート\(fired.count)件"
    }

    /// 出来高上位から順に Data API で約定を取得し、ユニーク取引者数の急増を判定する
    private func detectTraderSurges(_ candidates: [Candidate], limit: Int, now: Date) async -> [AlertRecord] {
        var seen = Set<String>()
        let targets = candidates
            .sorted { ($0.item.market.volume24hr ?? 0) > ($1.item.market.volume24hr ?? 0) }
            .filter { seen.insert($0.item.id).inserted }
            .prefix(limit)

        var records: [AlertRecord] = []
        for target in targets {
            guard let conditionId = target.item.market.conditionId else { continue }
            do {
                let trades = try await services.data.trades(conditionId: conditionId)
                guard let activity = TraderActivity.compute(
                    trades: trades, window: target.condition.rules.window, now: now,
                    truncated: trades.count >= DataAPI.maxTradesPerRequest)
                else { continue }
                if let detection = AnomalyDetector(rules: target.condition.rules).traderSurge(activity) {
                    records.append(makeRecord(detection, item: target.item, condition: target.condition, now: now))
                }
            } catch {
                if error.isCancellation { break }
                continue
            }
        }
        return records
    }

    private func makeRecord(_ detection: Detection, item: MonitoredMarket, condition: WatchCondition, now: Date) -> AlertRecord {
        AlertRecord(
            date: now,
            kind: detection.kind,
            marketId: item.market.id,
            question: item.market.question,
            eventTitle: item.eventTitle,
            eventSlug: item.eventSlug,
            conditionName: condition.name,
            summary: detection.summary,
            price: item.market.yesPrice)
    }
}
