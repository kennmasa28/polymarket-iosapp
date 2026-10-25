//
//  AlertModels.swift
//  polymarket-iosapp
//

import Foundation

nonisolated enum AlertKind: String, Codable, CaseIterable, Sendable {
    case priceMove
    case volumeSurge
    case traderSurge

    var label: String {
        switch self {
        case .priceMove: "価格急変"
        case .volumeSurge: "出来高急増"
        case .traderSurge: "参加者急増"
        }
    }

    var systemImage: String {
        switch self {
        case .priceMove: "arrow.up.arrow.down"
        case .volumeSurge: "chart.bar.fill"
        case .traderSurge: "person.3.fill"
        }
    }
}

/// 価格・出来高の時系列スナップショット（巡回ごとに 1 点）
nonisolated struct Snapshot: Codable, Hashable, Sendable {
    let t: Date
    /// Yes 価格
    let p: Double?
    /// 累計出来高（USD）
    let v: Double

    init(t: Date, price: Double?, volume: Double) {
        self.t = t
        self.p = price
        self.v = volume
    }

    var price: Double? { p }
    var volume: Double { v }
}

/// 検知結果
nonisolated struct Detection: Equatable, Sendable {
    let kind: AlertKind
    /// 価格差（pt）または倍率
    let magnitude: Double
    let summary: String
}

/// 発火した（または発火候補の）アラートの履歴
nonisolated struct AlertRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var kind: AlertKind
    var marketId: String
    var question: String
    var eventTitle: String
    var eventSlug: String?
    var conditionName: String
    var summary: String
    var price: Double?
    var isRead = false
}
