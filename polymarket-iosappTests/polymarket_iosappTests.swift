//
//  polymarket_iosappTests.swift
//  polymarket-iosappTests
//
//  Created by Kengo Shibata on 2026/10/25.
//

import Foundation
import Testing
@testable import polymarket_iosapp

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private let sampleEventJSON = #"""
{
  "id": "100",
  "title": "Bitcoin above $150k by December?",
  "slug": "bitcoin-150k-december",
  "volume24hr": 250000,
  "tags": [{"id": "21", "label": "Crypto", "slug": "crypto"}],
  "markets": [
    {
      "id": "12345",
      "question": "Will Bitcoin reach $150k by December 31?",
      "conditionId": "0xabc",
      "outcomes": "[\"Yes\", \"No\"]",
      "outcomePrices": "[\"0.62\", \"0.38\"]",
      "clobTokenIds": "[\"111\", \"222\"]",
      "volume": "150000.5",
      "volumeNum": 150000.5,
      "volume24hr": 12000,
      "liquidity": "8000",
      "oneHourPriceChange": 0.03,
      "active": true,
      "closed": false
    },
    {
      "id": "broken"
    },
    {
      "id": 999,
      "question": "Closed market",
      "outcomes": ["Yes", "No"],
      "outcomePrices": ["1", "0"],
      "active": true,
      "closed": true
    }
  ]
}
"""#

struct DecodingTests {
    @Test func decodesEventWithStringEncodedFields() throws {
        let event = try decode(PMEvent.self, sampleEventJSON)
        #expect(event.id == "100")
        #expect(event.tags.first?.slug == "crypto")
        #expect(event.markets.count == 3)

        let market = try #require(event.markets.first)
        #expect(market.outcomes == ["Yes", "No"])
        #expect(market.outcomePrices == [0.62, 0.38])
        #expect(market.clobTokenIds == ["111", "222"])
        #expect(market.volume == 150000.5)
        #expect(market.liquidity == 8000)
        #expect(market.yesPrice == 0.62)
        #expect(market.isTradable)

        #expect(event.markets[2].id == "999")
        #expect(!event.markets[2].isTradable)
    }

    @Test func settingsDecodeToleratesMissingKeys() throws {
        let settings = try decode(AppSettings.self, #"{"pollIntervalMinutes": 10, "conditions": [{"name": "Crypto"}]}"#)
        #expect(settings.pollIntervalMinutes == 10)
        #expect(settings.cooldownMinutes == AppSettings().cooldownMinutes)
        #expect(settings.conditions.first?.name == "Crypto")
        #expect(settings.conditions.first?.rules == AlertRules())
    }

    @Test func settingsRoundTrip() throws {
        var settings = AppSettings()
        var condition = WatchCondition(name: "Politics")
        condition.tags = [PMTag(id: "2", label: "Politics", slug: "politics")]
        condition.rules.windowMinutes = 15
        settings.conditions = [condition]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }
}

struct ConditionMatcherTests {
    @Test func filtersByKeywordVolumeAndClosedState() throws {
        let event = try decode(PMEvent.self, sampleEventJSON)

        var condition = WatchCondition(name: "BTC")
        condition.keywords = ["bitcoin"]
        #expect(ConditionMatcher.monitoredMarkets(in: [event], condition: condition).map(\.id) == ["12345"])

        condition.excludedKeywords = ["150k"]
        #expect(ConditionMatcher.monitoredMarkets(in: [event], condition: condition).isEmpty)

        condition.excludedKeywords = []
        condition.minVolume24h = 50_000
        #expect(ConditionMatcher.monitoredMarkets(in: [event], condition: condition).isEmpty)
    }
}

struct AnomalyDetectorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(minutesAgo: Double, price: Double, volume: Double) -> Snapshot {
        Snapshot(t: now.addingTimeInterval(-minutesAgo * 60), price: price, volume: volume)
    }

    @Test func detectsPriceMoveWithinWindow() {
        let detector = AnomalyDetector(rules: AlertRules())  // 60分, 5pt
        let history = [
            snapshot(minutesAgo: 55, price: 0.40, volume: 0),
            snapshot(minutesAgo: 30, price: 0.43, volume: 0),
            snapshot(minutesAgo: 5, price: 0.45, volume: 0),
        ]
        let current = snapshot(minutesAgo: 0, price: 0.48, volume: 0)
        let change = detector.windowPriceChange(history: history, current: current, fallback: nil)
        #expect(abs((change ?? 0) - 0.08) < 1e-9)
        #expect(detector.priceMove(change: change, currentPrice: 0.48)?.kind == .priceMove)
        #expect(detector.priceMove(change: 0.02, currentPrice: 0.48) == nil)
    }

    @Test func usesFallbackWhenHistoryIsShort() {
        let detector = AnomalyDetector(rules: AlertRules())
        let history = [snapshot(minutesAgo: 10, price: 0.40, volume: 0)]
        let current = snapshot(minutesAgo: 0, price: 0.60, volume: 0)
        #expect(detector.windowPriceChange(history: history, current: current, fallback: 0.01) == 0.01)
    }

    @Test func detectsVolumeSurge() {
        let detector = AnomalyDetector(rules: AlertRules())  // 3倍, 最低$1,000
        let history = [snapshot(minutesAgo: 60, price: 0.5, volume: 100_000)]
        // 24h出来高 $24,000 → 1時間平均 $1,000。直近1時間で $5,000 = 5倍
        let current = snapshot(minutesAgo: 0, price: 0.5, volume: 105_000)
        let detection = detector.volumeSurge(history: history, current: current, volume24h: 24_000)
        #expect(detection?.kind == .volumeSurge)
        #expect(abs((detection?.magnitude ?? 0) - 5) < 1e-9)

        let quiet = snapshot(minutesAgo: 0, price: 0.5, volume: 101_500)
        #expect(detector.volumeSurge(history: history, current: quiet, volume24h: 24_000) == nil)
    }

    @Test func ignoresStaleVolumeReference() {
        let detector = AnomalyDetector(rules: AlertRules())
        let history = [snapshot(minutesAgo: 600, price: 0.5, volume: 0)]
        let current = snapshot(minutesAgo: 0, price: 0.5, volume: 1_000_000)
        #expect(detector.volumeSurge(history: history, current: current, volume24h: 1_000) == nil)
    }

    @Test func detectsTraderSurge() throws {
        var rules = AlertRules()
        rules.traderSurgeEnabled = true
        rules.minRecentTraders = 10
        let detector = AnomalyDetector(rules: rules)

        let t = now.timeIntervalSince1970
        let recent = (0..<30).map { PMTrade(proxyWallet: "r\($0)", timestamp: t - Double($0 * 60)) }
        let older = (0..<5).map { PMTrade(proxyWallet: "o\($0)", timestamp: t - 3600 - Double($0 * 300) - 60) }
        let activity = try #require(TraderActivity.compute(
            trades: recent + older, window: 3600, now: now, truncated: false))
        #expect(activity.recentTraders == 30)
        #expect(activity.baselineTraders == 5)
        #expect(detector.traderSurge(activity)?.kind == .traderSurge)
    }

    @Test func traderActivityNeedsEnoughHistoryWhenTruncated() {
        let t = now.timeIntervalSince1970
        // 取得上限に達し、直近10分の約定しか取れていない
        let trades = (0..<10).map { PMTrade(proxyWallet: "w\($0)", timestamp: t - Double($0 * 60)) }
        #expect(TraderActivity.compute(trades: trades, window: 3600, now: now, truncated: true) == nil)
    }
}
