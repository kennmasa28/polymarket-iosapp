//
//  TradingService.swift
//  polymarket-iosapp
//
//  売買機能の拡張ポイント。現時点では `DisabledTradingService`（常に未接続）を使う。
//
//  将来の実装方針（PolymarketTradingService）:
//   1. 設定 › ウォレット で MetaMask の秘密鍵を入力 → `WalletKeyStore`（Keychain, この端末のみ）に保存
//   2. 秘密鍵から EOA アドレスを導出し、CLOB の L1 認証（EIP-712 署名）で API キーを発行/取得
//   3. 注文は EIP-712 で端末内署名し、L2 ヘッダ（HMAC）付きで CLOB `POST /order` へ送信
//   秘密鍵は端末外へ送信しない。UI は `TradingState` と本プロトコルだけに依存させる。
//

import Foundation

nonisolated enum TradingState: Equatable, Sendable {
    /// ウォレット未設定
    case notConfigured
    /// 鍵は保存済みだが未ロック解除（Face ID 等）
    case locked
    case ready(address: String)

    var canTrade: Bool {
        if case .ready = self { return true }
        return false
    }

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
    /// 指値（約定するまで有効）
    case gtc = "GTC"
    /// 即時全量約定、できなければ取消
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

    var id: String { tokenId }
}

nonisolated enum TradingError: LocalizedError {
    case notConfigured
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notConfigured: "ウォレットが接続されていません"
        case .notImplemented: "取引機能はまだ実装されていません"
        }
    }
}

protocol TradingService: AnyObject {
    var state: TradingState { get }
    func placeOrder(_ order: OrderRequest) async throws -> OrderReceipt
    func cancelOrder(id: String) async throws
    func openOrders() async throws -> [OpenOrder]
    func positions() async throws -> [Position]
}

/// 取引機能を持たない（閲覧・監視専用）実装
final class DisabledTradingService: TradingService {
    var state: TradingState { .notConfigured }

    func placeOrder(_ order: OrderRequest) async throws -> OrderReceipt { throw TradingError.notConfigured }
    func cancelOrder(id: String) async throws { throw TradingError.notConfigured }
    func openOrders() async throws -> [OpenOrder] { [] }
    func positions() async throws -> [Position] { [] }
}
