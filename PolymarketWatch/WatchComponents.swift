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

/// 一覧から開く画面
enum WatchScreen: Hashable {
    case trending
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

/// 縮小済みサムネイルの読み込みとキャッシュ。メモリの少ない Watch 向けに
/// - 画像はファイルにダウンロードし、ImageIO でディスクから直接縮小する（元データをメモリに載せない）
/// - URL キャッシュを使わない専用セッション、同時ダウンロードは 2 件まで
/// - 大きすぎる画像は読み込まない、キャッシュは件数上限つき
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private static let maxConcurrentDownloads = 2
    private static let maxDownloadBytes: Int64 = 2_000_000
    private static let cacheLimit = 30

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private var cache: [String: UIImage] = [:]
    private var order: [String] = []
    private var failed = Set<String>()
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func thumbnail(for urlString: String?, maxPixelSize: Int) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let key = "\(maxPixelSize)|\(urlString)"
        if let cached = cache[key] { return cached }
        if failed.contains(key) { return nil }

        await acquire()
        defer { release() }
        // 待っている間に別の呼び出しが読み込んでいれば再利用
        if let cached = cache[key] { return cached }
        if Task.isCancelled { return nil }

        guard let image = await download(url, maxPixelSize: maxPixelSize) else {
            failed.insert(key)
            return nil
        }
        cache[key] = image
        order.append(key)
        if order.count > Self.cacheLimit {
            cache[order.removeFirst()] = nil
        }
        return image
    }

    private func download(_ url: URL, maxPixelSize: Int) async -> UIImage? {
        guard let result = try? await session.download(from: url) else { return nil }
        let (fileURL, response) = result
        defer { try? FileManager.default.removeItem(at: fileURL) }
        if response.expectedContentLength > Self.maxDownloadBytes { return nil }
        if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int64,
           size > Self.maxDownloadBytes {
            return nil
        }
        return Self.downsample(fileURL, maxPixelSize: maxPixelSize)
    }

    private func acquire() async {
        if running < Self.maxConcurrentDownloads {
            running += 1
            return
        }
        // 枠が空くまで待つ（release で running を引き継ぐ）
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// フル解像度で展開せずに縮小画像を作る
    private static func downsample(_ fileURL: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else { return nil }
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

/// 確率を示す細いバー。リストの行ごとに GeometryReader を使うとレイアウト計算が重くなるので、
/// 幅に依存しない scaleEffect で塗りの長さを表す
struct ProbabilityBar: View {
    let value: Double
    var color: Color = .accentColor

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.15))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .scaleEffect(x: max(min(value, 1), 0.02), y: 1, anchor: .leading)
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
