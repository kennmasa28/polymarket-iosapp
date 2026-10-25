//
//  polymarket_iosappApp.swift
//  polymarket-iosapp
//
//  Created by Kengo Shibata on 2026/10/25.
//

import SwiftUI
import UserNotifications

@main
struct polymarket_iosappApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container.services)
                .environment(container.settings)
                .environment(container.alerts)
                .environment(container.monitor)
                .environment(container.router)
        }
        .onChange(of: scenePhase) { _, phase in
            container.handleScenePhase(phase)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await AppContainer.shared.runBackgroundRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// アプリ表示中もバナーを出す
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 通知タップでマーケット詳細を開く
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let marketId = response.notification.request.content.userInfo[NotificationService.marketIdKey] as? String
        guard let marketId else { return }
        await MainActor.run {
            AppContainer.shared.router.openMarket(id: marketId)
        }
    }
}
