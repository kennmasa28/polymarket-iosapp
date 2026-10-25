//
//  FeedView.swift
//  polymarket-iosapp
//
//  最新トピックス：出来高上位のイベントを、監視条件ごとに切り替えて表示する。
//

import SwiftUI

struct FeedView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings

    /// nil = トレンド（全カテゴリ）
    @State private var selectedConditionId: UUID?
    @State private var events: [PMEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var searchResults: [PMEvent]?

    private var displayedEvents: [PMEvent] { searchResults ?? events }

    var body: some View {
        NavigationStack {
            List {
                if searchResults == nil {
                    conditionChips
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                ForEach(displayedEvents) { event in
                    NavigationLink(value: event) {
                        EventRow(event: event)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("トピックス")
            .marketNavigationDestinations()
            .searchable(text: $query, prompt: "マーケットを検索")
            .task(id: query) { await search() }
            .task(id: selectedConditionId) { await load() }
            .refreshable { await load() }
            .overlay {
                if isLoading && displayedEvents.isEmpty {
                    ProgressView()
                } else if !isLoading && displayedEvents.isEmpty && errorMessage == nil {
                    ContentUnavailableView("該当するマーケットがありません", systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var conditionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "トレンド", systemImage: "flame", id: nil)
                ForEach(settings.enabledConditions) { condition in
                    chip(title: condition.name, systemImage: "line.3.horizontal.decrease", id: condition.id)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, systemImage: String, id: UUID?) -> some View {
        let isSelected = selectedConditionId == id
        return Button {
            selectedConditionId = id
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        let condition = settings.value.conditions.first { $0.id == selectedConditionId }
        isLoading = true
        defer { isLoading = false }
        do {
            var cache: [String: [PMEvent]] = [:]
            let fetched = try await EventFetcher(gamma: services.gamma)
                .events(for: condition, maxEventsPerTag: condition == nil ? 50 : 100, cache: &cache)
            let filtered = condition.map { ConditionMatcher.filterEvents(fetched, condition: $0) } ?? fetched
            events = filtered.sorted { ($0.volume24hr ?? 0) > ($1.volume24hr ?? 0) }
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            searchResults = nil
            return
        }
        // 入力中の連続リクエストを避ける
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            searchResults = try await services.gamma.search(text).events
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}

struct EventRow: View {
    let event: PMEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(urlString: event.image ?? event.icon, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                if let market = event.leadingMarket {
                    HStack {
                        Text(event.markets.count > 1 ? market.displayName : "Yes")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.percent(market.yesPrice))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        ChangeBadge(change: market.oneDayPriceChange)
                    }
                    .font(.subheadline)
                }
                HStack(spacing: 10) {
                    Label(Fmt.usd(event.volume24hr), systemImage: "chart.bar")
                    if event.markets.count > 1 {
                        Label("\(event.markets.count)", systemImage: "list.bullet")
                    }
                    if let end = event.endDateValue {
                        Label(end.formatted(.relative(presentation: .named)), systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
    }
}
