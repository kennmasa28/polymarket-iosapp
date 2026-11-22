//
//  TrendingView.swift
//  PolymarketWatch
//
//  24 時間出来高の多いマーケット（トレンド）。お気に入り一覧から開き、タップで詳細を開く。
//

import SwiftUI

struct TrendingView: View {
    @State private var items: [WatchTrendingItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if items.isEmpty && isLoading {
                ProgressView()
            }
            ForEach(items) { item in
                NavigationLink(value: WatchMarketRoute(marketId: item.marketId, title: item.marketTitle ?? item.eventTitle)) {
                    TrendingRow(item: item)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            if !items.isEmpty {
                Button {
                    Task { await load() }
                } label: {
                    Label("更新", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("トレンド")
        .task {
            if items.isEmpty { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await WatchAPI.trending()
            errorMessage = nil
        } catch {
            errorMessage = "読み込めませんでした"
        }
    }
}

private struct TrendingRow: View {
    let item: WatchTrendingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                MarketIcon(urlString: item.imageURL, size: 24)
                Text(item.eventTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let title = item.marketTitle {
                    Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(WatchFormat.percent(item.price))
                    .font(.system(.body, design: .rounded).weight(.bold).monospacedDigit())
                ChangeText(change: item.dayChange)
                    .font(.caption2.monospacedDigit())
            }
            Text("24h \(WatchFormat.usd(item.volume24h))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
