//
//  WalletDerivation.swift
//  polymarket-iosapp
//
//  署名者（秘密鍵のアドレス）から Polymarket の各種ウォレットアドレスを CREATE2 で導出し、
//  入力された資金保有アドレスがどの種類か判定する。
//  定数・手順は公式 SDK polymarket-client（polymarket/_internal/wallet.py, environments.py）と同じ。
//

import Foundation

nonisolated enum WalletDerivation {
    private static let proxyFactory = "0xaB45c5A4B0c941a2F231C04C3f49182e1A254052"
    private static let proxyImplementation = "0x44e999d5c2F66Ef0861317f9A4805AC2e90aEB4f"
    private static let safeFactory = "0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b"
    private static let safeInitCodeHash = "2bce2127ff07fb632d16c8347c4ebf501f4841168bed00d9e6ef715ddb6fcecf"
    private static let depositWalletFactory = "0x00000000000Fb5C9ADea0298D729A0CB3823Cc07"
    private static let depositWalletImplementation = "0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB"
    private static let depositWalletBeacon = "0x7A18EDfe055488A3128f01F563e5B479D92ffc3a"

    // ERC-1967 プロキシのバイトコード断片
    private static let erc1967Const1 = "cc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3"
    private static let erc1967Const2 = "5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076"
    private static let beaconConst1 = "b3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3"
    private static let beaconConst2 = "1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c"
    private static let beaconConst3 = "60195155f3363d3d373d3d363d602036600436635c60da"
    /// 0x61003D3D8160233D3973 + (64 << 56)（引数 64 バイト）
    private static let uupsPrefix = "61007d3d8160233d3973"
    /// 0x6100523D8160233D3973 + (64 << 56)
    private static let beaconPrefix = "6100923d8160233d3973"

    /// 資金保有アドレスの種類を判定する。どれにも当てはまらなければ nil
    static func detect(signer: String, wallet: String) throws -> WalletSignatureType? {
        let signer = try EthereumAddress.checksummed(signer)
        let wallet = try EthereumAddress.checksummed(wallet)
        if wallet == signer { return .eoa }
        if wallet == (try beaconDepositWallet(signer: signer)) { return .depositWallet }
        if wallet == (try uupsDepositWallet(signer: signer)) { return .depositWallet }
        if wallet == (try proxyWallet(signer: signer)) { return .polyProxy }
        if wallet == (try safeWallet(signer: signer)) { return .gnosisSafe }
        return nil
    }

    static func proxyWallet(signer: String) throws -> String {
        let parts: [String] = [
            "3d3d606380380380913d393d73", bare(proxyFactory),
            "5af4602a57600080fd5b602d8060366000396000f3363d3d373d3d3d363d73", bare(proxyImplementation),
            "5af43d82803e903d91602b57fd5bf352e831dd",
            "0000000000000000000000000000000000000000000000000000000000000020",
            "0000000000000000000000000000000000000000000000000000000000000000",
        ]
        let bytecode = try Data(hex: parts.joined())
        let salt = Keccak256.hash(try ABI.addressBytes(signer))
        return try create2(factory: proxyFactory, salt: salt, initCodeHash: Keccak256.hash(bytecode))
    }

    static func safeWallet(signer: String) throws -> String {
        let salt = Keccak256.hash(try ABI.address(signer))
        return try create2(factory: safeFactory, salt: salt, initCodeHash: try Data(hex: safeInitCodeHash))
    }

    static func uupsDepositWallet(signer: String) throws -> String {
        let args = try depositWalletArgs(signer: signer)
        let head: [String] = [uupsPrefix, bare(depositWalletImplementation), "6009", erc1967Const2, erc1967Const1]
        let bytecode = try Data(hex: head.joined()) + args
        return try create2(factory: depositWalletFactory, salt: Keccak256.hash(args), initCodeHash: Keccak256.hash(bytecode))
    }

    static func beaconDepositWallet(signer: String) throws -> String {
        let args = try depositWalletArgs(signer: signer)
        let head: [String] = [beaconPrefix, bare(depositWalletBeacon), beaconConst3, beaconConst2, beaconConst1]
        let bytecode = try Data(hex: head.joined()) + args
        return try create2(factory: depositWalletFactory, salt: Keccak256.hash(args), initCodeHash: Keccak256.hash(bytecode))
    }

    /// abi.encode(address factory, bytes32 walletId)。walletId は署名者アドレスを左ゼロ埋めしたもの
    private static func depositWalletArgs(signer: String) throws -> Data {
        try ABI.address(depositWalletFactory) + ABI.address(signer)
    }

    private static func create2(factory: String, salt: Data, initCodeHash: Data) throws -> String {
        let raw = Data([0xFF]) + (try ABI.addressBytes(factory)) + salt + initCodeHash
        return try EthereumAddress.checksummed(Keccak256.hash(raw).suffix(20).prefixedHex)
    }

    private static func bare(_ address: String) -> String {
        String(address.dropFirst(2)).lowercased()
    }
}
