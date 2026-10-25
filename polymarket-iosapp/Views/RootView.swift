//
//  RootView.swift
//  polymarket-iosapp
//

import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AlertStore.self) private var alerts
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("トピックス", systemImage: "flame", value: AppTab.feed) {
                FeedView()
            }
            Tab("モニター", systemImage: "waveform.path.ecg", value: AppTab.monitor) {
                MonitorView()
            }
            Tab("アラート", systemImage: "bell", value: AppTab.alerts) {
                AlertsView()
            }
            .badge(alerts.unreadCount)
            // ウォレット接続時のみ表示
            if services.trading.state.isConfigured {
                Tab("ポートフォリオ", systemImage: "briefcase", value: AppTab.portfolio) {
                    PortfolioView()
                }
            }
            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sheet(item: $router.presentedMarket) { ref in
            NavigationStack {
                MarketDetailLoader(marketId: ref.id)
                    .marketNavigationDestinations()
            }
        }
        .task {
            await NotificationService.requestAuthorization()
        }
    }
}
