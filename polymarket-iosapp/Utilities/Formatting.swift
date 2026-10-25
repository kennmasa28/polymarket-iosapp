//
//  Formatting.swift
//  polymarket-iosapp
//

import Foundation

nonisolated enum Fmt {
    /// $1.2M のような短縮表記
    static func usd(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch abs(value) {
        case 1_000_000_000...: return String(format: "$%.1fB", value / 1_000_000_000)
        case 1_000_000...: return String(format: "$%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "$%.1fK", value / 1_000)
        default: return String(format: "$%.0f", value)
        }
    }

    /// 0.523 -> "52%"
    static func percent(_ price: Double?) -> String {
        guard let price else { return "—" }
        if price > 0 && price < 0.01 { return "<1%" }
        if price < 1 && price > 0.99 { return ">99%" }
        return String(format: "%.0f%%", price * 100)
    }

    /// 0.523 -> "52.3¢"
    static func cents(_ price: Double?) -> String {
        guard let price else { return "—" }
        return String(format: "%.1f¢", price * 100)
    }

    /// 価格差（確率ポイント）: 0.031 -> "+3.1pt"
    static func points(_ delta: Double?) -> String {
        guard let delta else { return "—" }
        return String(format: "%+.1fpt", delta * 100)
    }

    static func windowLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分" }
        if minutes % 60 == 0 { return "\(minutes / 60)時間" }
        return "\(minutes)分"
    }
}
