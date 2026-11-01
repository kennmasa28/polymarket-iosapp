//
//  MarketPriceComplication.swift
//  PolymarketWatchWidget
//
//  Apple Watch の文字盤に置けるコンプリケーション（WidgetKit の accessory ウィジェット）。
//  お気に入りのマーケットの Yes 価格（確率）と 24 時間の変化を表示する。
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

struct FavoriteMarketEntity: AppEntity {
    let id: String
    let title: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "マーケット")
    static let defaultQuery = FavoriteMarketQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(_ favorite: FavoriteMarket) {
        self.init(id: favorite.id, title: favorite.title)
    }
}

struct FavoriteMarketQuery: EntityQuery {
    func entities(for identifiers: [FavoriteMarketEntity.ID]) async throws -> [FavoriteMarketEntity] {
        SharedStore.favorites()
            .filter { identifiers.contains($0.id) }
            .map(FavoriteMarketEntity.init)
    }

    func suggestedEntities() async throws -> [FavoriteMarketEntity] {
        SharedStore.favorites().map(FavoriteMarketEntity.init)
    }
}

struct SelectMarketIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "マーケットを選択" }

    /// 未指定ならお気に入りの先頭を表示
    @Parameter(title: "マーケット")
    var market: FavoriteMarketEntity?
}

// MARK: - Timeline

struct QuoteEntry: TimelineEntry {
    let date: Date
    let title: String?
    let quote: MarketQuote?
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(date: .now, title: MarketQuote.placeholder.title, quote: .placeholder)
    }

    func snapshot(for configuration: SelectMarketIntent, in context: Context) async -> QuoteEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SelectMarketIntent, in context: Context) async -> Timeline<QuoteEntry> {
        let entry = await entry(for: configuration)
        // 文字盤の更新回数には上限があるため 15 分間隔で十分
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    /// watchOS では文字盤編集時にこの一覧から選ぶ
    func recommendations() -> [AppIntentRecommendation<SelectMarketIntent>] {
        let favorites = SharedStore.favorites()
        guard !favorites.isEmpty else {
            return [AppIntentRecommendation(intent: SelectMarketIntent(), description: Text("お気に入りの先頭"))]
        }
        return favorites.prefix(10).map { favorite in
            var intent = SelectMarketIntent()
            intent.market = FavoriteMarketEntity(favorite)
            return AppIntentRecommendation(intent: intent, description: Text(favorite.title))
        }
    }

    private func entry(for configuration: SelectMarketIntent) async -> QuoteEntry {
        let favorites = SharedStore.favorites()
        let selected = favorites.first { $0.id == configuration.market?.id } ?? favorites.first
        guard let favorite = selected else {
            return QuoteEntry(date: .now, title: nil, quote: nil)
        }
        let fetched = try? await QuoteFetcher.quotes(for: [favorite]).first
        return QuoteEntry(
            date: .now, title: favorite.title, quote: fetched ?? SharedStore.cachedQuote(for: favorite.id))
    }
}

// MARK: - Views

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuoteEntry

    var body: some View {
        switch family {
        case .accessoryCircular: CircularComplication(entry: entry)
        case .accessoryCorner: CornerComplication(entry: entry)
        case .accessoryInline: InlineComplication(entry: entry)
        default: RectangularComplication(entry: entry)
        }
    }
}

/// 24 時間の変化を ▲3.1 / ▼1.2 の形で表示
private struct ChangeLabel: View {
    let change: Double?

    var body: some View {
        if let change, abs(change) >= 0.0005 {
            HStack(spacing: 1) {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .imageScale(.small)
                Text(String(format: "%.1f", abs(change) * 100))
            }
            .foregroundStyle(change > 0 ? Color.green : Color.red)
        } else {
            Text("±0").foregroundStyle(.secondary)
        }
    }
}

/// モジュラー文字盤の中央など。タイトル / 確率 + 変化 / 確率バー の 3 段に収める
private struct RectangularComplication: View {
    let entry: QuoteEntry

    var body: some View {
        if let quote = entry.quote {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .imageScale(.small)
                    Text(entry.title ?? quote.title)
                        .lineLimit(1)
                }
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.0f", quote.price * 100))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    ChangeLabel(change: quote.dayChange)
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                ProbabilityBar(value: quote.price)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Polymarket", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text("iPhone アプリで ☆ を付けたマーケットを表示します")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// 確率を示す細いバー
private struct ProbabilityBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.tint)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), 3))
                    .widgetAccentable()
            }
        }
        .frame(height: 4)
    }
}

private struct CircularComplication: View {
    let entry: QuoteEntry

    var body: some View {
        if let quote = entry.quote {
            Gauge(value: quote.price, in: 0...1) {
                Image(systemName: (quote.dayChange ?? 0) >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            } currentValueLabel: {
                Text(String(format: "%.0f", quote.price * 100))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .widgetAccentable()
        }
    }
}

private struct CornerComplication: View {
    let entry: QuoteEntry

    var body: some View {
        Text(entry.quote.map { String(format: "%.0f%%", $0.price * 100) } ?? "—")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .minimumScaleFactor(0.6)
            .widgetLabel {
                Text("\(entry.title ?? "Polymarket") \(entry.quote?.changeText ?? "")")
            }
    }
}

private struct InlineComplication: View {
    let entry: QuoteEntry

    var body: some View {
        if let quote = entry.quote {
            Text("\(entry.title ?? quote.title) \(quote.percentText) \(quote.changeText)")
        } else {
            Text("Polymarket")
        }
    }
}

// MARK: - Widget

@main
struct MarketPriceComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WatchShared.widgetKind, intent: SelectMarketIntent.self, provider: QuoteProvider()
        ) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("マーケット価格")
        .description("お気に入りのマーケットの価格と24時間の変化")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
