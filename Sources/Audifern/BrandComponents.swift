import AppKit
import SwiftUI

enum Brand {
    static let name = "Audifern"
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.35, green: 0.81, blue: 0.65, alpha: 1)
            : NSColor(srgbRed: 0.06, green: 0.44, blue: 0.34, alpha: 1)
    })
    static let background = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.105, green: 0.115, blue: 0.12, alpha: 1)
            : NSColor(srgbRed: 0.97, green: 0.975, blue: 0.98, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.16, green: 0.17, blue: 0.18, alpha: 1)
            : .white
    })
}

struct PageHeading<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 34, weight: .bold))
                Text(subtitle).font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

struct Surface<Content: View>: View {
    var insets: CGFloat = 24
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(insets).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.065)))
            .shadow(color: .black.opacity(0.025), radius: 12, x: 0, y: 4)
    }
}

struct ConnectionBadge: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(store.connectedCount > 0 ? Brand.accent : .secondary).frame(width: 7, height: 7)
            Text(store.isDemo ? L("Preview mode") : store.connectedCount > 0 ? L("%d connected", store.connectedCount) : L("Disconnected"))
                .font(AppType.callout.weight(.medium))
        }.padding(.horizontal, 13).padding(.vertical, 9)
            .background(Brand.surface, in: Capsule()).overlay(Capsule().strokeBorder(.quaternary))
            .accessibilityIdentifier("connection-status")
    }
}

struct HearingAidArtwork: View {
    var right = false
    var size: CGFloat = 1
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        Image(nsImage: HearingAidImage.image(size: CGSize(width: 168 * size, height: 245 * size), scale: displayScale, mirrored: right))
            .resizable().interpolation(.high).frame(width: 168 * size, height: 245 * size)
            .frame(width: 120 * size, height: 175 * size).accessibilityHidden(true)
    }
}

struct BrandMark: View {
    var body: some View {
        Image(nsImage: AppResources.brandMark).resizable().scaledToFit()
            .frame(width: 30, height: 30).scaleEffect(1.25).accessibilityHidden(true)
    }
}


struct RoundControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 64, height: 64)
            .background(Brand.background.opacity(configuration.isPressed ? 0.85 : 0.5), in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.12)))
            .contentShape(Circle())
            .opacity(enabled ? 1 : 0.35)
    }
}
