//
//  WalletSettingsView.swift
//  polymarket-iosapp
//
//  ウォレット接続（秘密鍵のインポート）・ロック・接続解除。
//

import SwiftUI

struct WalletSettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Form {
            if let configuration = services.wallet.configuration {
                ConnectedWalletSections(configuration: configuration)
            } else {
                ConnectWalletSections()
            }
        }
        .navigationTitle("ウォレット")
    }
}

private struct ConnectWalletSections: View {
    @Environment(AppServices.self) private var services

    @State private var privateKey = ""
    @State private var funderAddress = ""
    @State private var acknowledged = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// 入力中の鍵とアドレスからウォレット種別を判定して表示する
    private var detectedType: String? {
        guard let signer = try? EthereumSigner(privateKeyHex: privateKey) else { return nil }
        let funder = funderAddress.trimmingCharacters(in: .whitespaces)
        if funder.isEmpty { return WalletSignatureType.eoa.label }
        guard EthereumAddress.isValid(funder) else { return "アドレスの形式が正しくありません" }
        guard let type = try? WalletDerivation.detect(signer: signer.address, wallet: funder) else {
            return "この秘密鍵のウォレットではありません"
        }
        return type.label
    }

    var body: some View {
        Section {
            SecureField("秘密鍵（0x…64桁）", text: $privateKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            TextField("資金保有アドレス（0x…）", text: $funderAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            if let detectedType {
                LabeledContent("ウォレットの種類", value: detectedType)
            }
        } header: {
            Text("MetaMask 秘密鍵と Polymarket のアドレス")
        } footer: {
            Text("資金保有アドレスには Polymarket の設定（またはプロフィール）に表示されるアカウントのアドレスを入力してください。種類（Safe・デポジットウォレット等）は自動判定します。空欄の場合は秘密鍵のアドレスで直接取引します。秘密鍵はこの端末の Keychain（パスコード必須・この端末のみ）に保存され、使用時に Face ID / パスコードを要求します。署名は端末内で行い、秘密鍵が外部へ送信されることはありません。")
        }

        Section {
            Toggle("実際の資金で取引されることを理解しました", isOn: $acknowledged)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Text("保存して接続")
                    Spacer()
                    if isConnecting { ProgressView() }
                }
            }
            .disabled(!acknowledged || privateKey.isEmpty || isConnecting)
        } footer: {
            Text("取引用に、専用の少額ウォレットの利用をおすすめします。Polymarket の利用規約と、お住まいの地域での利用可否を確認してください。")
        }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await services.wallet.connect(privateKey: privateKey, funderAddress: funderAddress)
            privateKey = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ConnectedWalletSections: View {
    let configuration: WalletConfiguration

    @Environment(AppServices.self) private var services
    @State private var balance: Double?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showDisconnectConfirmation = false

    var body: some View {
        Section("状態") {
            LabeledContent("ウォレット", value: services.wallet.state.label)
            LabeledContent("種類", value: configuration.signatureType.label)
            if let balance {
                LabeledContent("USDC 残高", value: String(format: "$%.2f", balance))
            }
        }

        Section("アドレス") {
            AddressRow(title: "署名者", address: configuration.signerAddress)
            if configuration.funderAddress != configuration.signerAddress {
                AddressRow(title: "資金保有", address: configuration.funderAddress)
            }
        }

        Section {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if services.wallet.state.canTrade {
                Button("残高を更新") { Task { await loadBalance() } }
                    .disabled(isWorking)
                Button("ロックする") {
                    services.wallet.lock()
                    balance = nil
                }
            } else {
                Button {
                    Task { await unlock() }
                } label: {
                    Label("ロック解除（Face ID / パスコード）", systemImage: "faceid")
                }
                .disabled(isWorking)
            }
        } footer: {
            Text("アプリがバックグラウンドに移ると自動でロックされます。")
        }

        Section {
            Button("接続を解除して秘密鍵を削除", role: .destructive) {
                showDisconnectConfirmation = true
            }
        }
        .confirmationDialog(
            "秘密鍵をこの端末から削除しますか？", isPresented: $showDisconnectConfirmation, titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                do {
                    try services.wallet.disconnect()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("ウォレット自体や資金には影響しません。再度取引するには秘密鍵の入力が必要です。")
        }
        .task(id: services.wallet.state) {
            if services.wallet.state.canTrade { await loadBalance() }
        }
    }

    private func unlock() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.wallet.unlock()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadBalance() async {
        isWorking = true
        defer { isWorking = false }
        do {
            balance = try await services.wallet.collateralBalance()
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}

private struct AddressRow: View {
    let title: String
    let address: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(address)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        }
    }
}
