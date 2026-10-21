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
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                identity
                Surface {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Support Audifern")).font(.system(size: 25, weight: .semibold))
                            Text(L("If Audifern is useful to you, you can support its development with a voluntary contribution."))
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Picker(L("Ways to support"), selection: $method) {
                            ForEach(ContributionMethod.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("support-method")
                        if method == .mercadoPago { mercadoPago }
                        else { cryptocurrency }
                    }
                }
                HStack(spacing: 22) {
                    Link(L("Source code"), destination: SupportInfo.sourceURL)
                    Link(L("License · GPL-3.0-only"), destination: SupportInfo.licenseURL)
                }.font(AppType.callout)
                Text(L("An independent project, licensed under GNU GPLv3. Not affiliated with or endorsed by the hearing-aid manufacturer."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: 800, alignment: .leading).padding(28)
        }
        .font(AppType.body).tint(Brand.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("about-audifern")
        .onChange(of: method) { _, _ in copied = nil }
        .onChange(of: asset) { _, _ in copied = nil }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 22) {
                Image(nsImage: AppResources.brandMark).resizable().scaledToFit()
                    .frame(width: 68, height: 82).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Brand.name).font(.system(size: 36, weight: .bold))
                    Text(L("Version %@ · Build %@", version, build))
                        .font(AppType.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 5) {
                Text(L("Developed by"))
                Link(SupportInfo.author, destination: SupportInfo.authorURL).fontWeight(.semibold)
            }.accessibilityIdentifier("about-developer")
            Text(L("Made with ❤️ and 🤖 in 🇧🇷")).font(AppType.body)
                .accessibilityIdentifier("about-made-with")
            Label(L("Open source · GPL-3.0-only"), systemImage: "chevron.left.forwardslash.chevron.right")
                .labelStyle(AlignedLabelStyle(iconSize: 16)).font(AppType.callout).foregroundStyle(.secondary)
        }
    }

    private var mercadoPago: some View {
        HStack(alignment: .top, spacing: 24) {
            qr(SupportInfo.mercadoPagoURL.absoluteString, label: L("Mercado Pago donation link QR code"))
            VStack(alignment: .leading, spacing: 14) {
                Text(ContributionMethod.mercadoPago.title).font(AppType.headline)
                Text(L("Choose your contribution on the payment page, or scan this code with your phone."))
                    .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link(destination: SupportInfo.mercadoPagoURL) {
                    Label(L("Donate with Mercado Pago"), systemImage: "arrow.up.right")
                }.buttonStyle(.borderedProminent).font(AppType.body)
                    .accessibilityIdentifier("donate-mercado-pago")
                copyButton(SupportInfo.mercadoPagoURL.absoluteString, title: L("Copy link"))
                Text(L("Opens in your browser. Audifern does not receive payment details or send a device identifier."))
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cryptocurrency: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker(L("Cryptocurrency"), selection: $asset) {
                ForEach(DonationAsset.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("donation-asset")
            Label(asset.network, systemImage: "network").font(AppType.callout.weight(.medium)).foregroundStyle(Brand.accent)
            HStack(alignment: .top, spacing: 24) {
                qr(asset.qrPayload, label: L("%@ receiving address QR code", asset.title))
                VStack(alignment: .leading, spacing: 12) {
                    Text(asset.assetDescription).font(AppType.headline)
                    Text(L("Receiving address")).font(AppType.caption).foregroundStyle(.secondary)
                    Text(asset.address).font(.system(size: 14, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("donation-address")
                    copyButton(asset.address, title: L("Copy address"))
                    Text(L("This QR contains only the receiving address. Choose the asset and network shown in your wallet."))
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
        }.frame(width: 150, height: 150).padding(8)
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
                .frame(minWidth: 130, alignment: .leading)
        }.buttonStyle(.bordered).font(AppType.callout)
    }
}
