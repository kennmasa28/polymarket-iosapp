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
        WatchSessionReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            // デジタルクラウン/縦スワイプでお気に入りとトレンドを切り替える
            TabView {
                FavoritesView()
                TrendingView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
