//
//  WatchComponents.swift
//  PolymarketWatch
//

import SwiftUI

/// 詳細画面への遷移先
struct WatchMarketRoute: Hashable {
    let marketId: String
    let title: String
}

/// マーケット/イベントのアイコン画像（読み込み前はグレーの丸）
struct MarketIcon: View {
    let urlString: String?
    var size: CGFloat = 28

    var body: some View {
        AsyncImage(url: urlString.flatMap { URL(string: $0) }) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

/// 24 時間の変化（▲3.1 / ▼1.2）
struct ChangeText: View {
    let change: Double?

    var body: some View {
        if let change, abs(change) >= 0.0005 {
            HStack(spacing: 1) {
                Image(systemName: change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .imageScale(.small)
                Text(String(format: "%.1f", abs(change) * 100))
            }
            .foregroundStyle(change > 0 ? Color.green : Color.red)
        } else {
            Text("±0").foregroundStyle(.secondary)
        }
    }
}

/// 確率を示す細いバー
struct ProbabilityBar: View {
    let value: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * min(max(value, 0), 1), 3))
            }
        }
        .frame(height: 4)
    }
}

enum WatchFormat {
    static func usd(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch abs(value) {
        case 1_000_000...: return String(format: "$%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "$%.1fK", value / 1_000)
        default: return String(format: "$%.0f", value)
        }
    }

    static func percent(_ price: Double?) -> String {
        guard let price else { return "—" }
        return String(format: "%.0f%%", price * 100)
    }

    static func points(_ change: Double?) -> String {
        guard let change else { return "—" }
        return String(format: "%+.1f", change * 100)
    }
}
