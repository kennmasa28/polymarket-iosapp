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

    private enum Mode: String, CaseIterable {
        case market = "成行"
        case limit = "指値"
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var side: OrderSide
    @State private var mode: Mode = .market
    /// 成行 BUY: USDC / 成行 SELL・指値: 株数
    @State private var size: Double = 5
    @State private var limitPrice: Double
    @State private var estimate: OrderEstimate?
    @State private var estimateError: String?
    @State private var balance: Double?
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var resultMessage: String?
    @State private var succeeded = false

    init(draft: OrderDraft) {
        self.draft = draft
        _side = State(initialValue: draft.side)
        _limitPrice = State(initialValue: min(max(((draft.price ?? 0.5) * 100).rounded() / 100, 0.01), 0.99))
    }

    private var request: OrderRequest? {
        guard let tokenId = draft.tokenId, size > 0 else { return nil }
        return OrderRequest(
            tokenId: tokenId, side: side, type: mode == .market ? .fak : .gtc, size: size,
            limitPrice: mode == .limit ? limitPrice : nil)
    }

    private var sizeLabel: String {
        if mode == .market && side == .buy { return "支払額（USDC）" }
        return side == .buy ? "購入株数" : "売却株数"
    }

    private var tick: Double { estimate?.tickSize ?? 0.01 }

    private var summary: String {
        guard let estimate else { return "" }
        let action = side == .buy ? "買い" : "売り"
        return String(
            format: "%@ を %.2f 株 %@（%@ %.1f¢、約 $%.2f）",
            draft.outcomeName, estimate.shares, action, mode.rawValue, estimate.price * 100, estimate.usdc)
    }

    var body: some View {
        Form {
            Section {
                Text(draft.market.question).font(.subheadline)
                LabeledContent("アウトカム", value: draft.outcomeName)
                if let bid = estimate?.bestBid, let ask = estimate?.bestAsk {
                    LabeledContent("買い気配 / 売り気配", value: "\(Fmt.cents(bid)) / \(Fmt.cents(ask))")
                }
                if let balance {
                    LabeledContent("USDC 残高", value: String(format: "$%.2f", balance))
                }
            }

            Section {
                Picker("売買", selection: $side) {
                    ForEach(OrderSide.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("注文方法", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent(sizeLabel) {
                    TextField(sizeLabel, value: $size, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                if mode == .limit {
                    Stepper(value: $limitPrice, in: tick...(1 - tick), step: tick) {
                        LabeledContent("指値") {
                            Text(String(format: "%.1f¢", limitPrice * 100)).monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text(mode == .market
                    ? "板の注文に対して即時に約定させ、約定できなかった分は取り消します（FAK）。"
                    : "指定価格で板に注文を出し、約定するまで残ります（GTC）。")
            }

            Section("見積もり") {
                if let estimate {
                    LabeledContent(mode == .market ? "約定見込み価格（最大）" : "価格", value: Fmt.cents(estimate.price))
                    LabeledContent("株数", value: String(format: "%.2f", estimate.shares))
                    LabeledContent(side == .buy ? "支払額" : "受取額", value: String(format: "$%.2f", estimate.usdc))
                    if side == .buy {
                        LabeledContent("的中時の受取", value: String(format: "$%.2f", estimate.shares))
                    }
                    if let minimum = estimate.minOrderSize, estimate.shares < minimum {
                        Label(String(format: "最小注文数量は %.0f 株です", minimum), systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } else if let estimateError {
                    Text(estimateError).font(.footnote).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
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
                .disabled(isSubmitting || estimate == nil || request == nil || !services.trading.state.canTrade)
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
        .task(id: "\(side.rawValue)|\(mode.rawValue)|\(size)|\(limitPrice)") {
            await refreshEstimate()
        }
    }

    private func refreshEstimate() async {
        // 入力中の連続リクエストを避ける
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let request else { return }
        do {
            estimate = try await services.trading.estimate(request)
            estimateError = nil
        } catch {
            if error.isCancellation { return }
            estimate = nil
            estimateError = error.localizedDescription
        }
    }

    private func submit() async {
        guard let request else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await services.trading.placeOrder(request)
            succeeded = true
            resultMessage = "注文を受け付けました（\(receipt.status)）"
            balance = try? await services.trading.collateralBalance()
        } catch {
            succeeded = false
            resultMessage = error.localizedDescription
        }
    }
}
