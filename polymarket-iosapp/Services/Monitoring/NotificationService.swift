//
//  NotificationService.swift
//  polymarket-iosapp
//

import Foundation
import UserNotifications

nonisolated enum NotificationService {
    static let marketIdKey = "marketId"
    /// 1 回の巡回で個別に通知する最大件数（超過分はまとめて 1 件にする）
    static let maxIndividualNotifications = 5

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func deliver(_ records: [AlertRecord]) async {
        let center = UNUserNotificationCenter.current()
        for record in records.prefix(maxIndividualNotifications) {
            let content = UNMutableNotificationContent()
            content.title = "\(record.kind.label)｜\(record.conditionName)"
            content.subtitle = record.question
            content.body = record.summary
            content.sound = .default
            content.threadIdentifier = record.kind.rawValue
            content.userInfo = [marketIdKey: record.marketId]
            try? await center.add(UNNotificationRequest(
                identifier: record.id.uuidString, content: content, trigger: nil))
        }

        let rest = records.count - maxIndividualNotifications
        if rest > 0 {
            let content = UNMutableNotificationContent()
            content.title = "ほか\(rest)件のアラート"
            content.body = "アプリのアラート一覧で確認できます"
            content.sound = .default
            try? await center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    static func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "テスト通知"
        content.body = "Polymarket モニターからの通知は正常に届いています"
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
