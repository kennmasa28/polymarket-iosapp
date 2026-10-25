//
//  EthereumPrimitives.swift
//  polymarket-iosapp
//
//  16進変換、ABI エンコード、EIP-712 ハッシュ、secp256k1 署名。
//  署名そのものは libsecp256k1（swift-secp256k1 の P256K）に任せ、RFC 6979 の決定的ナンスを使う。
//

import Foundation
import P256K

nonisolated enum EthereumError: LocalizedError {
    case invalidHex
    case invalidPrivateKey
    case invalidAddress(String)
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .invalidHex: "16進文字列が不正です"
        case .invalidPrivateKey: "秘密鍵が不正です（64桁の16進数）"
        case .invalidAddress(let value): "アドレスが不正です: \(value)"
        case .invalidNumber(let value): "数値が不正です: \(value)"
        }
    }
}

// MARK: - Hex

nonisolated extension Data {
    init(hex: String) throws {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("0x") || string.hasPrefix("0X") { string.removeFirst(2) }
        guard string.count % 2 == 0 else { throw EthereumError.invalidHex }
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { throw EthereumError.invalidHex }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    var prefixedHex: String { "0x" + hexString }
}

// MARK: - ABI

nonisolated enum ABI {
    /// 10進文字列を 32 バイトのビッグエンディアン uint256 に変換
    static func uint256(_ decimal: String) throws -> Data {
        guard !decimal.isEmpty, decimal.allSatisfy(\.isASCII), decimal.allSatisfy(\.isNumber) else {
            throw EthereumError.invalidNumber(decimal)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        for character in decimal.utf8 {
            var carry = UInt32(character - 48)
            for index in stride(from: 31, through: 0, by: -1) {
                let value = UInt32(bytes[index]) * 10 + carry
                bytes[index] = UInt8(value & 0xFF)
                carry = value >> 8
            }
            guard carry == 0 else { throw EthereumError.invalidNumber(decimal) }
        }
        return Data(bytes)
    }

    static func uint256<T: BinaryInteger>(_ value: T) -> Data {
        // 10進文字列化は常に成功する
        (try? uint256(String(value))) ?? Data(count: 32)
    }

    /// 20 バイトのアドレスを左ゼロ埋めで 32 バイトに
    static func address(_ hex: String) throws -> Data {
        let raw = try addressBytes(hex)
        return Data(count: 12) + raw
    }

    static func addressBytes(_ hex: String) throws -> Data {
        guard let raw = try? Data(hex: hex), raw.count == 20 else { throw EthereumError.invalidAddress(hex) }
        return raw
    }
}

// MARK: - Address

nonisolated enum EthereumAddress {
    /// EIP-55 チェックサム付きアドレス
    static func checksummed(_ hex: String) throws -> String {
        let lower = try ABI.addressBytes(hex).hexString
        let hash = Keccak256.hash(lower).hexString
        var result = "0x"
        for (character, hashCharacter) in zip(lower, hash) {
            if character.isLetter, let nibble = Int(String(hashCharacter), radix: 16), nibble >= 8 {
                result += character.uppercased()
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func isValid(_ hex: String) -> Bool {
        (try? ABI.addressBytes(hex)) != nil
    }

    static let zero = "0x0000000000000000000000000000000000000000"
}

// MARK: - EIP-712

nonisolated enum EIP712Value {
    case address(String)
    case uint(String)
    case string(String)

    func encoded() throws -> Data {
        switch self {
        case .address(let value): return try ABI.address(value)
        case .uint(let value): return try ABI.uint256(value)
        case .string(let value): return Keccak256.hash(value)
        }
    }
}

nonisolated struct EIP712Struct {
    /// 例: "Order(uint256 salt,address maker,...)"
    let typeString: String
    let values: [EIP712Value]

    func hashStruct() throws -> Data {
        var data = Keccak256.hash(typeString)
        for value in values {
            data += try value.encoded()
        }
        return Keccak256.hash(data)
    }
}

nonisolated enum EIP712 {
    static func domainSeparator(name: String, version: String, chainId: Int, verifyingContract: String?) throws -> Data {
        if let verifyingContract {
            return try EIP712Struct(
                typeString: "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)",
                values: [.string(name), .string(version), .uint(String(chainId)), .address(verifyingContract)]
            ).hashStruct()
        }
        return try EIP712Struct(
            typeString: "EIP712Domain(string name,string version,uint256 chainId)",
            values: [.string(name), .string(version), .uint(String(chainId))]
        ).hashStruct()
    }

    /// keccak256(0x19 0x01 ‖ domainSeparator ‖ hashStruct(message))
    static func digest(domainSeparator: Data, message: EIP712Struct) throws -> Data {
        Keccak256.hash(Data([0x19, 0x01]) + domainSeparator + (try message.hashStruct()))
    }
}

// MARK: - Signer

/// メモリ上で秘密鍵を保持して署名する。ロック時は破棄する。
nonisolated struct EthereumSigner {
    let address: String
    private let privateKey: Data

    init(privateKeyHex: String) throws {
        guard let key = try? Data(hex: privateKeyHex), key.count == 32 else {
            throw EthereumError.invalidPrivateKey
        }
        try self.init(privateKey: key)
    }

    init(privateKey: Data) throws {
        guard privateKey.count == 32,
              let key = try? P256K.Recovery.PrivateKey(dataRepresentation: privateKey, format: .uncompressed)
        else { throw EthereumError.invalidPrivateKey }
        // 非圧縮公開鍵（0x04 ‖ X ‖ Y）の X‖Y を keccak256 した末尾 20 バイト
        let publicKey = key.publicKey.dataRepresentation.dropFirst()
        let rawAddress = Keccak256.hash(publicKey).suffix(20)
        self.address = try EthereumAddress.checksummed(rawAddress.prefixedHex)
        self.privateKey = privateKey
    }

    /// 32 バイトのダイジェストに署名し、r ‖ s ‖ v（v = 27 + recoveryId）の 65 バイトを返す
    func sign(digest: Data) throws -> Data {
        guard digest.count == 32 else { throw EthereumError.invalidHex }
        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey, format: .uncompressed)
        let signature = try key.signature(for: HashDigest(Array(digest)))
        let compact = try signature.compactRepresentation
        return compact.signature + Data([UInt8(27 + compact.recoveryId)])
    }
}
