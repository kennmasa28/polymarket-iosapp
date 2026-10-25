//
//  ConditionEditorView.swift
//  polymarket-iosapp
//

import SwiftUI

struct ConditionEditorView: View {
    let isNew: Bool
    let onSave: (WatchCondition) -> Void

    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WatchCondition
    @State private var includeText: String
    @State private var excludeText: String
    @State private var previewText: String?
    @State private var isPreviewing = false

    init(condition: WatchCondition, isNew: Bool, onSave: @escaping (WatchCondition) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: condition)
        _includeText = State(initialValue: condition.keywords.joined(separator: ", "))
        _excludeText = State(initialValue: condition.excludedKeywords.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section("基本") {
                TextField("条件名", text: $draft.name)
                Toggle("有効", isOn: $draft.isEnabled)
            }

            Section {
                ForEach(draft.tags) { tag in
                    Label(tag.label, systemImage: "tag")
                }
                .onDelete { draft.tags.remove(atOffsets: $0) }
                NavigationLink {
                    TagPickerView(selected: $draft.tags)
                } label: {
                    Label("タグを選択", systemImage: "plus")
                }
            } header: {
                Text("タグ")
            } footer: {
                Text("いずれかのタグに属するイベントが対象です。未指定の場合は全カテゴリの出来高上位が対象になります。")
            }

            Section {
                TextField("含む（カンマ区切り）", text: $includeText)
                    .textInputAutocapitalization(.never)
                TextField("除外（カンマ区切り）", text: $excludeText)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("キーワード")
            } footer: {
                Text("イベント名・マーケットの質問文に対して大文字小文字を区別せずに照合します（英語）。")
            }

            Section("フィルタ") {
                numberField("24h出来高の下限 ($)", value: $draft.minVolume24h)
                numberField("流動性の下限 ($)", value: $draft.minLiquidity)
            }

            Section {
                Picker("検知ウィンドウ", selection: $draft.rules.windowMinutes) {
                    ForEach(AlertRules.windowChoices, id: \.self) { Text(Fmt.windowLabel(minutes: $0)).tag($0) }
                }
            } header: {
                Text("アラート")
            } footer: {
                Text("直近この時間内の変化を、各ルールで判定します。")
            }

            Section {
                Toggle("価格急変", isOn: $draft.rules.priceChangeEnabled)
                if draft.rules.priceChangeEnabled {
                    VStack(alignment: .leading) {
                        LabeledContent("閾値", value: String(format: "±%.0fpt", draft.rules.priceChangeThreshold * 100))
                        Slider(value: $draft.rules.priceChangeThreshold, in: 0.01...0.30, step: 0.01)
                    }
                }
            } footer: {
                Text("Yes 価格（確率）がウィンドウ内でこのポイント以上動いたら通知します。")
            }

            Section {
                Toggle("出来高急増", isOn: $draft.rules.volumeSurgeEnabled)
                if draft.rules.volumeSurgeEnabled {
                    Stepper(value: $draft.rules.volumeSurgeMultiplier, in: 1.5...20, step: 0.5) {
                        LabeledContent("倍率", value: String(format: "%.1f倍", draft.rules.volumeSurgeMultiplier))
                    }
                    numberField("最低出来高 ($)", value: $draft.rules.minWindowVolume)
                }
            } footer: {
                Text("ウィンドウ内の出来高が、24時間平均ペースの指定倍率以上になったら通知します。")
            }

            Section {
                Toggle("参加者急増", isOn: $draft.rules.traderSurgeEnabled)
                if draft.rules.traderSurgeEnabled {
                    Stepper(value: $draft.rules.traderSurgeMultiplier, in: 1.5...20, step: 0.5) {
                        LabeledContent("倍率", value: String(format: "%.1f倍", draft.rules.traderSurgeMultiplier))
                    }
                    Stepper(value: $draft.rules.minRecentTraders, in: 5...500, step: 5) {
                        LabeledContent("最低人数", value: "\(draft.rules.minRecentTraders)人")
                    }
                }
            } footer: {
                Text("Data API の約定履歴からユニーク取引者数を数え、直前のウィンドウと比較します。API 呼び出しが増えるため、出来高上位から設定の上限件数までを対象にします。")
            }

            Section {
                Button {
                    Task { await preview() }
                } label: {
                    HStack {
                        Text("一致するマーケットを確認")
                        Spacer()
                        if isPreviewing { ProgressView() }
                    }
                }
                .disabled(isPreviewing)
                if let previewText {
                    Text(previewText).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isNew ? "新しい条件" : "条件を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(finalized())
                    dismiss()
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func finalized() -> WatchCondition {
        var condition = draft
        condition.name = condition.name.trimmingCharacters(in: .whitespaces)
        condition.keywords = Self.splitKeywords(includeText)
        condition.excludedKeywords = Self.splitKeywords(excludeText)
        return condition
    }

    private static func splitKeywords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func preview() async {
        isPreviewing = true
        defer { isPreviewing = false }
        let condition = finalized()
        do {
            var cache: [String: [PMEvent]] = [:]
            let events = try await EventFetcher(gamma: services.gamma).events(
                for: condition, maxEventsPerTag: settings.value.maxEventsPerCondition, cache: &cache)
            let markets = ConditionMatcher.monitoredMarkets(in: events, condition: condition)
            let examples = markets
                .sorted { ($0.market.volume24hr ?? 0) > ($1.market.volume24hr ?? 0) }
                .prefix(3)
                .map { "・\($0.market.question)" }
            previewText = (["\(events.count)イベント中 \(markets.count)マーケットが一致"] + examples)
                .joined(separator: "\n")
        } catch {
            if !error.isCancellation { previewText = error.localizedDescription }
        }
    }
}
