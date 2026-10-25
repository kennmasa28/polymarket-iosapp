//
//  AlertsView.swift
//  polymarket-iosapp
//

import SwiftUI

struct AlertsView: View {
    @Environment(AlertStore.self) private var alerts
    @Environment(AppRouter.self) private var router

    @State private var kindFilter: AlertKind?

    private var filtered: [AlertRecord] {
        guard let kindFilter else { return alerts.records }
        return alerts.records.filter { $0.kind == kindFilter }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { record in
                    Button {
                        alerts.markRead(id: record.id)
                        router.openMarket(id: record.marketId)
                    } label: {
                        AlertRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    // フィルタ表示中は元配列のインデックスに変換して削除
                    let ids = Set(offsets.map { filtered[$0].id })
                    alerts.remove(at: IndexSet(alerts.records.indices.filter { ids.contains(alerts.records[$0].id) }))
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "アラートはありません", systemImage: "bell.slash",
                        description: Text("監視条件に一致するマーケットで急変があるとここに表示されます"))
                }
            }
            .navigationTitle("アラート")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("種類", selection: $kindFilter) {
                            Text("すべて").tag(AlertKind?.none)
                            ForEach(AlertKind.allCases, id: \.self) { kind in
                                Label(kind.label, systemImage: kind.systemImage).tag(AlertKind?.some(kind))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("すべて既読") { alerts.markAllRead() }
                        .disabled(alerts.unreadCount == 0)
                }
            }
        }
    }
}

struct AlertRow: View {
    let record: AlertRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.systemImage)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.kind.label).font(.caption.weight(.semibold)).foregroundStyle(color)
                    Text(record.conditionName).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(record.date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(record.question)
                    .font(.subheadline.weight(record.isRead ? .regular : .semibold))
                    .lineLimit(2)
                Text(record.summary).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch record.kind {
        case .priceMove: .orange
        case .volumeSurge: .blue
        case .traderSurge: .purple
        }
    }
}
