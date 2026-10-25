//
//  TradePanel.swift
//  polymarket-iosapp
//
//  マーケット詳細の売買 UI。現在は `TradingService.state` が未接続のため無効表示。
//  ウォレット接続を実装すれば、この UI のまま発注できるようになる。
//

import SwiftUI

struct OrderDraft: Identifiable {
    let id = UUID()
    let market: PMMarket
    let outcomeIndex: Int

    var outcomeName: String { market.outcomes.indices.contains(outcomeIndex) ? market.outcomes[outcomeIndex] : "?" }
    var tokenId: String? { market.clobTokenIds.indices.contains(outcomeIndex) ? market.clobTokenIds[outcomeIndex] : nil }
    var price: Double? { market.outcomePrices.indices.contains(outcomeIndex) ? market.outcomePrices[outcomeIndex] : nil }
}

struct TradePanel: View {
    let market: PMMarket

    @Environment(AppServices.self) private var services
    @State private var draft: OrderDraft?

    private var canTrade: Bool { services.trading.state.canTrade && market.isTradable }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(market.outcomes.prefix(2).enumerated()), id: \.offset) { index, outcome in
                    Button {
                        draft = OrderDraft(market: market, outcomeIndex: index)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(outcome) を買う").font(.subheadline.weight(.semibold))
                            Text(Fmt.cents(market.outcomePrices.indices.contains(index) ? market.outcomePrices[index] : nil))
                                .font(.caption.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(index == 0 ? .green : .red)
                }
            }
            .disabled(!canTrade)

            if !services.trading.state.canTrade {
                Label("取引機能は未接続です（設定 › ウォレット）", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $draft) { draft in
            NavigationStack { OrderTicketView(draft: draft) }
                .presentationDetents([.medium, .large])
        }
    }
}

/// 発注チケット。`TradingService.placeOrder` に `OrderRequest` を渡すだけで、署名等はサービス側の責務
struct OrderTicketView: View {
    let draft: OrderDraft

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var side: OrderSide = .buy
    @State private var orderType: OrderType = .gtc
    @State private var priceCents: Double
    @State private var shares: Double = 10
    @State private var isSubmitting = false
    @State private var resultMessage: String?

    init(draft: OrderDraft) {
        self.draft = draft
        _priceCents = State(initialValue: ((draft.price ?? 0.5) * 100).rounded())
    }

    private var estimatedCost: Double { priceCents / 100 * shares }

    var body: some View {
        Form {
            Section {
                Text(draft.market.question).font(.subheadline)
                LabeledContent("アウトカム", value: draft.outcomeName)
            }
            Section {
                Picker("売買", selection: $side) {
                    ForEach(OrderSide.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("注文種別", selection: $orderType) {
                    ForEach(OrderType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper(value: $priceCents, in: 1...99, step: 1) {
                    LabeledContent("指値", value: "\(Int(priceCents))¢")
                }
                LabeledContent("株数") {
                    TextField("株数", value: $shares, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("概算金額", value: String(format: "$%.2f", estimatedCost))
                LabeledContent("的中時の受取", value: String(format: "$%.2f", shares))
            }
            if let resultMessage {
                Section { Text(resultMessage).font(.footnote) }
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text("注文を確定") }
                        Spacer()
                    }
                }
                .disabled(isSubmitting || shares <= 0 || draft.tokenId == nil || !services.trading.state.canTrade)
            }
        }
        .navigationTitle("注文")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
        }
    }

    private func submit() async {
        guard let tokenId = draft.tokenId else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await services.trading.placeOrder(OrderRequest(
                tokenId: tokenId, side: side, price: priceCents / 100, size: shares, type: orderType))
            resultMessage = "注文を受け付けました（\(receipt.status)）"
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}
