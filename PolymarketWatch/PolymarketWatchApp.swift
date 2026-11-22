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
    init() {
        // 通信キャッシュがメモリを圧迫しないよう小さくする（Watch はメモリ上限が厳しい）
        URLCache.shared = URLCache(memoryCapacity: 512 * 1024, diskCapacity: 5 * 1024 * 1024)
        WatchSessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            // NavigationStack + List の単純な構成にする。縦ページ TabView の各ページに NavigationStack や
            // ツールバーを置く構成は watchOS でレイアウト計算が終わらず、起動時に固まって強制終了していた
            FavoritesView()
        }
    }
}
