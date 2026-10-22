import AppKit
import SwiftUI

struct AboutView: View {
    enum ContributionMethod: String, CaseIterable, Identifiable {
        case mercadoPago, cryptocurrency
        var id: String { rawValue }
        var title: String { self == .mercadoPago ? "Mercado Pago" : L("Cryptocurrency") }
    }
    @EnvironmentObject private var preferences: AppPreferences
    @State private var method: ContributionMethod
    @State private var asset: DonationAsset
    @State private var copied: String?

    init(initialMethod: ContributionMethod = .mercadoPago, initialAsset: DonationAsset = .bitcoin) {
        _method = State(initialValue: initialMethod)
        _asset = State(initialValue: initialAsset)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("Development")
    }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                identity
                Surface(insets: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Support Audifern")).font(.system(size: 23, weight: .semibold))
                            Text(L("Voluntary contributions support development."))
                                .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Picker(L("Ways to support"), selection: $method) {
                            ForEach(ContributionMethod.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).tint(Brand.controlTint).labelsHidden().accessibilityIdentifier("support-method")
                        if method == .mercadoPago { mercadoPago }
                        else { cryptocurrency }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 22) {
                        Link(L("Source code"), destination: SupportInfo.sourceURL)
                        Link(L("License · GPL-3.0-only"), destination: SupportInfo.licenseURL)
                    }.font(AppType.callout)
                    Text(L("An independent project, licensed under GNU GPLv3. Not affiliated with or endorsed by the hearing-aid manufacturer."))
                        .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("about-footer")
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    Divider().opacity(0.45)
                    Text(L("Made with ❤️ and 🤖 in 🇧🇷"))
                        .font(AppType.caption).foregroundStyle(.secondary).opacity(0.7)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("about-made-with")
                }
            }.padding(22)
        .font(AppType.body).tint(Brand.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("about-audifern")
        .onChange(of: method) { _, _ in copied = nil }
        .onChange(of: asset) { _, _ in copied = nil }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(nsImage: AppResources.brandMark).resizable().scaledToFit()
                    .frame(width: 48, height: 60).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Brand.name).font(.system(size: 30, weight: .bold))
                        Spacer(minLength: 12)
                        Text(L("Version %@ · Build %@", version, build))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        Text(L("Developed by"))
                        Link(SupportInfo.author, destination: SupportInfo.authorURL).fontWeight(.semibold)
                    }.font(AppType.callout).accessibilityIdentifier("about-developer")
                }
            }
        }
    }

    private var mercadoPago: some View {
        HStack(alignment: .top, spacing: 18) {
            qr(SupportInfo.mercadoPagoURL.absoluteString, label: L("Mercado Pago donation link QR code"))
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Scan or open the donation page."))
                    .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Link(destination: SupportInfo.mercadoPagoURL) {
                        Label(L("Open donation page"), systemImage: "arrow.up.right")
                    }.buttonStyle(.borderedProminent).tint(Brand.controlTint).font(AppType.callout)
                        .accessibilityIdentifier("donate-mercado-pago")
                    copyButton(SupportInfo.mercadoPagoURL.absoluteString, title: L("Copy link"))
                }
                Text(L("Opens in your browser. No device ID is sent."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cryptocurrency: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(L("Cryptocurrency"), selection: $asset) {
                    ForEach(DonationAsset.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().accessibilityIdentifier("donation-asset")
                Spacer(minLength: 8)
                Label(asset == .usdc ? L("Ethereum mainnet · ERC-20") : asset.network, systemImage: "network")
                    .font(AppType.caption.weight(.medium)).foregroundStyle(Brand.accent)
            }
            HStack(alignment: .top, spacing: 18) {
                qr(asset.qrPayload, label: L("%@ receiving address QR code", asset.title))
                VStack(alignment: .leading, spacing: 8) {
                    Text(asset.address).font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("donation-address")
                    copyButton(asset.address, title: L("Copy address"))
                    Text(L("Choose this asset and network in your wallet."))
                        .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func qr(_ payload: String, label: String) -> some View {
        Group {
            if let image = DonationQRCode.image(for: payload) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
            } else { Text(L("QR code unavailable")).font(AppType.caption).foregroundStyle(.black) }
        }.frame(width: 128, height: 128).padding(8)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.gray.opacity(0.2)))
            .accessibilityLabel(label)
    }

    private func copyButton(_ value: String, title: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(value, forType: .string) { copied = value }
        } label: {
            Label(copied == value ? L("Copied") : title, systemImage: copied == value ? "checkmark" : "doc.on.doc")
                .labelStyle(AlignedLabelStyle(iconSize: 15, iconWidth: 18, spacing: 7))
                .frame(alignment: .leading)
        }.buttonStyle(.bordered).font(AppType.callout)
    }
}
