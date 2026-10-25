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
    /// 即時に全量約定、できなければ取消（価格は許容する最も不利な価格）
    case fok = "FOK"

    var label: String { self == .gtc ? "指値" : "成行(FOK)" }
}

nonisolated struct OrderRequest: Sendable {
    let tokenId: String
    let side: OrderSide
    /// 0〜1（USDC/株）
    let price: Double
    /// 株数
    let size: Double
    let type: OrderType
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

    var errorDescription: String? {
        switch self {
        case .notConfigured: "ウォレットが接続されていません"
        case .locked: "ウォレットがロックされています"
        case .keyMissing: "保存された秘密鍵が見つかりません。ウォレットを接続し直してください"
        case .keyMismatch: "保存された秘密鍵のアドレスが設定と一致しません"
        case .invalidFunderAddress: "資金保有アドレス（0x から始まる40桁）を正しく入力してください"
        }
    }
}

protocol TradingService: AnyObject {
    var state: TradingState { get }
    /// 資金・ポジションを保有するアドレス
    var fundingAddress: String? { get }

    func unlock() async throws
    func lock()
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
    func placeOrder(_ order: OrderRequest) async throws -> OrderReceipt { throw TradingError.notConfigured }
    func cancelOrder(id: String) async throws { throw TradingError.notConfigured }
    func openOrders() async throws -> [OpenOrder] { [] }
    func positions() async throws -> [Position] { [] }
    func collateralBalance() async throws -> Double { 0 }
}
