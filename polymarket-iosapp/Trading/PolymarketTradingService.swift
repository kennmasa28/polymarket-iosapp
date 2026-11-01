//
//  PolymarketTradingService.swift
//  polymarket-iosapp
//
//  秘密鍵を Keychain に保存し、ロック解除中だけメモリに保持して CLOB に発注する。
//  アプリがバックグラウンドに入ると自動でロックする（AppContainer）。
//

import Foundation
import Observation

/// ウォレットの公開情報（wallet.json。秘密情報は含まない）
nonisolated struct WalletConfiguration: Codable, Equatable, Sendable {
    /// 秘密鍵から導出した署名者アドレス
    var signerAddress: String
    var signatureType: WalletSignatureType
    /// 資金を保有するアドレス（EOA の場合は signerAddress と同じ）
    var funderAddress: String
}

@Observable
final class PolymarketTradingService: TradingService {
    private static let configurationFile = "wallet.json"
    private static let unlockReason = "取引のためにウォレットのロックを解除します"

    private(set) var state: TradingState
    private(set) var configuration: WalletConfiguration?

    @ObservationIgnored private var signer: EthereumSigner?
    @ObservationIgnored private var credentials: ClobCredentials?
    @ObservationIgnored private let clob = ClobTradingClient()
    @ObservationIgnored private let dataAPI = DataAPI()

    init() {
        // @Observable のプロパティは全プロパティ初期化前に読めないため、ローカル変数経由で設定する
        let saved = LocalStore.load(WalletConfiguration.self, from: Self.configurationFile)
        configuration = saved
        state = saved == nil ? .notConfigured : .locked
    }

    var fundingAddress: String? { configuration?.funderAddress }

    // MARK: Wallet lifecycle

    /// 秘密鍵と資金保有アドレスを検証し（ウォレット種別は自動判定）、CLOB の API キーを取得して Keychain に保存する。
    /// 資金保有アドレスを空にした場合は秘密鍵のアドレス（EOA）で取引する
    func connect(privateKey: String, funderAddress: String?) async throws {
        let keyData = try Data(hex: privateKey)
        let signer = try EthereumSigner(privateKey: keyData)

        let funder: String
        let signatureType: WalletSignatureType
        let trimmed = funderAddress?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            funder = signer.address
            signatureType = .eoa
        } else {
            guard EthereumAddress.isValid(trimmed) else { throw TradingError.invalidFunderAddress }
            funder = try EthereumAddress.checksummed(trimmed)
            guard let detected = try WalletDerivation.detect(signer: signer.address, wallet: funder) else {
                throw TradingError.unknownWalletType
            }
            signatureType = detected
        }

        let credentials = try await clob.createOrDeriveCredentials(signer: signer)
        try KeychainItem.privateKey.save(keyData)
        try KeychainItem.clobCredentials.save(JSONEncoder().encode(credentials))

        let configuration = WalletConfiguration(
            signerAddress: signer.address, signatureType: signatureType, funderAddress: funder)
        LocalStore.save(configuration, to: Self.configurationFile)

        self.configuration = configuration
        self.signer = signer
        self.credentials = credentials
        state = .ready(address: signer.address)
    }

    func unlock() async throws {
        guard let configuration else { throw TradingError.notConfigured }
        if state.canTrade { return }

        let reason = Self.unlockReason
        let keyData = try await Task.detached(priority: .userInitiated) {
            try KeychainItem.privateKey.load(reason: reason)
        }.value
        guard let keyData else { throw TradingError.keyMissing }

        let signer = try EthereumSigner(privateKey: keyData)
        guard signer.address == configuration.signerAddress else { throw TradingError.keyMismatch }
        // 以前のバージョンで保存した種別が誤っていても、資金保有アドレスから判定し直して補正する
        if let detected = try? WalletDerivation.detect(signer: signer.address, wallet: configuration.funderAddress),
           detected != configuration.signatureType {
            var corrected = configuration
            corrected.signatureType = detected
            LocalStore.save(corrected, to: Self.configurationFile)
            self.configuration = corrected
        }

        var credentials = (try? KeychainItem.clobCredentials.load())
            .flatMap { try? JSONDecoder().decode(ClobCredentials.self, from: $0) }
        if credentials == nil {
            let derived = try await clob.createOrDeriveCredentials(signer: signer)
            try? KeychainItem.clobCredentials.save(JSONEncoder().encode(derived))
            credentials = derived
        }

        self.signer = signer
        self.credentials = credentials
        state = .ready(address: signer.address)
    }

    func lock() {
        signer = nil
        credentials = nil
        if configuration != nil { state = .locked }
    }

    /// 秘密鍵・API キー・設定をすべて削除する
    func disconnect() throws {
        lock()
        try KeychainItem.privateKey.delete()
        try KeychainItem.clobCredentials.delete()
        LocalStore.remove(Self.configurationFile)
        configuration = nil
        state = .notConfigured
    }

    private func readyContext() throws -> (EthereumSigner, ClobCredentials, WalletConfiguration) {
        guard let configuration else { throw TradingError.notConfigured }
        guard let signer, let credentials else { throw TradingError.locked }
        return (signer, credentials, configuration)
    }

    // MARK: Trading

    func estimate(_ order: OrderRequest) async throws -> OrderEstimate {
        let book = try await clob.orderBook(tokenId: order.tokenId)
        let (amounts, price) = try Self.amounts(for: order, book: book)
        let shares = Double(order.side == .buy ? amounts.takerAmount : amounts.makerAmount) / 1_000_000
        let usdc = Double(order.side == .buy ? amounts.makerAmount : amounts.takerAmount) / 1_000_000
        return OrderEstimate(
            price: price, shares: shares, usdc: usdc, tickSize: try ClobTick(book.tickSize).value,
            minOrderSize: book.minOrderSize, bestBid: book.bestBid, bestAsk: book.bestAsk)
    }

    func placeOrder(_ order: OrderRequest) async throws -> OrderReceipt {
        let (signer, credentials, configuration) = try readyContext()
        let book = try await clob.orderBook(tokenId: order.tokenId)
        let (amounts, _) = try Self.amounts(for: order, book: book)

        let signed = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: order.tokenId,
                side: order.side,
                amounts: amounts,
                wallet: configuration.funderAddress,
                signatureType: configuration.signatureType,
                negRisk: book.negRisk),
            signer: signer)

        let response = try await clob.postOrder(
            signed, orderType: order.type, address: signer.address, credentials: credentials)
        return OrderReceipt(orderId: response.orderID ?? "", status: response.status ?? "submitted")
    }

    /// 成行は板から約定価格を決め、指値は指定価格で金額を計算する
    private static func amounts(for order: OrderRequest, book: ClobOrderBook) throws -> (ClobOrderAmounts, Double) {
        let tick = try ClobTick(book.tickSize)
        if order.type.isMarket {
            let price = try ClobOrderBuilder.marketPrice(book: book, side: order.side, amount: order.size, type: order.type)
            let amounts = try ClobOrderBuilder.marketAmounts(side: order.side, price: price, amount: order.size, tick: tick)
            return (amounts, price)
        }
        guard let price = order.limitPrice else { throw ClobOrderError.priceOutOfRange(min: tick.value, max: 1 - tick.value) }
        return (try ClobOrderBuilder.limitAmounts(side: order.side, price: price, size: order.size, tick: tick), price)
    }

    func cancelOrder(id: String) async throws {
        let (signer, credentials, _) = try readyContext()
        try await clob.cancelOrder(id: id, address: signer.address, credentials: credentials)
    }

    func openOrders() async throws -> [OpenOrder] {
        let (signer, credentials, _) = try readyContext()
        return try await clob.openOrders(address: signer.address, credentials: credentials).map { order in
            OpenOrder(
                id: order.id,
                tokenId: order.assetId ?? "",
                outcome: order.outcome ?? "",
                side: OrderSide(rawValue: (order.side ?? "").uppercased()) ?? .buy,
                price: order.price ?? 0,
                size: order.originalSize ?? 0,
                filledSize: order.sizeMatched ?? 0)
        }
    }

    func positions() async throws -> [Position] {
        guard let funder = configuration?.funderAddress else { throw TradingError.notConfigured }
        return try await dataAPI.positions(user: funder).map { position in
            Position(
                tokenId: position.asset,
                marketQuestion: position.title,
                outcome: position.outcome,
                size: position.size,
                averagePrice: position.avgPrice,
                currentPrice: position.curPrice,
                currentValue: position.currentValue,
                pnl: position.cashPnl)
        }
    }

    func collateralBalance() async throws -> Double {
        let (signer, credentials, configuration) = try readyContext()
        return try await clob.collateralBalance(
            address: signer.address, credentials: credentials, signatureType: configuration.signatureType)
    }
}
