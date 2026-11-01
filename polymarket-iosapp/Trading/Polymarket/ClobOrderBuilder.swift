//
//  ClobOrderBuilder.swift
//  polymarket-iosapp
//
//  Polymarket CLOB V2 の注文（CTF Exchange v2 の EIP-712 Order）を組み立てて署名する。
//  仕様は公式 SDK polymarket-client（polymarket/_internal/actions/orders/*）と同じ。
//  金額は浮動小数点誤差を避けるため整数で計算する（SDK の Decimal 計算と一致することをテストで確認）。
//

import Foundation

nonisolated enum ClobContracts {
    static let chainId = 137  // Polygon
    static let exchange = "0xE111180000d2663C0091e4f400237545B87B996B"
    static let negRiskExchange = "0xe2222d279d744050d28e00520010520000310F59"
    /// プロトコル v2 の position ID（トークン ID）用
    static let exchangeV3 = "0xe3333700cA9d93003F00f0F71f8515005F6c00Aa"

    static let orderTypeString =
        "Order(uint256 salt,address maker,address signer,uint256 tokenId,uint256 makerAmount,"
        + "uint256 takerAmount,uint8 side,uint8 signatureType,uint256 timestamp,bytes32 metadata,bytes32 builder)"

    /// デポジットウォレット（EIP-1271）用のラッパー型。参照される Order 型を末尾に連結する
    static let typedDataSignTypeString =
        "TypedDataSign(Order contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"
        + orderTypeString

    static let zeroBytes32Hex = "0x" + String(repeating: "0", count: 64)

    /// 注文先の取引所と EIP-712 ドメインのバージョン
    static func exchange(tokenId: String, negRisk: Bool) -> (address: String, version: String) {
        if isV2PositionId(tokenId) { return (exchangeV3, "3") }
        return (negRisk ? negRiskExchange : exchange, "2")
    }

    /// uint256 のビット 40〜103 がすべて 0 ならプロトコル v2 の position ID
    static func isV2PositionId(_ tokenId: String) -> Bool {
        guard let bytes = try? ABI.uint256(tokenId) else { return false }
        return bytes[19...26].allSatisfy { $0 == 0 }
    }
}

/// 資金を保有するウォレットの種類（Order.signatureType）
nonisolated enum WalletSignatureType: Int, Codable, CaseIterable, Sendable {
    /// 秘密鍵のアドレス自体が資金を保有
    case eoa = 0
    /// Polymarket のプロキシウォレット（メールログイン）
    case polyProxy = 1
    /// Polymarket の Gnosis Safe（ブラウザウォレットでログイン、旧来のアカウント）
    case gnosisSafe = 2
    /// Polymarket のデポジットウォレット（新しいアカウント、EIP-1271 署名）
    case depositWallet = 3

    var label: String {
        switch self {
        case .eoa: "EOA（秘密鍵のアドレスで直接保有）"
        case .polyProxy: "Polymarket プロキシウォレット"
        case .gnosisSafe: "Polymarket Safe"
        case .depositWallet: "Polymarket デポジットウォレット"
        }
    }
}

nonisolated enum ClobOrderError: LocalizedError {
    case invalidTickSize(String)
    case priceOutOfRange(min: Double, max: Double)
    case priceNotOnTick(Double)
    case sizeTooSmall
    case amountTooSmall
    case noLiquidity
    case insufficientLiquidity

    var errorDescription: String? {
        switch self {
        case .invalidTickSize(let tick): "未対応のティックサイズです: \(tick)"
        case .priceOutOfRange(let min, let max): String(format: "価格は %.4g〜%.4g の範囲で指定してください", min, max)
        case .priceNotOnTick(let tick): String(format: "価格は %.4g 刻みで指定してください", tick)
        case .sizeTooSmall: "数量が小さすぎます（0.01 以上）"
        case .amountTooSmall: "注文金額が小さすぎます"
        case .noLiquidity: "板に注文がありません"
        case .insufficientLiquidity: "板の厚みが足りず全量を約定できません"
        }
    }
}

/// マーケットのティックサイズと金額の丸め桁数（SDK の _ROUNDING_BY_TICK）
nonisolated struct ClobTick: Equatable, Sendable {
    /// 0.0001 単位のティック幅（0.01 → 100）
    let units: Int64
    /// 金額（USDC / 株）の小数桁数
    let amountDecimals: Int

    static let supported: [(String, ClobTick)] = [
        ("0.1", ClobTick(units: 1000, amountDecimals: 3)),
        ("0.01", ClobTick(units: 100, amountDecimals: 4)),
        ("0.005", ClobTick(units: 50, amountDecimals: 5)),
        ("0.0025", ClobTick(units: 25, amountDecimals: 6)),
        ("0.001", ClobTick(units: 10, amountDecimals: 5)),
        ("0.0001", ClobTick(units: 1, amountDecimals: 6)),
    ]

    var value: Double { Double(units) / 10_000 }

    init(units: Int64, amountDecimals: Int) {
        self.units = units
        self.amountDecimals = amountDecimals
    }

    /// "0.01" や 0.01 のような API の値から
    init(_ tickSize: String) throws {
        guard let value = Double(tickSize),
              let match = Self.supported.first(where: { abs($0.1.value - value) < 1e-9 })
        else { throw ClobOrderError.invalidTickSize(tickSize) }
        self = match.1
    }
}

nonisolated struct ClobOrderAmounts: Equatable, Sendable {
    /// 6 桁小数の整数表現（USDC / 条件付きトークンとも 6 decimals）
    let makerAmount: Int64
    let takerAmount: Int64
}

/// CLOB `POST /order` の `order` フィールド（V2）
nonisolated struct SignedClobOrder: Codable, Equatable, Sendable {
    let builder: String
    let expiration: String
    let maker: String
    let makerAmount: String
    let metadata: String
    let salt: Int
    let side: String
    let signature: String
    let signatureType: Int
    let signer: String
    let takerAmount: String
    let timestamp: String
    let tokenId: String
}

nonisolated struct ClobOrderParameters: Sendable {
    let tokenId: String
    let side: OrderSide
    let amounts: ClobOrderAmounts
    /// 資金保有アドレス（Order.maker）
    let wallet: String
    let signatureType: WalletSignatureType
    let negRisk: Bool
    var salt = Int.random(in: 1..<(1 << 53))
    /// ミリ秒
    var timestamp = Int64(Date().timeIntervalSince1970 * 1000)
}

/// 板（CLOB `GET /book`）
nonisolated struct ClobOrderBook: Decodable, Sendable {
    nonisolated struct Level: Decodable, Sendable {
        let price: Double
        let size: Double

        enum CodingKeys: String, CodingKey { case price, size }

        init(price: Double, size: Double) {
            self.price = price
            self.size = size
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            price = c.decodeLossyDouble(forKey: .price) ?? 0
            size = c.decodeLossyDouble(forKey: .size) ?? 0
        }
    }

    /// 安い順（最良の買い気配が末尾）
    let bids: [Level]
    /// 高い順（最良の売り気配が末尾）
    let asks: [Level]
    let tickSize: String
    let negRisk: Bool
    let minOrderSize: Double?

    enum CodingKeys: String, CodingKey {
        case bids, asks
        case tickSize = "tick_size"
        case negRisk = "neg_risk"
        case minOrderSize = "min_order_size"
    }

    init(bids: [Level], asks: [Level], tickSize: String, negRisk: Bool, minOrderSize: Double?) {
        self.bids = bids
        self.asks = asks
        self.tickSize = tickSize
        self.negRisk = negRisk
        self.minOrderSize = minOrderSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bids = c.decodeLossyArray(Level.self, forKey: .bids)
        asks = c.decodeLossyArray(Level.self, forKey: .asks)
        tickSize = c.decodeLossyString(forKey: .tickSize) ?? "0.01"
        negRisk = c.decodeLossyBool(forKey: .negRisk) ?? false
        minOrderSize = c.decodeLossyDouble(forKey: .minOrderSize)
    }

    var bestBid: Double? { bids.last?.price }
    var bestAsk: Double? { asks.last?.price }
}

nonisolated enum ClobOrderBuilder {
    private static func pow10(_ exponent: Int) -> Int64 {
        (0..<exponent).reduce(Int64(1)) { value, _ in value * 10 }
    }

    /// 価格を 0.0001 単位の整数に（範囲外・ティック外ならエラー）
    static func priceUnits(_ price: Double, tick: ClobTick) throws -> Int64 {
        let units = Int64((price * 10_000).rounded())
        guard units >= tick.units, units <= 10_000 - tick.units else {
            throw ClobOrderError.priceOutOfRange(min: tick.value, max: 1 - tick.value)
        }
        guard units % tick.units == 0 else { throw ClobOrderError.priceNotOnTick(tick.value) }
        return units
    }

    /// 0.01 単位の整数に切り捨て
    static func cents(_ value: Double) throws -> Int64 {
        let cents = Int64((value * 100 + 1e-7).rounded(.down))
        guard cents > 0 else { throw ClobOrderError.sizeTooSmall }
        return cents
    }

    /// 指値注文（GTC）。size は株数。BUY: maker=USDC, taker=株 / SELL: maker=株, taker=USDC
    static func limitAmounts(side: OrderSide, price: Double, size: Double, tick: ClobTick) throws -> ClobOrderAmounts {
        let price = try priceUnits(price, tick: tick)
        let size = try cents(size)
        let shares = size * 10_000
        let notional = size * price
        return side == .buy
            ? ClobOrderAmounts(makerAmount: notional, takerAmount: shares)
            : ClobOrderAmounts(makerAmount: shares, takerAmount: notional)
    }

    /// 成行注文（FAK/FOK）。amount は BUY なら支払う USDC、SELL なら売る株数
    static func marketAmounts(side: OrderSide, price: Double, amount: Double, tick: ClobTick) throws -> ClobOrderAmounts {
        let price = try priceUnits(price, tick: tick)
        let amount = try cents(amount)
        guard side == .buy else {
            return ClobOrderAmounts(makerAmount: amount * 10_000, takerAmount: amount * price)
        }
        // 株数 = 支払額 / 価格。SDK と同様に (小数桁+4) で切り上げてから小数桁で切り捨てる
        let decimals = tick.amountDecimals
        let numerator = Int128(amount) * 100 * Int128(pow10(decimals + 4))
        let ceiled = (numerator + Int128(price) - 1) / Int128(price)
        let shares = Int64(ceiled / 10_000) * pow10(6 - decimals)
        guard shares > 0 else { throw ClobOrderError.amountTooSmall }
        return ClobOrderAmounts(makerAmount: amount * 10_000, takerAmount: shares)
    }

    /// 成行注文の約定価格を板から決める（必要数量に届く最も不利な価格）
    static func marketPrice(book: ClobOrderBook, side: OrderSide, amount: Double, type: OrderType) throws -> Double {
        let levels = side == .buy ? book.asks : book.bids
        guard let worst = levels.first else { throw ClobOrderError.noLiquidity }
        var cumulative = 0.0
        for level in levels.reversed() {
            cumulative += side == .buy ? level.size * level.price : level.size
            if cumulative >= amount { return level.price }
        }
        if type == .fok { throw ClobOrderError.insufficientLiquidity }
        return worst.price
    }

    static func build(_ parameters: ClobOrderParameters, signer: EthereumSigner) throws -> SignedClobOrder {
        let wallet = try EthereumAddress.checksummed(parameters.wallet)
        let isDepositWallet = parameters.signatureType == .depositWallet
        // デポジットウォレットはウォレット自身が署名者（EIP-1271 で所有者の署名を検証）
        let orderSigner = isDepositWallet ? wallet : signer.address
        let zero = Data(count: 32)

        let message = EIP712Struct(
            typeString: ClobContracts.orderTypeString,
            values: [
                .uint(String(parameters.salt)),
                .address(wallet),
                .address(orderSigner),
                .uint(parameters.tokenId),
                .uint(String(parameters.amounts.makerAmount)),
                .uint(String(parameters.amounts.takerAmount)),
                .uint(parameters.side == .buy ? "0" : "1"),
                .uint(String(parameters.signatureType.rawValue)),
                .uint(String(parameters.timestamp)),
                .bytes32(zero),
                .bytes32(zero),
            ])
        let exchange = ClobContracts.exchange(tokenId: parameters.tokenId, negRisk: parameters.negRisk)
        let domain = try EIP712.domainSeparator(
            name: "Polymarket CTF Exchange", version: exchange.version, chainId: ClobContracts.chainId,
            verifyingContract: exchange.address)

        let signature: Data
        if isDepositWallet {
            let contents = try message.hashStruct()
            let wrapper = EIP712Struct(
                typeString: ClobContracts.typedDataSignTypeString,
                values: [
                    .bytes32(contents),
                    .string("DepositWallet"),
                    .string("1"),
                    .uint(String(ClobContracts.chainId)),
                    .address(wallet),
                    .bytes32(zero),
                ])
            let raw = try signer.sign(digest: EIP712.digest(domainSeparator: domain, message: wrapper))
            // ERC-7739 形式: 署名 ‖ ドメインセパレータ ‖ contents ハッシュ ‖ 型文字列 ‖ 型文字列長(2バイト)
            let typeBytes = Data(ClobContracts.orderTypeString.utf8)
            let length = Data([UInt8(typeBytes.count >> 8), UInt8(typeBytes.count & 0xFF)])
            signature = raw + domain + contents + typeBytes + length
        } else {
            signature = try signer.sign(digest: EIP712.digest(domainSeparator: domain, message: message))
        }

        return SignedClobOrder(
            builder: ClobContracts.zeroBytes32Hex,
            expiration: "0",
            maker: wallet,
            makerAmount: String(parameters.amounts.makerAmount),
            metadata: ClobContracts.zeroBytes32Hex,
            salt: parameters.salt,
            side: parameters.side.rawValue,
            signature: signature.prefixedHex,
            signatureType: parameters.signatureType.rawValue,
            signer: orderSigner,
            takerAmount: String(parameters.amounts.takerAmount),
            timestamp: String(parameters.timestamp),
            tokenId: parameters.tokenId)
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
