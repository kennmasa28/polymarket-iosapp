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
                .environment(container.agent)
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

    // 通知デリゲートは UNUserNotificationCenter が自前のバックグラウンドキューから呼ぶ。
    // このターゲットは既定で MainActor 隔離（SWIFT_DEFAULT_ACTOR_ISOLATION）かつ
    // nonisolated(nonsending) が既定（SWIFT_APPROACHABLE_CONCURRENCY）のため、async 版のデリゲートは
    // Objective-C からのブリッジで実行スレッドの前提が崩れ、通知タップ時にクラッシュし得る。
    // そこで completionHandler 版を nonisolated で実装し、必要な値だけ取り出して明示的にメインへ渡す。

    /// アプリ表示中もバナーを出す
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// 通知タップでマーケット詳細を開く
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let marketId = response.notification.request.content.userInfo[NotificationService.marketIdKey] as? String
        completionHandler()
        guard let marketId, !marketId.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                AppContainer.shared.router.openMarket(id: marketId)
            }
        }
    }
}
