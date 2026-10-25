//
//  SettingsView.swift
//  polymarket-iosapp
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AlertStore.self) private var alerts
    @Environment(AppServices.self) private var services
    @Environment(MarketMonitor.self) private var monitor

    @State private var newCondition: WatchCondition?
    @State private var showClearConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    ForEach(settings.value.conditions) { condition in
                        NavigationLink {
                            ConditionEditorView(condition: condition, isNew: false) { settings.upsert($0) }
                        } label: {
                            ConditionRow(condition: condition) { enabled in
                                settings.setEnabled(enabled, for: condition.id)
                            }
                        }
                    }
                    .onDelete { settings.removeConditions(at: $0) }
                    .onMove { settings.value.conditions.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        newCondition = WatchCondition(name: "新しい条件")
                    } label: {
                        Label("条件を追加", systemImage: "plus.circle")
                    }
                } header: {
                    Text("監視条件")
                } footer: {
                    Text("有効な条件に一致するマーケットをすべて定期的にチェックし、急変を通知します。")
                }

                Section {
                    Toggle("定期チェック", isOn: $settings.value.monitoringEnabled)
                    Picker("チェック間隔", selection: $settings.value.pollIntervalMinutes) {
                        ForEach(AppSettings.pollIntervalChoices, id: \.self) { Text("\($0)分").tag($0) }
                    }
                    Stepper(value: $settings.value.cooldownMinutes, in: 5...1440, step: 5) {
                        LabeledContent("再通知までの間隔", value: "\(settings.value.cooldownMinutes)分")
                    }
                    Stepper(value: $settings.value.maxEventsPerCondition, in: 50...2000, step: 50) {
                        LabeledContent("取得イベント上限 / タグ", value: "\(settings.value.maxEventsPerCondition)")
                    }
                    Stepper(value: $settings.value.maxTraderChecksPerCycle, in: 0...200, step: 5) {
                        LabeledContent("参加者チェック上限 / 回", value: "\(settings.value.maxTraderChecksPerCycle)")
                    }
                } header: {
                    Text("モニタリング")
                } footer: {
                    Text("アプリ表示中は指定間隔で実行します。バックグラウンドでは iOS が実行タイミングを決めるため、最短でも15分程度の間隔になり、保証もされません。")
                }

                Section {
                    if settings.value.favorites.isEmpty {
                        Text("マーケット詳細の ☆ でお気に入りに追加できます")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(settings.value.favorites) { favorite in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.title)
                            Text(favorite.question).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .onDelete { settings.removeFavorites(at: $0) }
                    .onMove { settings.moveFavorites(from: $0, to: $1) }
                } header: {
                    Text("お気に入り（Apple Watch）")
                } footer: {
                    Text("Apple Watch の文字盤を編集し、コンプリケーションで「Polymarket」を選ぶと価格と24時間の変化を表示できます。先頭のお気に入りが既定で表示されます。")
                }

                Section("通知") {
                    Toggle("急変を通知する", isOn: $settings.value.notificationsEnabled)
                    Button("テスト通知を送信") {
                        Task {
                            await NotificationService.requestAuthorization()
                            await NotificationService.sendTest()
                        }
                    }
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("iOS の通知設定を開く", destination: url)
                    }
                }

                Section {
                    NavigationLink {
                        WalletSettingsView()
                    } label: {
                        LabeledContent("ウォレット", value: services.trading.state.label)
                    }
                } header: {
                    Text("取引")
                } footer: {
                    Text("今後、MetaMask の秘密鍵を端末内に保存して売買できるようにする予定です。")
                }

                Section("データ") {
                    Button("アラート履歴を削除", role: .destructive) { alerts.removeAll() }
                    Button("価格履歴（スナップショット）を削除", role: .destructive) {
                        showClearConfirmation = true
                    }
                }

                Section("API") {
                    LabeledContent("Gamma", value: GammaAPI.baseURL.host() ?? "")
                    LabeledContent("CLOB", value: ClobAPI.baseURL.host() ?? "")
                    LabeledContent("Data", value: DataAPI.baseURL.host() ?? "")
                }
            }
            .navigationTitle("設定")
            .toolbar { EditButton() }
            .sheet(item: $newCondition) { condition in
                NavigationStack {
                    ConditionEditorView(condition: condition, isNew: true) { settings.upsert($0) }
                }
            }
            .confirmationDialog("価格履歴を削除しますか？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) { AppContainer.shared.snapshots.removeAll() }
            } message: {
                Text("急変検知の基準となる履歴が消えるため、しばらく検知精度が下がります。")
            }
        }
    }
}

private struct ConditionRow: View {
    let condition: WatchCondition
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(condition.name)
                Text(condition.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { condition.isEnabled }, set: onToggle))
                .labelsHidden()
        }
    }
}
