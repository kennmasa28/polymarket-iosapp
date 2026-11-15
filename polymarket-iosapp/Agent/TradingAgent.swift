//
//  TradingAgent.swift
//  polymarket-iosapp
//
//  急変アラートを受けて AI に「購入・売却・キープ」を判断させ、設定の範囲内で自動売買する。
//   1. マーケット情報・価格履歴・保有状況・予算を集める
//   2. OpenAI に判断させる（JSON スキーマで形式を強制）
//   3. AgentGuardrails で金額・価格・確信度を検証/制限する
//   4. 板から見積もり、許容価格を超えないことを確認してから発注（シミュレーションなら見積もりのみ）
//  実取引はウォレットのロック解除中だけ行う（秘密鍵の保護は弱めない）。ロック中は「未実行」として記録・通知する。
//

import Foundation
import Observation

@Observable
final class TradingAgent {
    private static let logFile = "agent_log.json"
    private static let maxLogEntries = 300

    private(set) var log: [AgentLogEntry]
    private(set) var isEvaluating = false
    private(set) var lastError: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let openAI = OpenAIClient()

    init(services: AppServices, settings: SettingsStore) {
        self.services = services
        self.settings = settings
        log = LocalStore.load([AgentLogEntry].self, from: Self.logFile) ?? []
    }

    var hasAPIKey: Bool { OpenAIClient.loadAPIKey() != nil }

    /// 今日（端末の日付）実際に購入に使った金額
    var spentToday: Double {
        log.filter { $0.status == .executed && $0.action == .buy && Calendar.current.isDateInToday($0.date) }
            .compactMap(\.usdc)
            .reduce(0, +)
    }

    // MARK: Triggers

    /// モニターで新しく発火したアラートを受け取る
    func handle(alerts: [AlertRecord]) async {
        let config = settings.value.agent
        guard config.enabled, hasAPIKey else { return }
        let cooldown = TimeInterval(config.marketCooldownMinutes) * 60
        var seen = Set<String>()
        let targets = alerts
            .filter { config.triggerKinds.contains($0.kind) }
            .filter { seen.insert($0.marketId).inserted }
            .filter { record in
                !log.contains { $0.marketId == record.marketId && Date().timeIntervalSince($0.date) < cooldown }
            }
            .prefix(config.maxEvaluationsPerCycle)
        for record in targets {
            await evaluate(marketId: record.marketId, trigger: "\(record.kind.label): \(record.summary)")
        }
    }

    /// 指定マーケットについて判断し、設定に従って実行する（設定画面からのテストでも使う）
    func evaluate(marketId: String, trigger: String) async {
        let config = settings.value.agent
        isEvaluating = true
        defer { isEvaluating = false }
        do {
            let market = try await services.gamma.market(id: marketId)
            let context = try await buildContext(market: market)
            let decision = try await openAI.decide(
                model: config.model,
                systemPrompt: Self.systemPrompt(settings: config),
                userPrompt: await userPrompt(market: market, context: context, trigger: trigger, settings: config))
            let entry = await execute(decision: decision, market: market, context: context, trigger: trigger, settings: config)
            append(entry)
            lastError = nil
            if entry.action != .hold || entry.status == .failed {
                await NotificationService.deliverAgent(entry)
            }
        } catch {
            if error.isCancellation { return }
            lastError = error.localizedDescription
        }
    }

    func clearLog() {
        log.removeAll()
        LocalStore.save(log, to: Self.logFile)
    }

    // MARK: Context

    private func buildContext(market: PMMarket) async throws -> AgentMarketContext {
        var held: [String: Double] = [:]
        if services.trading.state.isConfigured, let positions = try? await services.trading.positions() {
            for position in positions where market.clobTokenIds.contains(position.tokenId) {
                held[position.tokenId, default: 0] += position.size
            }
        }
        var balance: Double?
        if services.trading.state.canTrade {
            balance = try? await services.trading.collateralBalance()
        }
        return AgentMarketContext(
            marketId: market.id,
            question: market.question,
            outcomes: market.outcomes,
            prices: market.outcomePrices,
            tokenIds: market.clobTokenIds,
            heldShares: held,
            balance: balance,
            spentToday: spentToday)
    }

    static func systemPrompt(settings: AgentSettings) -> String {
        let stance: String
        switch settings.aggressiveness {
        case ..<0.34:
            stance = "慎重。明確な根拠がない限りキープを選び、購入額は控えめにする。損失回避を最優先する。"
        case ..<0.67:
            stance = "標準。期待値がはっきりプラスのときだけ売買し、根拠の強さに応じて金額を調整する。"
        default:
            stance = "強気。短期的な勢い（モメンタム）にも乗り、期待値がプラスなら上限に近い金額で積極的に売買する。"
        }
        var prompt = """
            あなたは Polymarket（予測市場）の売買判断を行うトレーディングエージェントです。
            価格の急変などのアラートが出たマーケットについて、購入（buy）・売却（sell）・キープ（hold）のいずれかを判断します。

            ルール:
            - 価格は 0〜1 で、そのアウトカムが起きる確率の市場予想を表します。的中すると 1 株あたり 1 USDC になります。
            - 購入は 1 回 \(String(format: "%.2f", settings.maxTradeUSDC)) USDC まで。amount_usdc はこれ以下にしてください。
            - 購入してよい価格帯は \(String(format: "%.2f", settings.minBuyPrice))〜\(String(format: "%.2f", settings.maxBuyPrice)) です。
            - 売却は保有しているアウトカムだけ可能です。保有がなければ sell を選ばないでください。
            - 情報が不十分、急変の理由が不明、または期待値がはっきりしない場合は hold を選んでください。
            - 解決ルールや終了日も考慮し、ニュースを推測で断定しないでください。
            - confidence は判断の確からしさ（0〜1）を正直に答えてください。
            - reasoning は日本語で簡潔に書いてください。

            リスク姿勢（強気度 \(String(format: "%.0f", settings.aggressiveness * 100))/100）: \(stance)
            """
        if !settings.allowBuy { prompt += "\n- 購入は禁止されています。buy を選ばないでください。" }
        if !settings.allowSell { prompt += "\n- 売却は禁止されています。sell を選ばないでください。" }
        let instructions = settings.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            prompt += "\n\nユーザーの投資方針:\n\(instructions)"
        }
        return prompt
    }

    private func userPrompt(market: PMMarket, context: AgentMarketContext, trigger: String, settings: AgentSettings) async -> String {
        var lines: [String] = []
        lines.append("アラート: \(trigger)")
        if let event = market.events.first?.title, event != market.question { lines.append("イベント: \(event)") }
        lines.append("マーケット: \(market.question)")
        for (index, outcome) in market.outcomes.enumerated() {
            let price = market.outcomePrices.indices.contains(index) ? String(format: "%.3f", market.outcomePrices[index]) : "不明"
            let tokenId = market.clobTokenIds.indices.contains(index) ? market.clobTokenIds[index] : ""
            let held = context.heldShares[tokenId].map { String(format: "%.2f 株", $0) } ?? "なし"
            lines.append("アウトカム \(index): \(outcome) 価格 \(price) 保有 \(held)")
        }
        lines.append(String(
            format: "変化（先頭アウトカム）: 1時間 %@ / 24時間 %@ / 1週間 %@",
            Fmt.points(market.oneHourPriceChange), Fmt.points(market.oneDayPriceChange), Fmt.points(market.oneWeekPriceChange)))
        lines.append("出来高 24h \(Fmt.usd(market.volume24hr)) / 累計 \(Fmt.usd(market.volume)) / 流動性 \(Fmt.usd(market.liquidity))")
        lines.append("買い気配 \(Fmt.cents(market.bestBid)) / 売り気配 \(Fmt.cents(market.bestAsk))")
        if let end = market.endDateValue {
            lines.append("終了予定: \(end.formatted(date: .abbreviated, time: .omitted))")
        }
        if let tokenId = market.clobTokenIds.first,
           let history = try? await services.clob.priceHistory(tokenId: tokenId, interval: .day), !history.isEmpty {
            let step = max(history.count / 24, 1)
            let sampled = stride(from: 0, to: history.count, by: step).map { history[$0] }
            let series = sampled.map { String(format: "%.3f", $0.p) }.joined(separator: ", ")
            lines.append("直近 24 時間の価格推移（古い順）: \(series)")
        }
        let remaining = max(settings.dailyBudgetUSDC - context.spentToday, 0)
        lines.append(String(format: "今日の残り予算: %.2f USDC", remaining))
        if let balance = context.balance { lines.append(String(format: "USDC 残高: %.2f", balance)) }
        if let description = market.description, !description.isEmpty {
            lines.append("解決ルール（抜粋）: \(description.prefix(600))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Execution

    private func execute(
        decision: AgentDecision, market: PMMarket, context: AgentMarketContext, trigger: String, settings: AgentSettings
    ) async -> AgentLogEntry {
        let outcome = market.outcomes.indices.contains(decision.outcomeIndex) ? market.outcomes[decision.outcomeIndex] : nil
        var entry = AgentLogEntry(
            date: .now, marketId: market.id, question: market.question, trigger: trigger,
            action: decision.action, outcome: outcome, confidence: decision.confidence,
            reasoning: decision.reasoning, status: .skipped, detail: "", mode: settings.mode)

        let plan = AgentGuardrails.plan(decision: decision, context: context, settings: settings)
        let request: OrderRequest
        switch plan {
        case .hold(let reason):
            entry.detail = reason
            return entry
        case .buy(_, let tokenId, let usdc, _):
            request = OrderRequest(tokenId: tokenId, side: .buy, type: .fak, size: usdc)
        case .sell(_, let tokenId, let shares, _):
            request = OrderRequest(tokenId: tokenId, side: .sell, type: .fak, size: shares)
        }

        do {
            let estimate = try await services.trading.estimate(request)
            entry.price = estimate.price
            entry.shares = estimate.shares
            entry.usdc = estimate.usdc
            // 板の約定見込み価格が許容範囲を超えていれば見送る
            switch plan {
            case .buy(_, _, _, let maxPrice) where estimate.price > maxPrice + 1e-9:
                entry.detail = String(format: "約定見込み %.1f¢ が上限 %.1f¢ を超えるため見送り", estimate.price * 100, maxPrice * 100)
                return entry
            case .sell(_, _, _, let minPrice) where estimate.price < minPrice - 1e-9:
                entry.detail = String(format: "約定見込み %.1f¢ が下限 %.1f¢ を下回るため見送り", estimate.price * 100, minPrice * 100)
                return entry
            default:
                break
            }
            if let minimum = estimate.minOrderSize, estimate.shares < minimum {
                entry.detail = String(format: "最小注文数量 %.0f 株に満たないため見送り", minimum)
                return entry
            }

            switch settings.mode {
            case .paper:
                entry.status = .simulated
                entry.detail = "シミュレーションのため注文は出していません"
            case .live:
                guard services.trading.state.canTrade else {
                    entry.status = .pendingUnlock
                    entry.detail = "ウォレットがロック中のため注文できませんでした"
                    return entry
                }
                let receipt = try await services.trading.placeOrder(request)
                entry.status = .executed
                entry.detail = "注文を受け付けました（\(receipt.status)）"
            }
        } catch {
            entry.status = .failed
            entry.detail = error.localizedDescription
        }
        return entry
    }

    private func append(_ entry: AgentLogEntry) {
        log = Array(([entry] + log).prefix(Self.maxLogEntries))
        LocalStore.save(log, to: Self.logFile)
    }
}
