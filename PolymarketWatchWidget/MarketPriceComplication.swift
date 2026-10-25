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

    private var changeColor: Color {
        guard let change = entry.quote?.dayChange else { return .secondary }
        return change >= 0 ? .green : .red
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let quote = entry.quote {
            Gauge(value: quote.price, in: 0...1) {
                Text("Yes")
            } currentValueLabel: {
                Text("\(Int((quote.price * 100).rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            Image(systemName: "chart.line.uptrend.xyaxis")
        }
    }

    private var corner: some View {
        Text(entry.quote?.percentText ?? "—")
            .font(.title3.monospacedDigit())
            .widgetLabel {
                Text("\(entry.title ?? "Polymarket") \(entry.quote?.changeText ?? "")")
            }
    }

    private var inline: some View {
        Text("\(entry.title ?? "Polymarket") \(entry.quote?.percentText ?? "—") \(entry.quote?.changeText ?? "")")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title ?? "お気に入りなし")
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            if let quote = entry.quote {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(quote.percentText)
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text("\(quote.changeText)pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(changeColor)
                }
                Text("24h · \(quote.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("iPhone で ☆ を付けて追加")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
