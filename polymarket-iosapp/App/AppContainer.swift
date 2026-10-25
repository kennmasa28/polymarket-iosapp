//
//  AppContainer.swift
//  polymarket-iosapp
//
//  アプリ全体で共有するサービス・ストアの生成と、フォアグラウンド巡回ループの管理。
//

import Foundation
import Observation
import SwiftUI

/// API クライアントと取引サービス。取引機能を実装したら `trading` を差し替える。
@Observable
final class AppServices {
    let gamma = GammaAPI()
    let clob = ClobAPI()
    let data = DataAPI()
    var trading: any TradingService = DisabledTradingService()
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
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startForegroundLoop()
        case .background:
            stopForegroundLoop()
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
