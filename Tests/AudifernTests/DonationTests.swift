import AppKit
import CoreImage
import Foundation
import Testing
@testable import Audifern

@Test func contributionDestinationsMatchTheMaintainersSuppliedReceivingAddresses() {
    #expect(DonationAsset.bitcoin.address == "bc1qjntn2qxppkajtf042520vt6zqjfzl2zetq0chl")
    #expect(DonationAsset.ethereum.address == "0xA0cc1D5A0cc21073367830894CDA3b133cAF7EcF")
    #expect(DonationAsset.usdc.address == DonationAsset.ethereum.address)
    #expect(DonationAsset.solana.address == "Bzq3EtpuogiX43EAcYCcNMDRRVtPoyRenBRLE1Cd8M9r")
    #expect(SupportInfo.mercadoPagoURL.absoluteString == "https://link.mercadopago.com.br/sabinosoftware")
    #expect(SupportInfo.mercadoPagoURL.query == nil && SupportInfo.mercadoPagoURL.fragment == nil)
    #expect(SupportInfo.authorURL.absoluteString == "https://github.com/sabino")
}

@MainActor @Test func everyContributionQRCodeDecodesToItsExactOfflinePayload() throws {
    let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    let payloads = DonationAsset.allCases.map(\.qrPayload) + [SupportInfo.mercadoPagoURL.absoluteString]
    for payload in payloads {
        let image = try #require(DonationQRCode.image(for: payload))
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let features = detector.features(in: CIImage(cgImage: cg)).compactMap { $0 as? CIQRCodeFeature }
        #expect(features.count == 1)
        #expect(features.first?.messageString == payload)
        // Also decode the QR at its smallest on-screen 1x size, rather than
        // trusting only the generator's full-resolution image.
        let scaled = try #require(CGContext(data: nil, width: 150, height: 150, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        scaled.interpolationQuality = .none
        scaled.draw(cg, in: CGRect(x: 0, y: 0, width: 150, height: 150))
        let small = try #require(scaled.makeImage())
        let smallFeatures = detector.features(in: CIImage(cgImage: small)).compactMap { $0 as? CIQRCodeFeature }
        #expect(smallFeatures.first?.messageString == payload)
    }
}

@Test func madeWithCreditKeepsTheMaintainersRequestedEmojiInEveryLanguage() {
    for (language, expected) in [(AppLanguage.english, "Made with ❤️ and 🤖 in 🇧🇷"),
        (.portugueseBrazil, "Feito com ❤️ e 🤖 no 🇧🇷"), (.spanish, "Hecho con ❤️ y 🤖 en 🇧🇷")] {
        let text = Localization(language: language)
        #expect(text.string("Made with ❤️ and 🤖 in 🇧🇷") == expected)
    }
}
