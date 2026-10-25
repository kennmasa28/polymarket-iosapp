//
//  FavoritesView.swift
//  PolymarketWatch
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
                    Text("iPhone アプリのマーケット詳細で ☆ を付けると、ここと文字盤に表示されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(receiver.favorites) { favorite in
                    QuoteRow(title: favorite.title, quote: quotes[favorite.id] ?? SharedStore.cachedQuote(for: favorite.id))
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                if !receiver.favorites.isEmpty {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isLoading { ProgressView() } else { Label("更新", systemImage: "arrow.clockwise") }
                    }
                    .disabled(isLoading)
                }
            }
            .navigationTitle("Polymarket")
            .task(id: receiver.favorites) { await refresh() }
        }
    }

    private func refresh() async {
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

private struct QuoteRow: View {
    let title: String
    let quote: MarketQuote?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).lineLimit(2)
            HStack(alignment: .firstTextBaseline) {
                Text(quote?.percentText ?? "—").font(.title3.monospacedDigit().weight(.semibold))
                Spacer()
                if let quote, let change = quote.dayChange {
                    Text(quote.changeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(change >= 0 ? Color.green : Color.red)
                }
            }
        }
    }
}
