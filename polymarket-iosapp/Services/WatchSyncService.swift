//
//  WatchSyncService.swift
//  polymarket-iosapp
//
//  お気に入りを Apple Watch に送る（WatchConnectivity の applicationContext）。
//  applicationContext は最新の 1 件だけが保持され、Watch アプリが起動していなくても後で届く。
//

import Foundation
import WatchConnectivity

final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var pendingFavorites: [FavoriteMarket]?

    func activate(favorites: [FavoriteMarket]) {
        pendingFavorites = favorites
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            flush()
        } else {
            session.activate()
        }
    }

    func send(favorites: [FavoriteMarket]) {
        pendingFavorites = favorites
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), let favorites = pendingFavorites else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(favorites)
        else { return }
        do {
            try session.updateApplicationContext([WatchShared.favoritesContextKey: data])
            pendingFavorites = nil
        } catch {
            print("WatchSync: failed to send favorites: \(error)")
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
    ) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // ペアリングする Watch が切り替わった場合は再アクティベートする
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
}
