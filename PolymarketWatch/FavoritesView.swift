//
//  FavoritesView.swift
//  PolymarketWatch
//
//  iPhone で ☆ を付けたマーケットの一覧。タップで詳細（グラフ付き）を開く。
//

import SwiftUI

struct FavoritesView: View {
    private let receiver = WatchSessionReceiver.shared

    @State private var quotes: [String: MarketQuote] = [:]
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if receiver.favorites.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "star").font(.title3).foregroundStyle(.yellow)
                        Text("iPhone アプリのマーケット詳細で ☆ を付けると、ここと文字盤に表示されます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(receiver.favorites) { favorite in
                    NavigationLink(value: WatchMarketRoute(marketId: favorite.id, title: favorite.title)) {
                        FavoriteRow(favorite: favorite, quote: quotes[favorite.id])
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("お気に入り")
            .navigationDestination(for: WatchMarketRoute.self) { route in
                MarketDetailView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isLoading || receiver.favorites.isEmpty)
                }
            }
            .task(id: receiver.favorites) { await refresh() }
        }
    }

    private func refresh() async {
        guard !receiver.favorites.isEmpty else { return }
        // 通信前に前回の価格を表示する。UserDefaults の読み込みと JSON 解析はメインスレッド外で 1 回だけ行う
        if quotes.isEmpty {
            let cached = await Task.detached(priority: .userInitiated) { SharedStore.cachedQuotes() }.value
            for favorite in receiver.favorites where quotes[favorite.id] == nil {
                quotes[favorite.id] = cached[favorite.id]
            }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await QuoteFetcher.quotes(for: receiver.favorites)
            quotes = Dictionary(fetched.map { ($0.marketId, $0) }, uniquingKeysWith: { _, latest in latest })
            errorMessage = nil
        } catch {
            errorMessage = "価格を取得できませんでした"
        }
    }
}

private struct FavoriteRow: View {
    let favorite: FavoriteMarket
    let quote: MarketQuote?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                MarketIcon(urlString: quote?.imageURL, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    if let eventTitle = favorite.eventTitle {
                        Text(eventTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(favorite.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(WatchFormat.percent(quote?.price))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                Spacer()
                ChangeText(change: quote?.dayChange)
                    .font(.caption.monospacedDigit())
            }
            if let price = quote?.price {
                ProbabilityBar(value: price)
            }
        }
        .padding(.vertical, 2)
    }
}
