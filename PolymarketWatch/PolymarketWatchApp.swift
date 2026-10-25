//
//  PolymarketWatchApp.swift
//  PolymarketWatch
//
//  iPhone でお気に入りに追加したマーケットの価格を表示する Watch アプリ。
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
            FavoritesView()
        }
    }
}
