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

    /// オンならお気に入りからランダムに選び、一定間隔で切り替える（market より優先）
    @Parameter(title: "お気に入りからランダムに表示", default: false)
    var random: Bool
}

// MARK: - Timeline

struct QuoteEntry: TimelineEntry {
    let date: Date
    let title: String?
    let quote: MarketQuote?
    var eventTitle: String? = nil
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(date: .now, title: MarketQuote.placeholder.title, quote: .placeholder, eventTitle: MarketQuote.placeholder.eventTitle)
    }

    func snapshot(for configuration: SelectMarketIntent, in context: Context) async -> QuoteEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SelectMarketIntent, in context: Context) async -> Timeline<QuoteEntry> {
        // 文字盤の更新回数には上限があるため 15 分間隔で十分
        let interval: TimeInterval = 15 * 60
        guard configuration.random else {
            let entry = await entry(for: configuration)
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval)))
        }

        // ランダム: お気に入りの価格をまとめて取得し、15 分ごとに別のマーケットを表示する
        let favorites = SharedStore.favorites()
        let available = await quotes(for: favorites)
        guard !available.isEmpty else {
            return Timeline(entries: [QuoteEntry(date: .now, title: nil, quote: nil)], policy: .after(Date().addingTimeInterval(interval)))
        }
        let now = Date()
        let picks = Self.randomSequence(of: available, count: 4)
        let entries = picks.enumerated().map { index, quote in
            QuoteEntry(
                date: now.addingTimeInterval(Double(index) * interval), title: quote.title, quote: quote,
                eventTitle: quote.eventTitle)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// watchOS では文字盤編集時にこの一覧から選ぶ
    func recommendations() -> [AppIntentRecommendation<SelectMarketIntent>] {
        var randomIntent = SelectMarketIntent()
        randomIntent.random = true
        var recommendations = [
            AppIntentRecommendation(intent: randomIntent, description: Text("お気に入りからランダム")),
            AppIntentRecommendation(intent: SelectMarketIntent(), description: Text("お気に入りの先頭")),
        ]
        for favorite in SharedStore.favorites().prefix(10) {
            var intent = SelectMarketIntent()
            intent.market = FavoriteMarketEntity(favorite)
            recommendations.append(AppIntentRecommendation(intent: intent, description: Text(favorite.title)))
        }
        return recommendations
    }

    private func entry(for configuration: SelectMarketIntent) async -> QuoteEntry {
        let favorites = SharedStore.favorites()
        let selected: FavoriteMarket?
        if configuration.random {
            selected = favorites.randomElement()
        } else {
            selected = favorites.first { $0.id == configuration.market?.id } ?? favorites.first
        }
        guard let favorite = selected else {
            return QuoteEntry(date: .now, title: nil, quote: nil)
        }
        let quote = await quotes(for: [favorite]).first
        return QuoteEntry(date: .now, title: favorite.title, quote: quote, eventTitle: favorite.eventTitle)
    }

    /// 取得に失敗したマーケットは直近のキャッシュで補う
    private func quotes(for favorites: [FavoriteMarket]) async -> [MarketQuote] {
        let fetched = (try? await QuoteFetcher.quotes(for: favorites)) ?? []
        let byId = Dictionary(fetched.map { ($0.marketId, $0) }, uniquingKeysWith: { first, _ in first })
        return favorites.compactMap { byId[$0.id] ?? SharedStore.cachedQuote(for: $0.id) }
    }

    /// 同じマーケットが連続しないようにランダムに並べる
    static func randomSequence(of quotes: [MarketQuote], count: Int) -> [MarketQuote] {
        guard quotes.count > 1 else { return Array(quotes.prefix(1)) }
        var result: [MarketQuote] = []
        var pool: [MarketQuote] = []
        while result.count < count {
            if pool.isEmpty { pool = quotes.shuffled() }
            let next = pool.removeLast()
            if next.marketId == result.last?.marketId, let swap = pool.popLast() {
                pool.append(next)
                result.append(swap)
            } else {
                result.append(next)
            }
        }
        return result
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
/// モジュラー文字盤の中央など。上下幅が限られるので
/// イベント名（小）/ マーケット名 / 確率・変化・確率バー（横一列）の 3 段に収める
private struct RectangularComplication: View {
    let entry: QuoteEntry

    var body: some View {
        if let quote = entry.quote {
            VStack(alignment: .leading, spacing: 0) {
                if let eventTitle = entry.eventTitle ?? quote.eventTitle {
                    Text(eventTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(entry.title ?? quote.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(String(format: "%.0f", quote.price * 100))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    ChangeLabel(change: quote.dayChange)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .fixedSize()
                    ProbabilityBar(value: quote.price)
                }
                .monospacedDigit()
            }
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
