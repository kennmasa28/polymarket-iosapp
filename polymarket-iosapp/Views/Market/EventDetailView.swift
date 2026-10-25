//
//  EventDetailView.swift
//  polymarket-iosapp
//

import SwiftUI

struct EventDetailView: View {
    let event: PMEvent

    var body: some View {
        if event.markets.count == 1, let market = event.markets.first {
            MarketDetailView(market: market, eventTitle: event.title, eventSlug: event.slug)
        } else {
            List {
                Section {
                    HStack(spacing: 12) {
                        RemoteImage(urlString: event.image ?? event.icon, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.headline)
                            Text("24h \(Fmt.usd(event.volume24hr)) · 累計 \(Fmt.usd(event.volume))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("マーケット") {
                    ForEach(sortedMarkets) { market in
                        NavigationLink(value: MarketDestination(market: market, eventTitle: event.title, eventSlug: event.slug)) {
                            MarketRow(market: market)
                        }
                    }
                }
                if let url = event.webURL {
                    Section {
                        Link(destination: url) {
                            Label("Polymarketで開く", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sortedMarkets: [PMMarket] {
        event.markets.sorted {
            if $0.isTradable != $1.isTradable { return $0.isTradable }
            return ($0.yesPrice ?? 0) > ($1.yesPrice ?? 0)
        }
    }
}
