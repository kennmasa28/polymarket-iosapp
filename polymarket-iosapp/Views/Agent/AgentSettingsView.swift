//
//  AgentSettingsView.swift
//  polymarket-iosapp
//
//  AI エージェント（自動売買）の設定。OpenAI の API キー、モード、強気度、金額・価格の上限など。
//

import SwiftUI

struct AgentSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(TradingAgent.self) private var agent
    @Environment(AlertStore.self) private var alerts
    @Environment(AppServices.self) private var services

    @State private var apiKeyInput = ""
    @State private var hasAPIKey = OpenAIClient.loadAPIKey() != nil
    @State private var keyError: String?
    @State private var showLiveConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                if hasAPIKey {
                    LabeledContent("API キー", value: "設定済み")
                    Button("API キーを削除", role: .destructive) {
                        try? KeychainItem.openAIKey.delete()
                        hasAPIKey = false
                    }
                } else {
                    SecureField("sk-…", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("保存") { saveKey() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let keyError {
                    Text(keyError).font(.footnote).foregroundStyle(.red)
                }
                LabeledContent("モデル") {
                    TextField("モデル名", text: $settings.value.agent.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("OpenAI")
            } footer: {
                Text("API キーはこの端末の Keychain に保存します。判断のたびに OpenAI の API 料金がかかります。")
            }

            Section {
                Toggle("AI による自動売買", isOn: $settings.value.agent.enabled)
                    .disabled(!hasAPIKey)
                Picker("モード", selection: Binding(
                    get: { settings.value.agent.mode },
                    set: { newValue in
                        if newValue == .live { showLiveConfirmation = true } else { settings.value.agent.mode = .paper }
                    }
                )) {
                    ForEach(AgentMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("ウォレット", value: services.trading.state.label)
                LabeledContent("今日の購入額", value: String(
                    format: "$%.2f / $%.2f", agent.spentToday, settings.value.agent.dailyBudgetUSDC))
            } header: {
                Text("自動売買")
            } footer: {
                Text("急変アラートが出ると AI が購入・売却・キープを判断します。シミュレーションでは見積もりだけを記録します。実取引はアプリを開いてウォレットのロックを解除している間だけ注文し、ロック中は「未実行」として通知します。")
            }

            Section {
                VStack(alignment: .leading) {
                    LabeledContent("強気度", value: "\(settings.value.agent.aggressivenessLabel)（\(Int(settings.value.agent.aggressiveness * 100))）")
                    Slider(value: $settings.value.agent.aggressiveness, in: 0...1, step: 0.05) {
                        Text("強気度")
                    } minimumValueLabel: {
                        Text("慎重").font(.caption)
                    } maximumValueLabel: {
                        Text("強気").font(.caption)
                    }
                }
                VStack(alignment: .leading) {
                    LabeledContent("実行する確信度の下限", value: "\(Int(settings.value.agent.minConfidence * 100))%")
                    Slider(value: $settings.value.agent.minConfidence, in: 0.3...0.95, step: 0.05)
                }
                Toggle("購入を許可", isOn: $settings.value.agent.allowBuy)
                Toggle("売却を許可", isOn: $settings.value.agent.allowSell)
            } header: {
                Text("判断")
            } footer: {
                Text("AI の確信度が下限未満の判断は実行しません。")
            }

            Section {
                currencyField("1回の購入上限 ($)", value: $settings.value.agent.maxTradeUSDC)
                currencyField("1日の購入上限 ($)", value: $settings.value.agent.dailyBudgetUSDC)
                centsStepper("購入してよい最低価格", value: $settings.value.agent.minBuyPrice, range: 0.01...0.5)
                centsStepper("購入してよい最高価格", value: $settings.value.agent.maxBuyPrice, range: 0.5...0.99)
                centsStepper("許容する価格のずれ", value: $settings.value.agent.maxSlippage, range: 0.005...0.1, step: 0.005)
            } header: {
                Text("金額と価格")
            } footer: {
                Text("AI の提案がこれらを超えた場合は、上限まで減らすか見送ります。成行注文は板の約定見込み価格が「現在価格 ± 許容ずれ」を超えると見送ります。")
            }

            Section {
                ForEach(AlertKind.allCases, id: \.self) { kind in
                    Toggle(kind.label, isOn: Binding(
                        get: { settings.value.agent.triggerKinds.contains(kind) },
                        set: { isOn in
                            if isOn {
                                settings.value.agent.triggerKinds.insert(kind)
                            } else {
                                settings.value.agent.triggerKinds.remove(kind)
                            }
                        }))
                }
                Stepper(value: $settings.value.agent.maxEvaluationsPerCycle, in: 1...10) {
                    LabeledContent("1回の巡回で判断する件数", value: "\(settings.value.agent.maxEvaluationsPerCycle)件")
                }
                Stepper(value: $settings.value.agent.marketCooldownMinutes, in: 15...1440, step: 15) {
                    LabeledContent("同じマーケットの再判断", value: "\(settings.value.agent.marketCooldownMinutes)分後")
                }
            } header: {
                Text("判断のきっかけ")
            }

            Section {
                TextEditor(text: $settings.value.agent.instructions)
                    .frame(minHeight: 100)
            } header: {
                Text("投資方針（AI への追加の指示）")
            } footer: {
                Text("例: 「政治のマーケットは避ける」「終了まで1週間以内のものだけ」「急落時の買い戻しを狙う」")
            }

            Section {
                if let latest = alerts.records.first {
                    Button {
                        Task { await agent.evaluate(marketId: latest.marketId, trigger: "テスト: \(latest.kind.label) \(latest.summary)") }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("最新のアラートで判断を試す")
                                Text(latest.question).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if agent.isEvaluating { ProgressView() }
                        }
                    }
                    .disabled(!hasAPIKey || agent.isEvaluating)
                }
                if let error = agent.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                }
                NavigationLink {
                    AgentLogView()
                } label: {
                    LabeledContent("判断ログ", value: "\(agent.log.count)件")
                }
            } footer: {
                Text("テストも現在のモードで実行します（実取引モードでは実際に注文される可能性があります）。")
            }
        }
        .navigationTitle("AI エージェント")
        .confirmationDialog(
            "実取引モードにしますか？", isPresented: $showLiveConfirmation, titleVisibility: .visible
        ) {
            Button("実取引にする", role: .destructive) { settings.value.agent.mode = .live }
        } message: {
            Text(String(
                format: "AI の判断で実際の資金が使われます（1回 $%.2f、1日 $%.2f まで）。損失が出る可能性があります。",
                settings.value.agent.maxTradeUSDC, settings.value.agent.dailyBudgetUSDC))
        }
    }

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainItem.openAIKey.save(Data(key.utf8))
            apiKeyInput = ""
            hasAPIKey = true
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }

    private func currencyField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func centsStepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.01) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: String(format: "%.1f¢", value.wrappedValue * 100))
        }
    }
}

struct AgentLogView: View {
    @Environment(TradingAgent.self) private var agent
    @Environment(AppRouter.self) private var router

    var body: some View {
        List(agent.log) { entry in
            Button {
                router.openMarket(id: entry.marketId)
            } label: {
                AgentLogRow(entry: entry)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if agent.log.isEmpty {
                ContentUnavailableView("判断ログはありません", systemImage: "brain")
            }
        }
        .navigationTitle("判断ログ")
        .toolbar {
            Button("消去", role: .destructive) { agent.clearLog() }
                .disabled(agent.log.isEmpty)
        }
    }
}

private struct AgentLogRow: View {
    let entry: AgentLogEntry

    private var color: Color {
        switch entry.action {
        case .buy: .green
        case .sell: .orange
        case .hold: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(entry.action.label)\(entry.outcome.map { " \($0)" } ?? "")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Text(entry.status.label)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                if entry.mode == .paper {
                    Text("シミュレーション").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.date.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.question).font(.subheadline).lineLimit(2)
            if let usdc = entry.usdc, let shares = entry.shares, let price = entry.price {
                Text(String(format: "%.2f 株 @ %.1f¢（$%.2f）· 確信度 %.0f%%", shares, price * 100, usdc, entry.confidence * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: "確信度 %.0f%%", entry.confidence * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.reasoning).font(.footnote)
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.trigger).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
