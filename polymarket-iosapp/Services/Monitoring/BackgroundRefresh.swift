//
//  BackgroundRefresh.swift
//  polymarket-iosapp
//
//  BGAppRefreshTask によるバックグラウンド巡回のスケジュール。
//  iOS が実行タイミングを決めるため間隔は保証されない（最短でも 15 分程度、1 回あたり約 30 秒）。
//  識別子は Info.plist の BGTaskSchedulerPermittedIdentifiers にも登録が必要。
//

import BackgroundTasks
import Foundation

nonisolated enum BackgroundRefresh {
    static let taskIdentifier = "kengo.shibata.polymarket-iosapp.monitor"

    static func schedule(afterMinutes minutes: Int) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(max(minutes, 15) * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BackgroundRefresh: failed to schedule: \(error)")
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
}
