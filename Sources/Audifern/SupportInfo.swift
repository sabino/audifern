import Foundation

/// Public contribution destinations supplied by the project maintainer.
/// These are receiving addresses, never credentials or private keys.
enum SupportInfo {
    static let author = "sabino"
    static let authorURL = URL(string: "https://github.com/sabino")!
    static let sourceURL = URL(string: "https://github.com/sabino/audifern")!
    static let licenseURL = sourceURL.appendingPathComponent("blob/main/LICENSE")
    static let mercadoPagoURL = URL(string: "https://link.mercadopago.com.br/sabinosoftware")!
}

enum DonationAsset: String, CaseIterable, Identifiable {
    case bitcoin, ethereum, usdc, solana
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bitcoin: "Bitcoin (BTC)"
        case .ethereum: "Ethereum (ETH)"
        case .usdc: "USDC"
        case .solana: "Solana (SOL)"
        }
    }
    var network: String {
        switch self {
        case .bitcoin: L("Bitcoin network")
        case .ethereum, .usdc: L("Ethereum mainnet")
        case .solana: L("Solana mainnet")
        }
    }
    var assetDescription: String {
        self == .usdc ? L("USDC on Ethereum · ERC-20") : title
    }
    var address: String {
        switch self {
        case .bitcoin: "bc1qjntn2qxppkajtf042520vt6zqjfzl2zetq0chl"
        case .ethereum, .usdc: "0xA0cc1D5A0cc21073367830894CDA3b133cAF7EcF"
        case .solana: "Bzq3EtpuogiX43EAcYCcNMDRRVtPoyRenBRLE1Cd8M9r"
        }
    }
    // Address-only QR is compatible with ordinary wallet address scanners. The
    // UI names the asset and network explicitly; it never invents a token URI,
    // payment amount or a smart-contract transaction.
    var qrPayload: String { address }
}
