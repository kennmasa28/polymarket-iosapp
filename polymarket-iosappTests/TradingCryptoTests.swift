//
//  TradingCryptoTests.swift
//  polymarket-iosappTests
//
//  期待値は Polymarket 公式 SDK（polymarket-client / py-clob-client）と eth-account で生成したもの。
//  署名は RFC 6979 の決定的ナンスなので、同じ入力なら同じ署名になる。
//

import Foundation
import Testing
@testable import polymarket_iosapp

/// テスト専用の公開済みサンプル鍵（実資金は入っていない）
private let testPrivateKey = "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
private let testAddress = "0x2c7536E3605D9C16a7a3D7b1898e529396a65c23"
private let testTokenId = "71321045679252212594626385532706912750332728571942532289631379312455583992563"

struct KeccakTests {
    @Test func knownVectors() {
        #expect(Keccak256.hash(Data()).hexString == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        #expect(Keccak256.hash("abc").hexString == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        // 複数ブロック（512 バイト）
        let input = Data((0..<512).map { UInt8($0 % 256) })
        #expect(Keccak256.hash(input).hexString == "f55ba327291604f0e5be6651752398b7be2331aad65f5763ce067df95cc13be1")
    }
}

struct EthereumTests {
    @Test func derivesChecksummedAddress() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        #expect(signer.address == testAddress)
    }

    @Test func checksumsAddress() throws {
        #expect(try EthereumAddress.checksummed("0x9f2fe3f5c2e7b4a3c6f1b1d2e3a4b5c6d7e8f901")
            == "0x9f2fe3f5C2E7b4A3C6f1B1D2E3a4B5C6D7e8f901")
    }

    @Test func encodesLargeUint256() throws {
        let encoded = try ABI.uint256(testTokenId)
        #expect(encoded.count == 32)
        #expect(try ABI.uint256("255").hexString.hasSuffix("00ff"))
        #expect(throws: EthereumError.self) { try ABI.uint256("12a") }
    }

    @Test func rejectsInvalidPrivateKey() {
        #expect(throws: EthereumError.self) { try EthereumSigner(privateKeyHex: "0x1234") }
    }
}

/// 期待値は公式 SDK polymarket-client 0.15.0（CLOB V2）の手順と eth-account の EIP-712 実装で生成
struct ClobOrderV2Tests {
    private let safeWallet = "0x907C14d6Cea8e8FC78dD3dB152F0a93f43276b4D"
    private let depositWallet = "0xd2C50736787e5eeefA6c2E81496AE56d51D6b7B1"

    @Test func derivesWalletAddresses() throws {
        #expect(try WalletDerivation.proxyWallet(signer: testAddress) == "0x96a9892De6A11FE0B18Cf63373B9763055EcA8a6")
        #expect(try WalletDerivation.safeWallet(signer: testAddress) == safeWallet)
        #expect(try WalletDerivation.uupsDepositWallet(signer: testAddress) == "0xfd5041047Be8C192C725A66228F141196Fa3cF9C")
        #expect(try WalletDerivation.beaconDepositWallet(signer: testAddress) == depositWallet)
    }

    @Test func detectsWalletType() throws {
        #expect(try WalletDerivation.detect(signer: testAddress, wallet: testAddress) == .eoa)
        #expect(try WalletDerivation.detect(signer: testAddress, wallet: safeWallet) == .gnosisSafe)
        #expect(try WalletDerivation.detect(signer: testAddress, wallet: depositWallet.lowercased()) == .depositWallet)
        #expect(try WalletDerivation.detect(signer: testAddress, wallet: "0x96a9892De6A11FE0B18Cf63373B9763055EcA8a6") == .polyProxy)
        #expect(try WalletDerivation.detect(signer: testAddress, wallet: "0x0000000000000000000000000000000000000001") == nil)
    }

    @Test func signsSafeBuyOrder() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .buy,
                amounts: ClobOrderAmounts(makerAmount: 5_200_000, takerAmount: 10_000_000),
                wallet: safeWallet, signatureType: .gnosisSafe, negRisk: false,
                salt: 123_456_789, timestamp: 1_761_900_000_000),
            signer: signer)
        #expect(order.maker == safeWallet)
        #expect(order.signer == testAddress)
        #expect(order.signatureType == 2)
        #expect(order.timestamp == "1761900000000")
        #expect(order.signature == "0x85bc4b74564ce20ba01c4139b6d93b6aa51f45b6d28f0215849fcfffc183dc926eb36b433919434206ffe5c89d0c0fe3d7838793d34dc1bdad5303dec6e5f4c81c")
    }

    @Test func signsEoaNegRiskSellOrder() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .sell,
                amounts: ClobOrderAmounts(makerAmount: 2_500_000, takerAmount: 1_750_000),
                wallet: testAddress, signatureType: .eoa, negRisk: true,
                salt: 42, timestamp: 1_761_900_000_123),
            signer: signer)
        #expect(order.signature == "0xa856e526e102cff4602ef24348ec1b7db42e37dcbcc3328b6b69ee7c4d5886737395a24ed08b5d6c4e5bb907bea30a692dc415d1287af14936d802d2f2cefb111c")
    }

    @Test func signsDepositWalletOrderWithTrailer() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .buy,
                amounts: ClobOrderAmounts(makerAmount: 10_000_000, takerAmount: 17_543_859),
                wallet: depositWallet, signatureType: .depositWallet, negRisk: false,
                salt: 987_654_321, timestamp: 1_761_900_000_456),
            signer: signer)
        #expect(order.signer == depositWallet)
        #expect(order.signatureType == 3)
        #expect(order.signature == "0xa05e16a3ac8a5af08bbd357368d8d394599eb366a21840cd6cf24beb70354b383107ab1e214aecf7d2bc6bbcda5b3f93d87ae7c6674ee2f30ab04eaa72d2a9061c3264e159346253e26a64e00b69032db0e7d32f94628de3e6eecb50304d7af3d232c8b5e0f1fbd53871c0dd0622012321c5e89404d63cff7a89b325b5fc34e56a4f726465722875696e743235362073616c742c61646472657373206d616b65722c61646472657373207369676e65722c75696e7432353620746f6b656e49642c75696e74323536206d616b6572416d6f756e742c75696e743235362074616b6572416d6f756e742c75696e743820736964652c75696e7438207369676e6174757265547970652c75696e743235362074696d657374616d702c62797465733332206d657461646174612c62797465733332206275696c6465722900ba")
    }

    @Test func signsClobAuthLikeSdk() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let signature = try ClobOrderBuilder.clobAuthSignature(signer: signer, timestamp: 1_700_000_000, nonce: 0)
        #expect(signature == "0xaa541ee28fab54d848c37e4d6c69ce3bca78c3c67bbfe102e9736de2589f18573619c82c113a99cbd31a576b4166a9b2964de7a6845770dc4beb1ad757c4ae1d1b")
    }

    @Test func buildsHmacLikeSdk() throws {
        let signature = try ClobAuthHeaders.hmacSignature(
            secret: "c2VjcmV0LWtleS1mb3ItdGVzdGluZy0xMjM0NTY3OA==", timestamp: 1_700_000_000,
            method: "DELETE", path: "/order", body: #"{"orderID":"0xabc"}"#)
        #expect(signature == "5rflqJIxf-wy_4baXpGnEmn9WspX6C9zAOhNhuNaOeo=")
    }

    @Test func computesAmountsLikeSdk() throws {
        let cent = try ClobTick("0.01")
        // 成行 BUY: $10 を 57¢ で → 17.5438 株
        #expect(try ClobOrderBuilder.marketAmounts(side: .buy, price: 0.57, amount: 10, tick: cent)
            == ClobOrderAmounts(makerAmount: 10_000_000, takerAmount: 17_543_800))
        #expect(try ClobOrderBuilder.marketAmounts(side: .buy, price: 0.005, amount: 25.5, tick: ClobTick("0.005"))
            == ClobOrderAmounts(makerAmount: 25_500_000, takerAmount: 5_100_000_000))
        // 成行 SELL: 12.345 株 → 12.34 株に切り捨て
        #expect(try ClobOrderBuilder.marketAmounts(side: .sell, price: 0.43, amount: 12.345, tick: cent)
            == ClobOrderAmounts(makerAmount: 12_340_000, takerAmount: 5_306_200))
        #expect(try ClobOrderBuilder.limitAmounts(side: .buy, price: 0.525, size: 10, tick: ClobTick("0.005"))
            == ClobOrderAmounts(makerAmount: 5_250_000, takerAmount: 10_000_000))
    }

    @Test func rejectsInvalidPrices() {
        #expect(throws: ClobOrderError.self) {
            try ClobOrderBuilder.limitAmounts(side: .buy, price: 1.0, size: 10, tick: ClobTick("0.01"))
        }
        #expect(throws: ClobOrderError.self) {
            try ClobOrderBuilder.limitAmounts(side: .buy, price: 0.523, size: 10, tick: ClobTick("0.01"))
        }
        #expect(throws: ClobOrderError.self) { try ClobTick("0.02") }
    }

    @Test func picksMarketPriceFromBook() throws {
        // asks は高い順（最良の売り気配が末尾）
        let book = ClobOrderBook(
            bids: [.init(price: 0.40, size: 100), .init(price: 0.45, size: 10)],
            asks: [.init(price: 0.60, size: 100), .init(price: 0.55, size: 10)],
            tickSize: "0.01", negRisk: false, minOrderSize: 5)
        // $5 は 0.55 の板（$5.5 分）で足りる
        #expect(try ClobOrderBuilder.marketPrice(book: book, side: .buy, amount: 5, type: .fak) == 0.55)
        // $20 は 0.60 まで必要
        #expect(try ClobOrderBuilder.marketPrice(book: book, side: .buy, amount: 20, type: .fak) == 0.60)
        // 売り 50 株は 0.40 まで必要
        #expect(try ClobOrderBuilder.marketPrice(book: book, side: .sell, amount: 50, type: .fak) == 0.40)
        #expect(throws: ClobOrderError.self) {
            try ClobOrderBuilder.marketPrice(book: book, side: .sell, amount: 500, type: .fok)
        }
    }

    @Test func routesToV2Exchanges() {
        #expect(ClobContracts.exchange(tokenId: testTokenId, negRisk: false).address == ClobContracts.exchange)
        #expect(ClobContracts.exchange(tokenId: testTokenId, negRisk: true).address == ClobContracts.negRiskExchange)
        #expect(ClobContracts.exchange(tokenId: testTokenId, negRisk: false).version == "2")
        #expect(!ClobContracts.isV2PositionId(testTokenId))
    }

    @Test func encodesV2OrderBody() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .buy,
                amounts: ClobOrderAmounts(makerAmount: 1, takerAmount: 2),
                wallet: testAddress, signatureType: .eoa, negRisk: false, salt: 7, timestamp: 1),
            signer: signer)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(order)) as? [String: Any]
        #expect(json?["salt"] as? Int == 7)
        #expect(json?["tokenId"] as? String == testTokenId)
        #expect(json?["metadata"] as? String == ClobContracts.zeroBytes32Hex)
        #expect(json?["builder"] as? String == ClobContracts.zeroBytes32Hex)
        #expect(json?["timestamp"] as? String == "1")
        #expect(json?["taker"] == nil)
        #expect(json?["nonce"] == nil)
    }
}

struct FavoriteTests {
    @Test func shortensTitles() {
        #expect(FavoriteMarket.shortTitle(from: "Will Bitcoin reach $150k?") == "Bitcoin reach $150k")
        #expect(FavoriteMarket.shortTitle(from: String(repeating: "a", count: 40)).count == 22)
    }
}
