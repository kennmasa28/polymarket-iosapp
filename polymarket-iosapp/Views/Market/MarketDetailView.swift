//
//  MarketDetailView.swift
//  polymarket-iosapp
//

import Charts
import SwiftUI

struct MarketDetailView: View {
    let market: PMMarket
    let eventTitle: String?
    let eventSlug: String?

    @Environment(AppServices.self) private var services
    @State private var interval: PriceInterval = .day
    @State private var history: [PricePoint] = []
    @State private var historyError: String?
    @State private var isLoadingHistory = false

    var body: some View {
        List {
            Section { header }

            Section("価格推移（\(market.outcomes.first ?? "Yes")）") {
                Picker("期間", selection: $interval) {
                    ForEach(PriceInterval.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                chart
            }

            Section("統計") {
                LabeledContent("24h 出来高", value: Fmt.usd(market.volume24hr))
                LabeledContent("累計出来高", value: Fmt.usd(market.volume))
                LabeledContent("流動性", value: Fmt.usd(market.liquidity))
                LabeledContent("1時間の変化") { ChangeBadge(change: market.oneHourPriceChange) }
                LabeledContent("24時間の変化") { ChangeBadge(change: market.oneDayPriceChange) }
                LabeledContent("1週間の変化") { ChangeBadge(change: market.oneWeekPriceChange) }
                LabeledContent("Bid / Ask", value: "\(Fmt.cents(market.bestBid)) / \(Fmt.cents(market.bestAsk))")
                if let end = market.endDateValue {
                    LabeledContent("終了予定", value: end.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section("取引") {
                TradePanel(market: market)
            }

            if let description = market.description, !description.isEmpty {
                Section("解決ルール") {
                    Text(description).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if let url = webURL {
                Section {
                    Link(destination: url) { Label("Polymarketで開く", systemImage: "safari") }
                }
            }
        }
        .navigationTitle(market.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: interval) { await loadHistory() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(urlString: market.image ?? market.icon, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    if let eventTitle, eventTitle != market.question {
                        Text(eventTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(market.question).font(.headline)
                }
            }
            HStack(spacing: 16) {
                ForEach(Array(zip(market.outcomes, market.outcomePrices).enumerated()), id: \.offset) { index, pair in
                    VStack(alignment: .leading) {
                        Text(pair.0).font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.percent(pair.1))
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(index == 0 ? Color.green : Color.red)
                    }
                }
                if !market.isTradable {
                    Text("終了").font(.caption).padding(4).background(.secondary.opacity(0.2), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if let historyError {
            Text(historyError).font(.footnote).foregroundStyle(.secondary)
        } else if history.isEmpty {
            HStack {
                Spacer()
                if isLoadingHistory { ProgressView() } else { Text("データがありません").foregroundStyle(.secondary) }
                Spacer()
            }
            .frame(height: 200)
        } else {
            Chart(history) { point in
                LineMark(x: .value("時刻", point.date), y: .value("価格", point.p))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("時刻", point.date), yStart: .value("下限", yDomain.lowerBound), yEnd: .value("価格", point.p))
                    .foregroundStyle(.linearGradient(
                        colors: [Color.accentColor.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let price = value.as(Double.self) { Text(Fmt.percent(price)) }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let prices = history.map(\.p)
        guard let low = prices.min(), let high = prices.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, 0.02)
        return max(low - padding, 0)...min(high + padding, 1)
    }

    private var webURL: URL? {
        if let eventSlug { return URL(string: "https://polymarket.com/event/\(eventSlug)") }
        if let slug = market.slug { return URL(string: "https://polymarket.com/market/\(slug)") }
        return nil
    }

    private func loadHistory() async {
        guard let tokenId = market.clobTokenIds.first else {
            historyError = "価格履歴を取得できません（トークンIDなし）"
            return
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            history = try await services.clob.priceHistory(tokenId: tokenId, interval: interval)
            historyError = nil
        } catch {
            if !error.isCancellation { historyError = error.localizedDescription }
        }
    }
}

/// 通知やアラート一覧から ID だけでマーケット詳細を開くためのローダー
struct MarketDetailLoader: View {
    let marketId: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var market: PMMarket?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let market {
                MarketDetailView(
                    market: market,
                    eventTitle: market.events.first?.title,
                    eventSlug: market.events.first?.slug)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("読み込めませんでした", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("再試行") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            market = try await services.gamma.market(id: marketId)
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}
