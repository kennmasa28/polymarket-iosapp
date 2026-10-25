//
//  PortfolioView.swift
//  polymarket-iosapp
//
//  USDC 残高・保有ポジション・未約定注文（取消可）。
//

import SwiftUI

struct PortfolioView: View {
    @Environment(AppServices.self) private var services

    @State private var balance: Double?
    @State private var positions: [Position] = []
    @State private var orders: [OpenOrder] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !services.trading.state.canTrade {
                    Section {
                        Button {
                            Task {
                                do {
                                    try await services.trading.unlock()
                                    await load()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("ロック解除して残高・注文を表示", systemImage: "faceid")
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let balance {
                    Section("残高") {
                        LabeledContent("USDC", value: String(format: "$%.2f", balance))
                    }
                }

                Section("ポジション") {
                    if positions.isEmpty {
                        Text(isLoading ? "読み込み中…" : "ポジションはありません").foregroundStyle(.secondary)
                    }
                    ForEach(positions) { position in
                        PositionRow(position: position)
                    }
                }

                if services.trading.state.canTrade {
                    Section("未約定の注文") {
                        if orders.isEmpty {
                            Text("未約定の注文はありません").foregroundStyle(.secondary)
                        }
                        ForEach(orders) { order in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(order.side.label) \(order.outcome) @ \(Fmt.cents(order.price))")
                                    .font(.subheadline)
                                Text(String(format: "%.2f / %.2f 株 約定", order.filledSize, order.size))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("取消", role: .destructive) {
                                    Task { await cancel(order) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("ポートフォリオ")
            .refreshable { await load() }
            .task(id: services.trading.state) { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            positions = try await services.trading.positions()
                .sorted { ($0.currentValue ?? 0) > ($1.currentValue ?? 0) }
            if services.trading.state.canTrade {
                balance = try await services.trading.collateralBalance()
                orders = try await services.trading.openOrders()
            } else {
                balance = nil
                orders = []
            }
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    private func cancel(_ order: OpenOrder) async {
        do {
            try await services.trading.cancelOrder(id: order.id)
            orders.removeAll { $0.id == order.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PositionRow: View {
    let position: Position

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.marketQuestion).font(.subheadline).lineLimit(2)
                Text("\(position.outcome) · \(String(format: "%.2f", position.size))株 @ 平均\(Fmt.cents(position.averagePrice))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", position.currentValue ?? 0)).font(.subheadline.monospacedDigit())
                if let pnl = position.pnl {
                    Text(String(format: "%+.2f", pnl))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(pnl >= 0 ? Color.green : Color.red)
                }
            }
        }
    }
}
