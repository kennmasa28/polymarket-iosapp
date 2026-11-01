//
//  FavoritesView.swift
//  polymarket-iosapp
//
//  お気に入りのマーケットをすぐ確認できる一覧。表示中は 1 分ごとに価格を更新する。
//  並べ替えた順番は Apple Watch のコンプリケーション（「お気に入りの先頭」）にも反映される。
//

import SwiftUI

struct FavoritesView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings

    @State private var markets: [String: PMMarket] = [:]
    @State private var holdings: [String: Double] = [:]
    @State private var lastUpdated: Date?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var favoriteIds: [String] { settings.value.favorites.map(\.id) }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Section {
                    ForEach(settings.value.favorites) { favorite in
                        row(for: favorite)
                    }
                    .onDelete { settings.removeFavorites(at: $0) }
                    .onMove { settings.moveFavorites(from: $0, to: $1) }
                } footer: {
                    if let lastUpdated {
                        Text("更新 \(lastUpdated.formatted(date: .omitted, time: .standard)) · 1分ごとに自動更新")
                    }
                }
            }
            .overlay {
                if settings.value.favorites.isEmpty {
                    ContentUnavailableView(
                        "お気に入りはありません", systemImage: "star",
                        description: Text("マーケット詳細の右上の ☆ で追加できます。Apple Watch の文字盤にも表示されます。"))
                }
            }
            .navigationTitle("お気に入り")
            .toolbar {
                if !settings.value.favorites.isEmpty { EditButton() }
            }
            .marketNavigationDestinations()
            .refreshable { await load() }
            .task(id: favoriteIds) { await load() }
            .task {
                // 表示中は定期的に価格を更新
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { break }
                    await load()
                }
            }
        }
    }

    @ViewBuilder
    private func row(for favorite: FavoriteMarket) -> some View {
        if let market = markets[favorite.id] {
            NavigationLink(value: MarketDestination(
                market: market, eventTitle: market.events.first?.title, eventSlug: market.events.first?.slug)
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    MarketRow(market: market, subtitle: market.events.first?.title)
                    if let held = heldShares(in: market) {
                        Label(held, systemImage: "briefcase")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else {
            HStack {
                Text(favorite.question).lineLimit(2)
                Spacer()
                if isLoading { ProgressView() }
            }
        }
    }

    /// このマーケットの保有株数（例: "Yes 12.34 株保有"）
    private func heldShares(in market: PMMarket) -> String? {
        let parts = market.clobTokenIds.enumerated().compactMap { index, tokenId -> String? in
            guard let shares = holdings[tokenId], shares >= 0.01 else { return nil }
            let outcome = market.outcomes.indices.contains(index) ? market.outcomes[index] : "?"
            return String(format: "%@ %.2f 株", outcome, shares)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ") + " 保有"
    }

    private func load() async {
        let ids = favoriteIds
        guard !ids.isEmpty else {
            markets = [:]
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await services.gamma.markets(ids: ids)
            markets = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            lastUpdated = .now
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        if services.trading.state.isConfigured, let positions = try? await services.trading.positions() {
            holdings = Dictionary(positions.map { ($0.tokenId, $0.size) }, uniquingKeysWith: +)
        }
    }
}
