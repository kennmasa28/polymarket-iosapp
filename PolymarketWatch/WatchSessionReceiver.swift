//
//  WatchSessionReceiver.swift
//  PolymarketWatch
//

import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// iPhone から applicationContext で届くお気に入りを受け取り、App Group に保存する
@MainActor
@Observable
final class WatchSessionReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchSessionReceiver()

    /// 起動直後の描画をふさがないよう、保存済みのお気に入りは activate() でメインスレッド外から読む
    private(set) var favorites: [FavoriteMarket] = []

    func activate() {
        Task {
            let saved = await Task.detached(priority: .userInitiated) { SharedStore.favorites() }.value
            if favorites.isEmpty && !saved.isEmpty { favorites = saved }
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func apply(_ data: Data) {
        guard let favorites = try? JSONDecoder().decode([FavoriteMarket].self, from: data),
              favorites != self.favorites
        else { return }
        self.favorites = favorites
        SharedStore.saveFavorites(favorites)
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        guard let data = session.receivedApplicationContext[WatchShared.favoritesContextKey] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchShared.favoritesContextKey] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }
}
