//
//  AppContainer.swift
//  polymarket-iosapp
//
//  アプリ全体で共有するサービス・ストアの生成と、フォアグラウンド巡回ループの管理。
//

import Foundation
import Observation
import SwiftUI

/// API クライアントと取引サービス
@Observable
final class AppServices {
    let gamma = GammaAPI()
    let clob = ClobAPI()
    let data = DataAPI()
    /// ウォレット接続・ロック管理を含む具体実装（設定画面で使用）
    let wallet = PolymarketTradingService()
    /// 売買 UI はこの抽象だけに依存する
    var trading: any TradingService { wallet }
}

nonisolated enum AppTab: Hashable {
    case feed, monitor, alerts, portfolio, settings
}

nonisolated struct MarketRef: Identifiable, Hashable, Sendable {
    let id: String
}

/// 画面遷移の状態（通知タップからの遷移など）
@Observable
final class AppRouter {
    var selectedTab: AppTab = .feed
    var presentedMarket: MarketRef?

    func openMarket(id: String) {
        presentedMarket = MarketRef(id: id)
    }
}

final class AppContainer {
    static let shared = AppContainer()

    let services = AppServices()
    let settings = SettingsStore()
    let alerts = AlertStore()
    let snapshots = SnapshotStore()
    let router = AppRouter()
    let monitor: MarketMonitor

    private var foregroundLoop: Task<Void, Never>?

    private init() {
        monitor = MarketMonitor(services: services, settings: settings, snapshots: snapshots, alerts: alerts)
        WatchSyncService.shared.activate(favorites: settings.value.favorites)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startForegroundLoop()
        case .background:
            stopForegroundLoop()
            // 秘密鍵をメモリに残さない
            services.wallet.lock()
            if settings.value.monitoringEnabled {
                BackgroundRefresh.schedule(afterMinutes: settings.value.pollIntervalMinutes)
            } else {
                BackgroundRefresh.cancel()
            }
        default:
            break
        }
    }

    func runBackgroundRefresh() async {
        guard settings.value.monitoringEnabled else { return }
        // 次回分を先に予約しておく（今回が時間切れで中断されても途切れないように）
        BackgroundRefresh.schedule(afterMinutes: settings.value.pollIntervalMinutes)
        await monitor.runCycle(trigger: .background)
    }

    private func startForegroundLoop() {
        foregroundLoop?.cancel()
        foregroundLoop = Task {
            while !Task.isCancelled {
                if settings.value.monitoringEnabled {
                    await monitor.runCycle(trigger: .foreground)
                }
                let minutes = max(settings.value.pollIntervalMinutes, 1)
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    private func stopForegroundLoop() {
        foregroundLoop?.cancel()
        foregroundLoop = nil
    }
}
