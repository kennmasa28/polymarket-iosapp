//
//  WatchComponents.swift
//  PolymarketWatch
//

import ImageIO
import SwiftUI
import UIKit

/// 詳細画面への遷移先
struct WatchMarketRoute: Hashable {
    let marketId: String
    let title: String
}

/// マーケット/イベントのアイコン画像（読み込み前はグレーの角丸）。
/// AsyncImage は元画像をフルサイズで展開してメモリの少ない Watch では落ちる原因になるため、
/// 表示サイズに縮小したサムネイルだけを作ってキャッシュする
struct MarketIcon: View {
    let urlString: String?
    var size: CGFloat = 28

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        .task(id: urlString) {
            image = await ThumbnailLoader.shared.thumbnail(for: urlString, maxPixelSize: Int(size * 2))
        }
    }
}

/// 縮小済みサムネイルの読み込みとキャッシュ（件数上限つき）
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private let limit = 40

    func thumbnail(for urlString: String?, maxPixelSize: Int) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let key = "\(maxPixelSize)|\(urlString)"
        if let cached = cache[key] { return cached }
        guard let result = try? await URLSession.shared.data(from: url),
              let image = Self.downsample(result.0, maxPixelSize: maxPixelSize)
        else { return nil }
        cache[key] = image
        order.append(key)
        if order.count > limit {
            cache[order.removeFirst()] = nil
        }
        return image
    }

    /// フル解像度で展開せずに縮小画像を作る
    private static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
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
