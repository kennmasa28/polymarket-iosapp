//
//  WalletSettingsView.swift
//  polymarket-iosapp
//
//  ウォレット接続画面（プレースホルダー）。
//  売買機能の実装時は、ここで秘密鍵を入力 → KeychainWalletKeyStore に保存 →
//  AppServices.trading を PolymarketTradingService に差し替える。
//

import SwiftUI

struct WalletSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var privateKey = ""

    var body: some View {
        Form {
            Section("状態") {
                LabeledContent("ウォレット", value: services.trading.state.label)
            }

            Section {
                SecureField("0x...（今後対応）", text: $privateKey)
                    .disabled(true)
                Button("保存して接続") {}
                    .disabled(true)
            } header: {
                Text("MetaMask 秘密鍵")
            } footer: {
                Text("秘密鍵はこの端末の Keychain（この端末のみ・ロック解除中のみ参照可）に保存し、注文の署名も端末内で行います。秘密鍵が端末外に送信されることはありません。")
            }

            Section("今後の対応予定") {
                Label("秘密鍵のインポートと Face ID でのロック", systemImage: "key")
                Label("Polymarket CLOB への指値・成行注文", systemImage: "arrow.left.arrow.right")
                Label("ポジション・注文一覧（ポートフォリオタブ）", systemImage: "briefcase")
            }
        }
        .navigationTitle("ウォレット")
    }
}

struct PortfolioView: View {
    @Environment(AppServices.self) private var services
    @State private var positions: [Position] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(positions) { position in
                VStack(alignment: .leading) {
                    Text(position.marketQuestion).font(.subheadline)
                    Text("\(position.outcome) · \(String(format: "%.2f", position.size))株 @ \(Fmt.cents(position.averagePrice))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if let errorMessage {
                    ContentUnavailableView("読み込めませんでした", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if positions.isEmpty {
                    ContentUnavailableView("ポジションはありません", systemImage: "briefcase")
                }
            }
            .navigationTitle("ポートフォリオ")
            .task {
                do {
                    positions = try await services.trading.positions()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
