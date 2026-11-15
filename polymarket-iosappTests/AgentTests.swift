//
//  AgentTests.swift
//  polymarket-iosappTests
//
//  AI の判断をどこまで実行してよいかを決めるガードレールのテスト。
//

import Foundation
import Testing
@testable import polymarket_iosapp

struct AgentGuardrailTests {
    private func context(prices: [Double] = [0.40, 0.60], held: [String: Double] = [:],
                         balance: Double? = 100, spentToday: Double = 0) -> AgentMarketContext {
        AgentMarketContext(
            marketId: "1", question: "Q", outcomes: ["Yes", "No"], prices: prices, tokenIds: ["Y", "N"],
            heldShares: held, balance: balance, spentToday: spentToday)
    }

    private func decision(_ action: AgentDecision.Action, outcome: Int = 0, confidence: Double = 0.8,
                          amount: Double = 3, fraction: Double = 0, limit: Double = 0) -> AgentDecision {
        AgentDecision(action: action, outcomeIndex: outcome, confidence: confidence, amountUsdc: amount,
                      sellFraction: fraction, limitPrice: limit, reasoning: "test")
    }

    @Test func holdStaysHold() {
        let plan = AgentGuardrails.plan(decision: decision(.hold), context: context(), settings: AgentSettings())
        #expect(plan == .hold(reason: "AI の判断: キープ"))
    }

    @Test func lowConfidenceIsSkipped() {
        let plan = AgentGuardrails.plan(decision: decision(.buy, confidence: 0.5), context: context(), settings: AgentSettings())
        guard case .hold = plan else { Issue.record("expected hold"); return }
    }

    @Test func buyIsCappedBySettingsBudgetAndBalance() {
        var settings = AgentSettings()
        settings.maxTradeUSDC = 5
        settings.dailyBudgetUSDC = 20
        // AI が $50 を希望しても 1 回の上限 $5 に制限
        #expect(AgentGuardrails.plan(decision: decision(.buy, amount: 50), context: context(), settings: settings)
            == .buy(outcomeIndex: 0, tokenId: "Y", usdc: 5, maxPrice: 0.43))
        // 今日の残り予算 $2.5
        #expect(AgentGuardrails.plan(decision: decision(.buy, amount: 50), context: context(spentToday: 17.5), settings: settings)
            == .buy(outcomeIndex: 0, tokenId: "Y", usdc: 2.5, maxPrice: 0.43))
        // 残高 $1.2
        #expect(AgentGuardrails.plan(decision: decision(.buy, amount: 50), context: context(balance: 1.2), settings: settings)
            == .buy(outcomeIndex: 0, tokenId: "Y", usdc: 1.2, maxPrice: 0.43))
        // 予算切れ
        guard case .hold = AgentGuardrails.plan(decision: decision(.buy), context: context(spentToday: 19.5), settings: settings)
        else { Issue.record("expected hold"); return }
    }

    @Test func buyRespectsPriceRangeAndLimit() {
        var settings = AgentSettings()
        settings.maxBuyPrice = 0.55
        // No（0.60）は購入範囲外
        guard case .hold = AgentGuardrails.plan(decision: decision(.buy, outcome: 1), context: context(), settings: settings)
        else { Issue.record("expected hold"); return }
        // AI の上限価格 0.41 が反映される
        #expect(AgentGuardrails.plan(decision: decision(.buy, limit: 0.41), context: context(), settings: settings)
            == .buy(outcomeIndex: 0, tokenId: "Y", usdc: 3, maxPrice: 0.41))
        // AI の上限価格が現在価格より低ければ見送り
        guard case .hold = AgentGuardrails.plan(decision: decision(.buy, limit: 0.35), context: context(), settings: settings)
        else { Issue.record("expected hold"); return }
    }

    @Test func buyDisallowedBySettings() {
        var settings = AgentSettings()
        settings.allowBuy = false
        guard case .hold = AgentGuardrails.plan(decision: decision(.buy), context: context(), settings: settings)
        else { Issue.record("expected hold"); return }
    }

    @Test func sellRequiresHoldingAndRoundsDown() {
        let settings = AgentSettings()
        guard case .hold = AgentGuardrails.plan(decision: decision(.sell, fraction: 1), context: context(), settings: settings)
        else { Issue.record("expected hold"); return }
        #expect(AgentGuardrails.plan(
            decision: decision(.sell, fraction: 0.5), context: context(held: ["Y": 10.555]), settings: settings)
            == .sell(outcomeIndex: 0, tokenId: "Y", shares: 5.27, minPrice: 0.37))
        // 割合は 0〜1 に丸める
        #expect(AgentGuardrails.plan(
            decision: decision(.sell, fraction: 3), context: context(held: ["Y": 4]), settings: settings)
            == .sell(outcomeIndex: 0, tokenId: "Y", shares: 4, minPrice: 0.37))
    }

    @Test func invalidOutcomeIsSkipped() {
        guard case .hold = AgentGuardrails.plan(decision: decision(.buy, outcome: 5), context: context(), settings: AgentSettings())
        else { Issue.record("expected hold"); return }
    }
}

struct AgentDecodingTests {
    @Test func decodesStructuredOutput() throws {
        let json = #"{"action":"buy","outcome_index":1,"confidence":0.72,"amount_usdc":4.5,"sell_fraction":0,"limit_price":0.61,"reasoning":"理由"}"#
        let decision = try JSONDecoder().decode(AgentDecision.self, from: Data(json.utf8))
        #expect(decision.action == .buy)
        #expect(decision.outcomeIndex == 1)
        #expect(decision.limitPrice == 0.61)
    }

    @Test func settingsDefaultToSafeValues() throws {
        let settings = try JSONDecoder().decode(AgentSettings.self, from: Data("{}".utf8))
        #expect(settings.enabled == false)
        #expect(settings.mode == .paper)
        #expect(settings.triggerKinds == [.priceMove])
    }

    @Test func schemaRequiresEveryProperty() throws {
        let schema = AgentDecision.jsonSchema
        let required = try #require(schema["required"] as? [String])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(required) == Set(properties.keys))
        #expect(schema["additionalProperties"] as? Bool == false)
        // OpenAI に送れる JSON になっていること
        #expect(JSONSerialization.isValidJSONObject(schema))
    }
}
