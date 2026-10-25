//
//  MonitorView.swift
//  polymarket-iosapp
//
//  監視状況と、条件ごとの監視対象マーケット（ウィンドウ内の変化が大きい順）。
//

import SwiftUI

struct MonitorView: View {
    @Environment(MarketMonitor.self) private var monitor
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router

    private let previewCount = 15

    var body: some View {
        NavigationStack {
            List {
                statusSection

                if settings.enabledConditions.isEmpty {
                    ContentUnavailableView {
                        Label("監視条件がありません", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("設定タブでタグやキーワードを指定して監視条件を追加してください")
                    } actions: {
                        Button("設定を開く") { router.selectedTab = .settings }
                    }
                }

                ForEach(settings.enabledConditions) { condition in
                    let markets = sortedByMove(monitor.marketsByCondition[condition.id] ?? [])
                    Section {
                        if markets.isEmpty {
                            Text(monitor.lastRunAt == nil ? "未取得" : "一致するマーケットがありません")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(markets.prefix(previewCount)) { item in
                            NavigationLink(value: MarketDestination(item)) {
                                MarketRow(market: item.market, change: item.windowChange, subtitle: item.eventTitle)
                            }
                        }
                        if markets.count > previewCount {
                            NavigationLink("すべて表示（\(markets.count)件）") {
                                ConditionMarketsView(condition: condition, markets: markets)
                            }
                        }
                    } header: {
                        HStack {
                            Text(condition.name)
                            Spacer()
                            Text("\(markets.count)件 · \(condition.rules.windowLabel)の変化")
                        }
                    }
                }
            }
            .navigationTitle("モニター")
            .marketNavigationDestinations()
            .refreshable { await monitor.runCycle(trigger: .manual) }
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Label(
                    settings.value.monitoringEnabled ? "監視中（\(settings.value.pollIntervalMinutes)分ごと）" : "監視停止中",
                    systemImage: settings.value.monitoringEnabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                Spacer()
                if monitor.isRunning { ProgressView() }
            }
            if let lastRunAt = monitor.lastRunAt {
                LabeledContent("最終チェック", value: lastRunAt.formatted(date: .omitted, time: .standard))
            }
            if let summary = monitor.lastSummary {
                Text(summary).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(monitor.lastErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await monitor.runCycle(trigger: .manual) }
            } label: {
                Label("今すぐチェック", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isRunning)
        }
    }

    private func sortedByMove(_ markets: [MonitoredMarket]) -> [MonitoredMarket] {
        markets.sorted { abs($0.windowChange ?? 0) > abs($1.windowChange ?? 0) }
    }
}

struct ConditionMarketsView: View {
    let condition: WatchCondition
    let markets: [MonitoredMarket]

    @State private var query = ""

    private var filtered: [MonitoredMarket] {
        guard !query.isEmpty else { return markets }
        let q = query.lowercased()
        return markets.filter {
            $0.market.question.lowercased().contains(q) || $0.eventTitle.lowercased().contains(q)
        }
    }

    var body: some View {
        List(filtered) { item in
            NavigationLink(value: MarketDestination(item)) {
                MarketRow(market: item.market, change: item.windowChange, subtitle: item.eventTitle)
            }
        }
        .searchable(text: $query)
        .navigationTitle(condition.name)
    }
}
