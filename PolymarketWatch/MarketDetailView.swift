//
//  MarketDetailView.swift
//  PolymarketWatch
//
//  マーケット詳細: 画像・イベント名・各アウトカムの確率・価格推移グラフ・変化・出来高など。
//

import Charts
import SwiftUI

struct MarketDetailView: View {
    let route: WatchMarketRoute

    @State private var market: WatchMarketDetail?
    @State private var history: [WatchPricePoint] = []
    @State private var range: WatchChartRange = .day
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let market {
                VStack(alignment: .leading, spacing: 10) {
                    header(market)
                    outcomes(market)
                    chartSection(market)
                    changes(market)
                    stats(market)
                    if let rules = market.rules, !rules.isEmpty {
                        Text(rules)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(route.title)
        .task { await loadMarket() }
        .task(id: range) { await loadHistory() }
    }

    // MARK: Sections

    private func header(_ market: WatchMarketDetail) -> some View {
        HStack(alignment: .top, spacing: 8) {
            MarketIcon(urlString: market.imageURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                if let event = market.eventTitle, event != market.question {
                    Text(event)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(market.question)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(4)
            }
        }
    }

    /// 各アウトカム（通常 Yes / No）の確率
    private func outcomes(_ market: WatchMarketDetail) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(zip(market.outcomes, market.prices).prefix(2).enumerated()), id: \.offset) { index, pair in
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.0)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(WatchFormat.percent(pair.1))
                        .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(index == 0 ? Color.green : Color.red)
                    ProbabilityBar(value: pair.1, color: index == 0 ? .green : .red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func chartSection(_ market: WatchMarketDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(WatchChartRange.allCases) { option in
                    Button(option.label) { range = option }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .tint(option == range ? .accentColor : .gray)
                }
            }
            if history.count >= 2 {
                Chart(history) { point in
                    AreaMark(x: .value("時刻", point.date), yStart: .value("下限", yDomain.lowerBound), yEnd: .value("価格", point.p))
                        .foregroundStyle(.linearGradient(
                            colors: [Color.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("時刻", point.date), y: .value("価格", point.p))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYScale(domain: yDomain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let price = value.as(Double.self) { Text(WatchFormat.percent(price)).font(.system(size: 9)) }
                        }
                    }
                }
                .frame(height: 90)
            } else {
                Text(market.tokenIds.isEmpty ? "価格履歴はありません" : "グラフを読み込み中…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 40)
            }
        }
    }

    private func changes(_ market: WatchMarketDetail) -> some View {
        HStack {
            changeCell("1時間", market.oneHourChange)
            changeCell("24時間", market.oneDayChange)
            changeCell("1週間", market.oneWeekChange)
        }
    }

    private func changeCell(_ title: String, _ change: Double?) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            ChangeText(change: change).font(.caption2.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ market: WatchMarketDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            statRow("24h 出来高", WatchFormat.usd(market.volume24h))
            statRow("累計出来高", WatchFormat.usd(market.volume))
            statRow("流動性", WatchFormat.usd(market.liquidity))
            if let end = market.endDate {
                statRow("終了", end.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .font(.caption2)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private var yDomain: ClosedRange<Double> {
        let prices = history.map(\.p)
        guard let low = prices.min(), let high = prices.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, 0.02)
        return max(low - padding, 0)...min(high + padding, 1)
    }

    // MARK: Loading

    private func loadMarket() async {
        do {
            market = try await WatchAPI.market(id: route.marketId)
            errorMessage = nil
            await loadHistory()
        } catch {
            errorMessage = "読み込めませんでした"
        }
    }

    private func loadHistory() async {
        guard let tokenId = market?.tokenIds.first else { return }
        history = (try? await WatchAPI.priceHistory(tokenId: tokenId, range: range)) ?? []
    }
}
