//
//  TradePanel.swift
//  polymarket-iosapp
//
//  マーケット詳細の売買 UI。`TradingService` の状態に応じて
//  未接続 → 設定への案内 / ロック中 → ロック解除 / 接続済み → 注文チケット を出し分ける。
//

import SwiftUI

struct OrderDraft: Identifiable {
    let id = UUID()
    let market: PMMarket
    let outcomeIndex: Int
    var side: OrderSide = .buy

    var outcomeName: String { market.outcomes.indices.contains(outcomeIndex) ? market.outcomes[outcomeIndex] : "?" }
    var tokenId: String? { market.clobTokenIds.indices.contains(outcomeIndex) ? market.clobTokenIds[outcomeIndex] : nil }
    var price: Double? { market.outcomePrices.indices.contains(outcomeIndex) ? market.outcomePrices[outcomeIndex] : nil }
}

struct TradePanel: View {
    let market: PMMarket

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var draft: OrderDraft?
    @State private var errorMessage: String?
    @State private var isUnlocking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(market.outcomes.prefix(2).enumerated()), id: \.offset) { index, outcome in
                    Button {
                        Task { await open(outcomeIndex: index) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(outcome) を取引").font(.subheadline.weight(.semibold))
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
            .disabled(!market.isTradable || !services.trading.state.isConfigured || isUnlocking)

            switch services.trading.state {
            case .notConfigured:
                Button {
                    router.selectedTab = .settings
                } label: {
                    Label("取引するには 設定 › ウォレット で接続してください", systemImage: "lock")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            case .locked:
                Label("ボタンを押すと Face ID / パスコードでロック解除します", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .ready:
                EmptyView()
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(item: $draft) { draft in
            NavigationStack { OrderTicketView(draft: draft) }
                .presentationDetents([.large])
        }
    }

    private func open(outcomeIndex: Int) async {
        if !services.trading.state.canTrade {
            isUnlocking = true
            defer { isUnlocking = false }
            do {
                try await services.trading.unlock()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        errorMessage = nil
        draft = OrderDraft(market: market, outcomeIndex: outcomeIndex)
    }
}

/// 発注チケット。署名・送信は `TradingService.placeOrder` の責務
struct OrderTicketView: View {
    let draft: OrderDraft

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var side: OrderSide
    @State private var orderType: OrderType = .gtc
    @State private var priceCents: Double
    @State private var shares: Double = 10
    @State private var balance: Double?
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var resultMessage: String?
    @State private var succeeded = false

    init(draft: OrderDraft) {
        self.draft = draft
        _side = State(initialValue: draft.side)
        _priceCents = State(initialValue: min(max(((draft.price ?? 0.5) * 100).rounded(), 1), 99))
    }

    private var price: Double { priceCents / 100 }
    private var estimatedCost: Double { price * shares }

    private var summary: String {
        "\(draft.outcomeName) を \(String(format: "%.2f", shares))株 \(side.label)（\(orderType.label) \(Fmt.cents(price))、約 $\(String(format: "%.2f", estimatedCost))）"
    }

    var body: some View {
        Form {
            Section {
                Text(draft.market.question).font(.subheadline)
                LabeledContent("アウトカム", value: draft.outcomeName)
                LabeledContent("現在価格", value: Fmt.cents(draft.price))
                if let balance {
                    LabeledContent("USDC 残高", value: String(format: "$%.2f", balance))
                }
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
                    LabeledContent(orderType == .gtc ? "指値" : (side == .buy ? "上限価格" : "下限価格")) {
                        Text(String(format: "%.0f¢", priceCents)).monospacedDigit()
                    }
                }
                LabeledContent("株数") {
                    TextField("株数", value: $shares, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(side == .buy ? "支払額（概算）" : "受取額（概算）", value: String(format: "$%.2f", estimatedCost))
                if side == .buy {
                    LabeledContent("的中時の受取", value: String(format: "$%.2f", shares))
                }
            } footer: {
                Text(orderType == .gtc
                    ? "指定価格で板に注文を出し、約定するまで残ります。"
                    : "指定価格より不利にならない範囲で即時に全量約定させ、できなければ取り消されます。")
            }

            if let resultMessage {
                Section {
                    Label(resultMessage, systemImage: succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(succeeded ? Color.green : Color.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    showConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text("注文内容を確認") }
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
        .confirmationDialog("この内容で注文しますか？", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("注文する（\(side.label)）") { Task { await submit() } }
        } message: {
            Text(summary)
        }
        .task {
            balance = try? await services.trading.collateralBalance()
        }
    }

    private func submit() async {
        guard let tokenId = draft.tokenId else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await services.trading.placeOrder(OrderRequest(
                tokenId: tokenId, side: side, price: price, size: shares, type: orderType))
            succeeded = true
            resultMessage = "注文を受け付けました（\(receipt.status)）"
            balance = try? await services.trading.collateralBalance()
        } catch {
            succeeded = false
            resultMessage = error.localizedDescription
        }
    }
}
