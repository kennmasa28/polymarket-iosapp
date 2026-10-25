//
//  CommonViews.swift
//  polymarket-iosapp
//

import SwiftUI

struct RemoteImage: View {
    let urlString: String?
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: urlString.flatMap { URL(string: $0) }) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

/// 価格変化（pt）を色付きで表示
struct ChangeBadge: View {
    let change: Double?

    var body: some View {
        if let change, abs(change) >= 0.0005 {
            Text(Fmt.points(change))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(change > 0 ? Color.green : Color.red)
        }
    }
}

/// ナビゲーション用：マーケット詳細への遷移先
struct MarketDestination: Hashable {
    let market: PMMarket
    let eventTitle: String?
    let eventSlug: String?

    init(market: PMMarket, eventTitle: String?, eventSlug: String?) {
        self.market = market
        self.eventTitle = eventTitle
        self.eventSlug = eventSlug
    }

    init(_ item: MonitoredMarket) {
        self.init(market: item.market, eventTitle: item.eventTitle, eventSlug: item.eventSlug)
    }
}

struct MarketRow: View {
    let market: PMMarket
    /// 指定時はこの変化量を表示（モニター画面のウィンドウ変化など）。nil なら 24h 変化
    var change: Double?
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(market.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("24h \(Fmt.usd(market.volume24hr)) · 流動性 \(Fmt.usd(market.liquidity))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.percent(market.yesPrice))
                    .font(.title3.monospacedDigit().weight(.semibold))
                ChangeBadge(change: change ?? market.oneDayPriceChange)
            }
        }
        .padding(.vertical, 2)
    }
}

extension View {
    /// 共通の遷移先登録
    func marketNavigationDestinations() -> some View {
        self
            .navigationDestination(for: PMEvent.self) { EventDetailView(event: $0) }
            .navigationDestination(for: MarketDestination.self) { destination in
                MarketDetailView(
                    market: destination.market,
                    eventTitle: destination.eventTitle,
                    eventSlug: destination.eventSlug)
            }
    }
}
