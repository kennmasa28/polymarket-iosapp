//
//  ConditionMatcher.swift
//  polymarket-iosapp
//
//  監視条件に一致するイベント/マーケットの取得と絞り込み。
//  モニター（バックグラウンド巡回）とトピックス画面の両方で使う。
//

import Foundation

/// 監視対象のマーケット（親イベントの情報付き）
nonisolated struct MonitoredMarket: Identifiable, Hashable, Sendable {
    let market: PMMarket
    let eventId: String
    let eventTitle: String
    let eventSlug: String?
    /// 検知ウィンドウ内の価格変化（表示用）
    var windowChange: Double?

    var id: String { market.id }
}

nonisolated enum ConditionMatcher {
    static func matches(market: PMMarket, event: PMEvent, condition: WatchCondition) -> Bool {
        guard market.isTradable else { return false }
        if (market.volume24hr ?? 0) < condition.minVolume24h { return false }
        if (market.liquidity ?? 0) < condition.minLiquidity { return false }

        let text = [event.title, market.question, market.groupItemTitle ?? ""]
            .joined(separator: " ")
            .lowercased()
        let includes = normalized(condition.keywords)
        if !includes.isEmpty && !includes.contains(where: { text.contains($0) }) { return false }
        if normalized(condition.excludedKeywords).contains(where: { text.contains($0) }) { return false }
        return true
    }

    static func monitoredMarkets(in events: [PMEvent], condition: WatchCondition) -> [MonitoredMarket] {
        var seen = Set<String>()
        var result: [MonitoredMarket] = []
        for event in events {
            for market in event.markets where matches(market: market, event: event, condition: condition) {
                guard seen.insert(market.id).inserted else { continue }
                result.append(MonitoredMarket(
                    market: market, eventId: event.id, eventTitle: event.title, eventSlug: event.slug))
            }
        }
        return result
    }

    /// 一致するマーケットを1つ以上持つイベントだけを、一致マーケットに絞って返す
    static func filterEvents(_ events: [PMEvent], condition: WatchCondition) -> [PMEvent] {
        events.compactMap { event in
            var filtered = event
            filtered.markets = event.markets.filter { matches(market: $0, event: event, condition: condition) }
            return filtered.markets.isEmpty ? nil : filtered
        }
    }

    private static func normalized(_ keywords: [String]) -> [String] {
        keywords
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}

nonisolated struct EventFetcher: Sendable {
    let gamma: GammaAPI

    /// 条件のタグごとにイベントを取得して重複を除く。`cache` は同一巡回内でタグの重複取得を避けるため。
    func events(
        for condition: WatchCondition?,
        maxEventsPerTag: Int,
        cache: inout [String: [PMEvent]]
    ) async throws -> [PMEvent] {
        let tagIds: [String?] = {
            guard let condition, !condition.tags.isEmpty else { return [nil] }
            return condition.tags.map { Optional($0.id) }
        }()

        var seen = Set<String>()
        var result: [PMEvent] = []
        for tagId in tagIds {
            let key = "\(tagId ?? "*"):\(maxEventsPerTag)"
            let events: [PMEvent]
            if let cached = cache[key] {
                events = cached
            } else {
                events = try await gamma.allEvents(tagId: tagId, maxCount: maxEventsPerTag)
                cache[key] = events
            }
            for event in events where seen.insert(event.id).inserted {
                result.append(event)
            }
        }
        return result
    }
}
