//
//  PolymarketWatchApp.swift
//  PolymarketWatch
//
//  iPhone でお気に入りに追加したマーケットとトレンドを表示する Watch アプリ（詳細・グラフ付き）。
//  主な役割は、iPhone から届いたお気に入りを App Group に保存して文字盤のコンプリケーションに渡すこと。
//

import SwiftUI

@main
struct PolymarketWatchApp: App {
    @State private var page = 0

    init() {
        // 通信キャッシュがメモリを圧迫しないよう小さくする（Watch はメモリ上限が厳しい）
        URLCache.shared = URLCache(memoryCapacity: 512 * 1024, diskCapacity: 5 * 1024 * 1024)
        WatchSessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            // デジタルクラウン/縦スワイプでお気に入りとトレンドを切り替える。
            // トレンドは表示されたときに初めて読み込む（起動時のメモリと通信を抑える）
            TabView(selection: $page) {
                FavoritesView().tag(0)
                TrendingView(isActive: page == 1).tag(1)
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
