//
//  ClobTradingClient.swift
//  polymarket-iosapp
//
//  Polymarket CLOB の認証付き API。
//   - L1: EIP-712 (ClobAuth) 署名で API キーを作成/導出
//   - L2: API シークレットによる HMAC-SHA256 ヘッダで注文・取消・残高照会
//

import CryptoKit
import Foundation

/// CLOB の API 認証情報（Keychain に保存）
nonisolated struct ClobCredentials: Codable, Equatable, Sendable {
    let apiKey: String
    let secret: String
    let passphrase: String

    enum CodingKeys: String, CodingKey {
        case apiKey, secret, passphrase
    }
}

nonisolated struct ClobOpenOrder: Decodable, Identifiable, Sendable {
    let id: String
    let status: String?
    let assetId: String?
    let side: String?
    let price: Double?
    let originalSize: Double?
    let sizeMatched: Double?
    let outcome: String?

    enum CodingKeys: String, CodingKey {
        case id, status, side, price, outcome
        case assetId = "asset_id"
        case originalSize = "original_size"
        case sizeMatched = "size_matched"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.requireLossyString(forKey: .id)
        status = c.decodeLossyString(forKey: .status)
        assetId = c.decodeLossyString(forKey: .assetId)
        side = c.decodeLossyString(forKey: .side)
        price = c.decodeLossyDouble(forKey: .price)
        originalSize = c.decodeLossyDouble(forKey: .originalSize)
        sizeMatched = c.decodeLossyDouble(forKey: .sizeMatched)
        outcome = c.decodeLossyString(forKey: .outcome)
    }
}

nonisolated struct ClobPostOrderResponse: Decodable, Sendable {
    let success: Bool?
    let errorMsg: String?
    let orderID: String?
    let status: String?
}

// MARK: - Response / request bodies

nonisolated struct ClobTickSizeResponse: Decodable {
    let value: Double?
    enum CodingKeys: String, CodingKey { case value = "minimum_tick_size" }
    init(from decoder: Decoder) throws {
        value = try decoder.container(keyedBy: CodingKeys.self).decodeLossyDouble(forKey: .value)
    }
}

nonisolated struct ClobNegRiskResponse: Decodable {
    let negRisk: Bool?
    enum CodingKeys: String, CodingKey { case negRisk = "neg_risk" }
}

nonisolated struct ClobFeeRateResponse: Decodable {
    let baseFee: Double?
    enum CodingKeys: String, CodingKey { case baseFee = "base_fee" }
    init(from decoder: Decoder) throws {
        baseFee = try decoder.container(keyedBy: CodingKeys.self).decodeLossyDouble(forKey: .baseFee)
    }
}

nonisolated struct ClobPostOrderBody: Encodable {
    let order: SignedClobOrder
    let owner: String
    let orderType: String
    let postOnly: Bool
}

nonisolated struct ClobOrdersPage: Decodable {
    let data: [Lossy<ClobOpenOrder>]
    let nextCursor: String?
    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

nonisolated struct ClobBalanceResponse: Decodable {
    let balance: Double?
    enum CodingKeys: String, CodingKey { case balance }
    init(from decoder: Decoder) throws {
        balance = try decoder.container(keyedBy: CodingKeys.self).decodeLossyDouble(forKey: .balance)
    }
}

nonisolated enum ClobAuthHeaders {
    /// HMAC-SHA256(base64url_decode(secret), timestamp + method + path + body) を base64url で返す
    static func hmacSignature(secret: String, timestamp: Int, method: String, path: String, body: String?) throws -> String {
        var base64 = secret.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let key = Data(base64Encoded: base64) else { throw EthereumError.invalidHex }
        let message = "\(timestamp)\(method)\(path)\(body ?? "")"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    static func level2(
        address: String, credentials: ClobCredentials, method: String, path: String, body: String?,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) throws -> [String: String] {
        let signature = try hmacSignature(
            secret: credentials.secret, timestamp: timestamp, method: method, path: path, body: body)
        return [
            "POLY_ADDRESS": address,
            "POLY_SIGNATURE": signature,
            "POLY_TIMESTAMP": String(timestamp),
            "POLY_API_KEY": credentials.apiKey,
            "POLY_PASSPHRASE": credentials.passphrase,
        ]
    }

    static func level1(signer: EthereumSigner, nonce: Int = 0, timestamp: Int = Int(Date().timeIntervalSince1970)) throws -> [String: String] {
        let signature = try ClobOrderBuilder.clobAuthSignature(signer: signer, timestamp: timestamp, nonce: nonce)
        return [
            "POLY_ADDRESS": signer.address,
            "POLY_SIGNATURE": signature,
            "POLY_TIMESTAMP": String(timestamp),
            "POLY_NONCE": String(nonce),
        ]
    }
}

nonisolated struct ClobTradingClient: Sendable {
    var http = HTTPClient()
    private var baseURL: URL { ClobAPI.baseURL }

    private func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: L1

    /// API キーを新規作成し、既にあれば導出する（py-clob-client の create_or_derive_api_creds）
    func createOrDeriveCredentials(signer: EthereumSigner) async throws -> ClobCredentials {
        do {
            let data = try await http.send(
                "POST", url: try url("/auth/api-key"), headers: try ClobAuthHeaders.level1(signer: signer))
            return try decode(ClobCredentials.self, from: data)
        } catch {
            let data = try await http.send(
                "GET", url: try url("/auth/derive-api-key"), headers: try ClobAuthHeaders.level1(signer: signer))
            return try decode(ClobCredentials.self, from: data)
        }
    }

    // MARK: Public market parameters

    func tickSize(tokenId: String) async throws -> String {
        let data = try await http.send("GET", url: try url("/tick-size", query: [.init(name: "token_id", value: tokenId)]))
        let value = try decode(ClobTickSizeResponse.self, from: data).value ?? 0.01
        // 0.01 のような数値を "0.01" に正規化
        let candidates = ["0.1", "0.01", "0.001", "0.0001"]
        return candidates.min { abs(Double($0)! - value) < abs(Double($1)! - value) } ?? "0.01"
    }

    func negRisk(tokenId: String) async throws -> Bool {
        let data = try await http.send("GET", url: try url("/neg-risk", query: [.init(name: "token_id", value: tokenId)]))
        return try decode(ClobNegRiskResponse.self, from: data).negRisk ?? false
    }

    func feeRateBps(tokenId: String) async throws -> Int {
        let data = try await http.send("GET", url: try url("/fee-rate", query: [.init(name: "token_id", value: tokenId)]))
        return Int(try decode(ClobFeeRateResponse.self, from: data).baseFee ?? 0)
    }

    // MARK: L2

    func postOrder(
        _ order: SignedClobOrder, orderType: OrderType, address: String, credentials: ClobCredentials
    ) async throws -> ClobPostOrderResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let body = try encoder.encode(ClobPostOrderBody(order: order, owner: credentials.apiKey, orderType: orderType.rawValue, postOnly: false))
        let bodyString = String(decoding: body, as: UTF8.self)
        let headers = try ClobAuthHeaders.level2(
            address: address, credentials: credentials, method: "POST", path: "/order", body: bodyString)
        let data = try await http.send("POST", url: try url("/order"), headers: headers, body: body)
        let response = try decode(ClobPostOrderResponse.self, from: data)
        if response.success == false {
            throw APIError.server(status: 200, message: response.errorMsg ?? "注文が拒否されました")
        }
        return response
    }

    func cancelOrder(id: String, address: String, credentials: ClobCredentials) async throws {
        let body = try JSONEncoder().encode(["orderID": id])
        let headers = try ClobAuthHeaders.level2(
            address: address, credentials: credentials, method: "DELETE", path: "/order",
            body: String(decoding: body, as: UTF8.self))
        _ = try await http.send("DELETE", url: try url("/order"), headers: headers, body: body)
    }

    func openOrders(address: String, credentials: ClobCredentials) async throws -> [ClobOpenOrder] {
        var orders: [ClobOpenOrder] = []
        var cursor = "MA=="
        for _ in 0..<10 {
            let headers = try ClobAuthHeaders.level2(
                address: address, credentials: credentials, method: "GET", path: "/data/orders", body: nil)
            let data = try await http.send(
                "GET", url: try url("/data/orders", query: [.init(name: "next_cursor", value: cursor)]), headers: headers)
            if let page = try? JSONDecoder().decode(ClobOrdersPage.self, from: data) {
                orders += page.data.compactMap(\.value)
                guard let next = page.nextCursor, next != "LTE=", next != cursor else { break }
                cursor = next
            } else {
                orders += try decode([Lossy<ClobOpenOrder>].self, from: data).compactMap(\.value)
                break
            }
        }
        return orders
    }

    /// USDC 残高（ドル）
    func collateralBalance(
        address: String, credentials: ClobCredentials, signatureType: WalletSignatureType
    ) async throws -> Double {
        let headers = try ClobAuthHeaders.level2(
            address: address, credentials: credentials, method: "GET", path: "/balance-allowance", body: nil)
        let data = try await http.send(
            "GET",
            url: try url("/balance-allowance", query: [
                .init(name: "asset_type", value: "COLLATERAL"),
                .init(name: "signature_type", value: String(signatureType.rawValue)),
            ]),
            headers: headers)
        return (try decode(ClobBalanceResponse.self, from: data).balance ?? 0) / 1_000_000
    }
}

// MARK: - Data API: positions

nonisolated struct PMPosition: Decodable, Identifiable, Sendable {
    let asset: String
    let title: String
    let outcome: String
    let size: Double
    let avgPrice: Double
    let curPrice: Double?
    let currentValue: Double?
    let cashPnl: Double?
    let conditionId: String?

    var id: String { asset }

    enum CodingKeys: String, CodingKey {
        case asset, title, outcome, size, avgPrice, curPrice, currentValue, cashPnl, conditionId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        asset = try c.requireLossyString(forKey: .asset)
        title = c.decodeLossyString(forKey: .title) ?? ""
        outcome = c.decodeLossyString(forKey: .outcome) ?? ""
        size = c.decodeLossyDouble(forKey: .size) ?? 0
        avgPrice = c.decodeLossyDouble(forKey: .avgPrice) ?? 0
        curPrice = c.decodeLossyDouble(forKey: .curPrice)
        currentValue = c.decodeLossyDouble(forKey: .currentValue)
        cashPnl = c.decodeLossyDouble(forKey: .cashPnl)
        conditionId = c.decodeLossyString(forKey: .conditionId)
    }
}

nonisolated extension DataAPI {
    func positions(user: String) async throws -> [PMPosition] {
        let result: [Lossy<PMPosition>] = try await http.get(
            Self.baseURL, path: "positions",
            query: [.init(name: "user", value: user), .init(name: "sizeThreshold", value: "0.01")])
        return result.compactMap(\.value)
    }
}
