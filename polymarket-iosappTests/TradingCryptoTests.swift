//
//  TradingCryptoTests.swift
//  polymarket-iosappTests
//
//  期待値は Polymarket 公式の py-clob-client / py-order-utils と eth-account で生成したもの。
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

struct ClobOrderTests {
    @Test func signsBuyOrderLikePyClobClient() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .buy,
                amounts: ClobOrderAmounts(makerAmount: 5_200_000, takerAmount: 10_000_000),
                maker: "0x9F2fe3f5C2E7B4A3C6f1B1d2e3A4b5c6D7E8F901",
                signatureType: .gnosisSafe, feeRateBps: 0, negRisk: false, salt: 123_456_789),
            signer: signer)
        #expect(order.maker == "0x9f2fe3f5C2E7b4A3C6f1B1D2E3a4B5C6D7e8f901")
        #expect(order.signer == testAddress)
        #expect(order.side == "BUY")
        #expect(order.signatureType == 2)
        #expect(order.signature == "0x3619966518bcb04210dc37302b612943b56d36e876fb4327a8bd428eca7a2483302465aa9067de7aa6a5fea6b05a5abfd9466ea3b59ceac0ccc79843643b8a371b")
    }

    @Test func signsNegRiskSellOrderLikePyClobClient() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .sell,
                amounts: ClobOrderAmounts(makerAmount: 2_500_000, takerAmount: 1_750_000),
                maker: testAddress, signatureType: .eoa, feeRateBps: 0, negRisk: true, salt: 42),
            signer: signer)
        #expect(order.signature == "0x95ded667a00a7e5541f8f7e6595943db177b0ffd742dc3650b51d5849d9193825b8b4c397079e53998632b0ec8877fb52536878e878f60b26170b7a2f990e7b61c")
    }

    @Test func signsClobAuthLikePyClobClient() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let signature = try ClobOrderBuilder.clobAuthSignature(signer: signer, timestamp: 1_700_000_000, nonce: 0)
        #expect(signature == "0xaa541ee28fab54d848c37e4d6c69ce3bca78c3c67bbfe102e9736de2589f18573619c82c113a99cbd31a576b4166a9b2964de7a6845770dc4beb1ad757c4ae1d1b")
    }

    @Test func buildsHmacLikePyClobClient() throws {
        let signature = try ClobAuthHeaders.hmacSignature(
            secret: "c2VjcmV0LWtleS1mb3ItdGVzdGluZy0xMjM0NTY3OA==", timestamp: 1_700_000_000,
            method: "DELETE", path: "/order", body: #"{"orderID":"0xabc"}"#)
        #expect(signature == "5rflqJIxf-wy_4baXpGnEmn9WspX6C9zAOhNhuNaOeo=")
    }

    @Test func computesAmountsLikePyClobClient() throws {
        #expect(try ClobOrderBuilder.limitAmounts(side: .buy, price: 0.52, size: 10, tickSize: "0.01")
            == ClobOrderAmounts(makerAmount: 5_200_000, takerAmount: 10_000_000))
        #expect(try ClobOrderBuilder.limitAmounts(side: .sell, price: 0.613, size: 7.333, tickSize: "0.001")
            == ClobOrderAmounts(makerAmount: 7_330_000, takerAmount: 4_493_290))
        // 成行 BUY: 18.2株 × 57¢ = $10.374 → $10.37 に切り捨て（py-clob-client の market order と同じ）
        #expect(try ClobOrderBuilder.marketAmounts(side: .buy, price: 0.57, size: 18.2, tickSize: "0.01")
            == ClobOrderAmounts(makerAmount: 10_370_000, takerAmount: 18_192_900))
    }

    @Test func rejectsOutOfRangePrice() {
        #expect(throws: ClobOrderError.self) {
            try ClobOrderBuilder.limitAmounts(side: .buy, price: 1.0, size: 10, tickSize: "0.01")
        }
        #expect(throws: ClobOrderError.self) {
            try ClobOrderBuilder.limitAmounts(side: .buy, price: 0.5, size: 0.001, tickSize: "0.01")
        }
    }

    @Test func encodesOrderBodyWithExpectedFields() throws {
        let signer = try EthereumSigner(privateKeyHex: testPrivateKey)
        let order = try ClobOrderBuilder.build(
            ClobOrderParameters(
                tokenId: testTokenId, side: .buy,
                amounts: ClobOrderAmounts(makerAmount: 1, takerAmount: 2),
                maker: testAddress, signatureType: .eoa, feeRateBps: 0, negRisk: false, salt: 7),
            signer: signer)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(order)) as? [String: Any]
        #expect(json?["salt"] as? Int == 7)
        #expect(json?["tokenId"] as? String == testTokenId)
        #expect(json?["signatureType"] as? Int == 0)
        #expect(json?["side"] as? String == "BUY")
    }
}

struct FavoriteTests {
    @Test func shortensTitles() {
        #expect(FavoriteMarket.shortTitle(from: "Will Bitcoin reach $150k?") == "Bitcoin reach $150k")
        #expect(FavoriteMarket.shortTitle(from: String(repeating: "a", count: 40)).count == 22)
    }
}
