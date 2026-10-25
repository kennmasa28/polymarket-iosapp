//
//  Stores.swift
//  polymarket-iosapp
//

import Foundation
import Observation

/// 監視条件・アプリ設定（settings.json）
@Observable
final class SettingsStore {
    private static let fileName = "settings.json"

    var value: AppSettings {
        didSet { LocalStore.save(value, to: Self.fileName) }
    }

    init() {
        value = LocalStore.load(AppSettings.self, from: Self.fileName) ?? AppSettings()
    }

    var enabledConditions: [WatchCondition] { value.conditions.filter(\.isEnabled) }

    func upsert(_ condition: WatchCondition) {
        if let index = value.conditions.firstIndex(where: { $0.id == condition.id }) {
            value.conditions[index] = condition
        } else {
            value.conditions.append(condition)
        }
    }

    func removeConditions(at offsets: IndexSet) {
        value.conditions.removeElements(at: offsets)
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = value.conditions.firstIndex(where: { $0.id == id }) else { return }
        value.conditions[index].isEnabled = enabled
    }

    // MARK: Favorites

    func isFavorite(marketId: String) -> Bool {
        value.favorites.contains { $0.id == marketId }
    }

    func toggleFavorite(_ market: PMMarket) {
        if let index = value.favorites.firstIndex(where: { $0.id == market.id }) {
            value.favorites.remove(at: index)
        } else {
            value.favorites.append(FavoriteMarket(
                id: market.id,
                title: FavoriteMarket.shortTitle(from: market.displayName),
                question: market.question))
        }
        WatchSyncService.shared.send(favorites: value.favorites)
    }

    func removeFavorites(at offsets: IndexSet) {
        value.favorites.removeElements(at: offsets)
        WatchSyncService.shared.send(favorites: value.favorites)
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        var favorites = value.favorites
        let moving = source.sorted().map { favorites[$0] }
        favorites.removeElements(at: source)
        let insertAt = destination - source.filter { $0 < destination }.count
        favorites.insert(contentsOf: moving, at: max(0, min(insertAt, favorites.count)))
        value.favorites = favorites
        WatchSyncService.shared.send(favorites: value.favorites)
    }
}

/// アラート履歴（alerts.json）
@Observable
final class AlertStore {
    private static let fileName = "alerts.json"
    private static let maxRecords = 500

    private(set) var records: [AlertRecord]

    init() {
        records = LocalStore.load([AlertRecord].self, from: Self.fileName) ?? []
    }

    var unreadCount: Int { records.lazy.filter { !$0.isRead }.count }

    /// クールダウン中のものを除いて記録し、新たに記録したものを返す
    func register(_ candidates: [AlertRecord], cooldownMinutes: Int, now: Date) -> [AlertRecord] {
        let cooldown = TimeInterval(cooldownMinutes) * 60
        var accepted: [AlertRecord] = []
        for candidate in candidates {
            let isCoolingDown = (records + accepted).contains {
                $0.marketId == candidate.marketId && $0.kind == candidate.kind
                    && now.timeIntervalSince($0.date) < cooldown
            }
            if !isCoolingDown { accepted.append(candidate) }
        }
        guard !accepted.isEmpty else { return [] }
        records = Array((accepted + records).prefix(Self.maxRecords))
        save()
        return accepted
    }

    func markRead(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }), !records[index].isRead else { return }
        records[index].isRead = true
        save()
    }

    func markAllRead() {
        guard records.contains(where: { !$0.isRead }) else { return }
        for index in records.indices { records[index].isRead = true }
        save()
    }

    func remove(at offsets: IndexSet) {
        records.removeElements(at: offsets)
        save()
    }

    func removeAll() {
        records.removeAll()
        save()
    }

    private func save() {
        LocalStore.save(records, to: Self.fileName)
    }
}

/// マーケットごとの価格・出来高スナップショット履歴（snapshots.json）
final class SnapshotStore {
    private static let fileName = "snapshots.json"
    /// 24h ウィンドウでも判定できるよう少し長めに保持
    private static let retention: TimeInterval = 26 * 3600
    private static let maxPointsPerMarket = 320

    private var storage: [String: [Snapshot]]

    init() {
        storage = LocalStore.load([String: [Snapshot]].self, from: Self.fileName) ?? [:]
    }

    func history(for marketId: String) -> [Snapshot] {
        storage[marketId] ?? []
    }

    func record(_ latest: [String: Snapshot], now: Date) {
        for (marketId, snapshot) in latest {
            storage[marketId, default: []].append(snapshot)
        }
        let cutoff = now.addingTimeInterval(-Self.retention)
        storage = storage.compactMapValues { points in
            let kept = points.filter { $0.t >= cutoff }
            return kept.isEmpty ? nil : Array(kept.suffix(Self.maxPointsPerMarket))
        }
        // 数 MB になり得るのでメインスレッド外で書き込む
        let snapshot = storage
        let fileName = Self.fileName
        Task.detached(priority: .utility) {
            LocalStore.save(snapshot, to: fileName)
        }
    }

    func removeAll() {
        storage.removeAll()
        LocalStore.remove(Self.fileName)
    }
}

private extension Array {
    /// SwiftUI の `remove(atOffsets:)` 相当（ストア層を SwiftUI に依存させないため）
    mutating func removeElements(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
    }
}
