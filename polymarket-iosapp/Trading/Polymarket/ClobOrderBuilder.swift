//
//  ClobOrderBuilder.swift
//  polymarket-iosapp
//
//  Polymarket CLOB の注文（CTF Exchange の EIP-712 Order）を組み立てて署名する。
//  py-clob-client / py-order-utils と同じ仕様。金額は浮動小数点誤差を避けるため整数で計算する。
//

import Foundation

nonisolated enum ClobContracts {
    static let chainId = 137  // Polygon
    static let exchange = "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E"
    static let negRiskExchange = "0xC5d563A36AE78145C45a50134d48A1215220f80a"

    static let orderTypeString =
        "Order(uint256 salt,address maker,address signer,address taker,uint256 tokenId,"
        + "uint256 makerAmount,uint256 takerAmount,uint256 expiration,uint256 nonce,"
        + "uint256 feeRateBps,uint8 side,uint8 signatureType)"
}

/// 資金を保有するウォレットの種類（Order.signatureType）
nonisolated enum WalletSignatureType: Int, Codable, CaseIterable, Sendable {
    /// 秘密鍵のアドレス自体が資金を保有
    case eoa = 0
    /// Polymarket のプロキシウォレット（メール/Magic ログイン）
    case polyProxy = 1
    /// Polymarket の Gnosis Safe（MetaMask 等のブラウザウォレットでログイン）
    case gnosisSafe = 2

    var label: String {
        switch self {
        case .eoa: "EOA（秘密鍵のアドレスで直接保有）"
        case .polyProxy: "Polymarket プロキシ（メールログイン）"
        case .gnosisSafe: "Polymarket Safe（MetaMask ログイン）"
        }
    }

    var usesFunderAddress: Bool { self != .eoa }
}

nonisolated enum ClobOrderError: LocalizedError {
    case invalidTickSize(String)
    case priceOutOfRange(min: Double, max: Double)
    case sizeTooSmall
    case amountTooSmall

    var errorDescription: String? {
        switch self {
        case .invalidTickSize(let tick): "未対応のティックサイズです: \(tick)"
        case .priceOutOfRange(let min, let max): String(format: "価格は %.4g〜%.4g の範囲で指定してください", min, max)
        case .sizeTooSmall: "株数が小さすぎます（0.01 以上）"
        case .amountTooSmall: "注文金額が小さすぎます"
        }
    }
}

nonisolated struct ClobOrderAmounts: Equatable, Sendable {
    /// 6 桁小数の整数表現（USDC / 条件付きトークンとも 6 decimals）
    let makerAmount: Int64
    let takerAmount: Int64
}

/// CLOB `POST /order` の `order` フィールド
nonisolated struct SignedClobOrder: Codable, Equatable, Sendable {
    let salt: Int
    let maker: String
    let signer: String
    let taker: String
    let tokenId: String
    let makerAmount: String
    let takerAmount: String
    let expiration: String
    let nonce: String
    let feeRateBps: String
    let side: String
    let signatureType: Int
    let signature: String
}

nonisolated struct ClobOrderParameters: Sendable {
    let tokenId: String
    let side: OrderSide
    let amounts: ClobOrderAmounts
    /// 資金保有アドレス（EOA の場合は署名者アドレス）
    let maker: String
    let signatureType: WalletSignatureType
    let feeRateBps: Int
    let negRisk: Bool
    var salt = Int.random(in: 1...Int(Int32.max))
    var expiration = 0
    var nonce = 0
}

nonisolated enum ClobOrderBuilder {
    /// "0.01" → 2
    static func tickDecimals(_ tickSize: String) throws -> Int {
        switch tickSize {
        case "0.1": return 1
        case "0.01": return 2
        case "0.001": return 3
        case "0.0001": return 4
        default: throw ClobOrderError.invalidTickSize(tickSize)
        }
    }

    private static func pow10(_ exponent: Int) -> Int64 {
        (0..<exponent).reduce(Int64(1)) { value, _ in value * 10 }
    }

    /// 価格をティック単位の整数に（範囲外ならエラー）
    static func priceUnits(_ price: Double, tickDecimals: Int) throws -> Int64 {
        let scale = pow10(tickDecimals)
        let units = Int64((price * Double(scale)).rounded())
        guard units >= 1, units <= scale - 1 else {
            let tick = 1 / Double(scale)
            throw ClobOrderError.priceOutOfRange(min: tick, max: 1 - tick)
        }
        return units
    }

    /// 株数を 0.01 単位の整数に切り捨て
    static func sizeCents(_ size: Double) throws -> Int64 {
        let cents = Int64((size * 100 + 1e-7).rounded(.down))
        guard cents > 0 else { throw ClobOrderError.sizeTooSmall }
        return cents
    }

    /// 指値注文（GTC/GTD）の金額。BUY: maker=USDC, taker=株 / SELL: maker=株, taker=USDC
    static func limitAmounts(side: OrderSide, price: Double, size: Double, tickSize: String) throws -> ClobOrderAmounts {
        let decimals = try tickDecimals(tickSize)
        let price = try priceUnits(price, tickDecimals: decimals)
        let size = try sizeCents(size)
        let shares = size * 10_000
        let notional = size * price * pow10(4 - decimals)
        return side == .buy
            ? ClobOrderAmounts(makerAmount: notional, takerAmount: shares)
            : ClobOrderAmounts(makerAmount: shares, takerAmount: notional)
    }

    /// 成行（FOK）注文の金額。BUY は支払額（USDC, 小数2桁）から株数を算出する（py-clob-client の market order と同じ）
    static func marketAmounts(side: OrderSide, price: Double, size: Double, tickSize: String) throws -> ClobOrderAmounts {
        guard side == .buy else {
            return try limitAmounts(side: side, price: price, size: size, tickSize: tickSize)
        }
        let decimals = try tickDecimals(tickSize)
        let price = try priceUnits(price, tickDecimals: decimals)
        let usdcCents = try sizeCents(size) * price / pow10(decimals)
        guard usdcCents > 0 else { throw ClobOrderError.amountTooSmall }
        let shares = usdcCents * pow10(2 * decimals) / price * pow10(4 - decimals)
        return ClobOrderAmounts(makerAmount: usdcCents * 10_000, takerAmount: shares)
    }

    static func build(_ parameters: ClobOrderParameters, signer: EthereumSigner) throws -> SignedClobOrder {
        let maker = try EthereumAddress.checksummed(parameters.maker)
        let signerAddress = signer.address
        let taker = EthereumAddress.zero
        let message = EIP712Struct(
            typeString: ClobContracts.orderTypeString,
            values: [
                .uint(String(parameters.salt)),
                .address(maker),
                .address(signerAddress),
                .address(taker),
                .uint(parameters.tokenId),
                .uint(String(parameters.amounts.makerAmount)),
                .uint(String(parameters.amounts.takerAmount)),
                .uint(String(parameters.expiration)),
                .uint(String(parameters.nonce)),
                .uint(String(parameters.feeRateBps)),
                .uint(parameters.side == .buy ? "0" : "1"),
                .uint(String(parameters.signatureType.rawValue)),
            ])
        let domain = try EIP712.domainSeparator(
            name: "Polymarket CTF Exchange", version: "1", chainId: ClobContracts.chainId,
            verifyingContract: parameters.negRisk ? ClobContracts.negRiskExchange : ClobContracts.exchange)
        let digest = try EIP712.digest(domainSeparator: domain, message: message)
        let signature = try signer.sign(digest: digest)

        return SignedClobOrder(
            salt: parameters.salt,
            maker: maker,
            signer: signerAddress,
            taker: taker,
            tokenId: parameters.tokenId,
            makerAmount: String(parameters.amounts.makerAmount),
            takerAmount: String(parameters.amounts.takerAmount),
            expiration: String(parameters.expiration),
            nonce: String(parameters.nonce),
            feeRateBps: String(parameters.feeRateBps),
            side: parameters.side.rawValue,
            signatureType: parameters.signatureType.rawValue,
            signature: signature.prefixedHex)
    }

    /// L1 認証（API キーの作成/導出）用の ClobAuth 署名
    static func clobAuthSignature(signer: EthereumSigner, timestamp: Int, nonce: Int) throws -> String {
        let message = EIP712Struct(
            typeString: "ClobAuth(address address,string timestamp,uint256 nonce,string message)",
            values: [
                .address(signer.address),
                .string(String(timestamp)),
                .uint(String(nonce)),
                .string("This message attests that I control the given wallet"),
            ])
        let domain = try EIP712.domainSeparator(
            name: "ClobAuthDomain", version: "1", chainId: ClobContracts.chainId, verifyingContract: nil)
        return try signer.sign(digest: EIP712.digest(domainSeparator: domain, message: message)).prefixedHex
    }
}
