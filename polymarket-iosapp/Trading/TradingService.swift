//
//  TradingService.swift
//  polymarket-iosapp
//
//  売買機能のインターフェース。UI はこのプロトコルと `TradingState` だけに依存する。
//  実装は `PolymarketTradingService`（秘密鍵を Keychain に保存し、端末内で EIP-712 署名して CLOB に発注）。
//

import Foundation

nonisolated enum TradingState: Equatable, Sendable {
    /// ウォレット未設定
    case notConfigured
    /// 鍵は保存済みだが未ロック解除（Face ID 等が必要）
    case locked
    case ready(address: String)

    var canTrade: Bool {
        if case .ready = self { return true }
        return false
    }

    var isConfigured: Bool { self != .notConfigured }

    var label: String {
        switch self {
        case .notConfigured: "未接続"
        case .locked: "ロック中"
        case .ready(let address): "接続済み \(address.prefix(6))…\(address.suffix(4))"
        }
    }
}

nonisolated enum OrderSide: String, Codable, CaseIterable, Sendable {
    case buy = "BUY"
    case sell = "SELL"

    var label: String { self == .buy ? "買う" : "売る" }
}

nonisolated enum OrderType: String, Codable, CaseIterable, Sendable {
    /// 指値（約定するまで板に残る）
    case gtc = "GTC"
    /// 成行：約定できる分だけ即時に約定し、残りは取消（Fill-And-Kill）
    case fak = "FAK"
    /// 成行：全量を即時に約定できなければ取消（Fill-Or-Kill）
    case fok = "FOK"

    var label: String {
        switch self {
        case .gtc: "指値"
        case .fak: "成行"
        case .fok: "成行(全量)"
        }
    }

    var isMarket: Bool { self != .gtc }
}

nonisolated struct OrderRequest: Sendable {
    let tokenId: String
    let side: OrderSide
    let type: OrderType
    /// 指値: 株数 / 成行 BUY: 支払う USDC / 成行 SELL: 売る株数（py SDK と同じ）
    let size: Double
    /// 指値のみ（0〜1）
    var limitPrice: Double?
}

/// 発注前の見積もり（板から算出）
nonisolated struct OrderEstimate: Sendable {
    /// 約定見込み価格（成行は板の最も不利な約定価格、指値は指定価格）
    let price: Double
    let shares: Double
    let usdc: Double
    let tickSize: Double
    let minOrderSize: Double?
    let bestBid: Double?
    let bestAsk: Double?
}

nonisolated struct OrderReceipt: Sendable {
    let orderId: String
    let status: String
}

nonisolated struct OpenOrder: Identifiable, Sendable {
    let id: String
    let tokenId: String
    let outcome: String
    let side: OrderSide
    let price: Double
    let size: Double
    let filledSize: Double
}

nonisolated struct Position: Identifiable, Sendable {
    let tokenId: String
    let marketQuestion: String
    let outcome: String
    let size: Double
    let averagePrice: Double
    let currentPrice: Double?
    let currentValue: Double?
    let pnl: Double?

    var id: String { tokenId }
}

nonisolated enum TradingError: LocalizedError {
    case notConfigured
    case locked
    case keyMissing
    case keyMismatch
    case invalidFunderAddress
    case unknownWalletType

    var errorDescription: String? {
        switch self {
        case .notConfigured: "ウォレットが接続されていません"
        case .locked: "ウォレットがロックされています"
        case .keyMissing: "保存された秘密鍵が見つかりません。ウォレットを接続し直してください"
        case .keyMismatch: "保存された秘密鍵のアドレスが設定と一致しません"
        case .invalidFunderAddress: "資金保有アドレス（0x から始まる40桁）を正しく入力してください"
        case .unknownWalletType: "この資金保有アドレスは入力した秘密鍵のウォレットではありません。Polymarket の設定に表示されるアドレスを確認してください"
        }
    }
}

protocol TradingService: AnyObject {
    var state: TradingState { get }
    /// 資金・ポジションを保有するアドレス
    var fundingAddress: String? { get }

    func unlock() async throws
    func lock()
    /// 板から約定価格・数量を見積もる（認証不要）
    func estimate(_ order: OrderRequest) async throws -> OrderEstimate
    func placeOrder(_ order: OrderRequest) async throws -> OrderReceipt
    func cancelOrder(id: String) async throws
    func openOrders() async throws -> [OpenOrder]
    func positions() async throws -> [Position]
    /// 利用可能な USDC 残高
    func collateralBalance() async throws -> Double
}

/// 取引機能を持たない（閲覧・監視専用）実装。プレビューやテスト用
final class DisabledTradingService: TradingService {
    var state: TradingState { .notConfigured }
    var fundingAddress: String? { nil }

    func unlock() async throws { throw TradingError.notConfigured }
    func lock() {}
    func estimate(_ order: OrderRequest) async throws -> OrderEstimate { throw TradingError.notConfigured }
    func placeOrder(_ order: OrderRequest) async throws -> OrderReceipt { throw TradingError.notConfigured }
    func cancelOrder(id: String) async throws { throw TradingError.notConfigured }
    func openOrders() async throws -> [OpenOrder] { [] }
    func positions() async throws -> [Position] { [] }
    func collateralBalance() async throws -> Double { 0 }
}
