//
//  Keccak256.swift
//  polymarket-iosapp
//
//  Ethereum で使われる Keccak-256（SHA3-256 とはパディングが異なる 0x01 版）。
//

import Foundation

nonisolated enum Keccak256 {
    private static let rate = 136

    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]

    /// レーン (x, y) の回転量。インデックスは x + 5y
    private static let rotationOffsets: [UInt64] = [
        0, 1, 62, 28, 27,
        36, 44, 6, 55, 20,
        3, 10, 43, 25, 39,
        41, 45, 15, 21, 8,
        18, 2, 61, 56, 14,
    ]

    static func hash<D: DataProtocol>(_ input: D) -> Data {
        var bytes = [UInt8](input)
        bytes.append(0x01)
        while bytes.count % rate != 0 { bytes.append(0) }
        bytes[bytes.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        for blockStart in stride(from: 0, to: bytes.count, by: rate) {
            for lane in 0..<(rate / 8) {
                var value: UInt64 = 0
                for byte in 0..<8 {
                    value |= UInt64(bytes[blockStart + lane * 8 + byte]) << (8 * UInt64(byte))
                }
                state[lane] ^= value
            }
            permute(&state)
        }

        var output = [UInt8]()
        output.reserveCapacity(32)
        for lane in 0..<4 {
            for byte in 0..<8 {
                output.append(UInt8(truncatingIfNeeded: state[lane] >> (8 * UInt64(byte))))
            }
        }
        return Data(output)
    }

    static func hash(_ string: String) -> Data {
        hash(Data(string.utf8))
    }

    private static func rotateLeft(_ value: UInt64, _ amount: UInt64) -> UInt64 {
        amount == 0 ? value : (value << amount) | (value >> (64 - amount))
    }

    /// Keccak-f[1600]
    private static func permute(_ a: inout [UInt64]) {
        var b = [UInt64](repeating: 0, count: 25)
        var c = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            // θ
            for x in 0..<5 {
                c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
            }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotateLeft(c[(x + 1) % 5], 1)
                for y in stride(from: 0, to: 25, by: 5) { a[y + x] ^= d }
            }
            // ρ, π
            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotateLeft(a[x + 5 * y], rotationOffsets[x + 5 * y])
                }
            }
            // χ
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 {
                    a[y + x] = b[y + x] ^ (~b[y + (x + 1) % 5] & b[y + (x + 2) % 5])
                }
            }
            // ι
            a[0] ^= roundConstants[round]
        }
    }
}
