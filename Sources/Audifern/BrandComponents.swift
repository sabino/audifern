import AppKit
import SwiftUI

enum Brand {
    static let name = "Audifern"
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.35, green: 0.81, blue: 0.65, alpha: 1)
            : NSColor(srgbRed: 0.06, green: 0.44, blue: 0.34, alpha: 1)
    })
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
}

struct PageHeading<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 30, weight: .bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.065)))
    }
}

struct ConnectionBadge: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(store.connectedCount > 0 ? Brand.accent : .secondary).frame(width: 7, height: 7)
            Text(store.isDemo ? L("Preview mode") : store.connectedCount > 0 ? L("%d connected", store.connectedCount) : L("Disconnected"))
                .font(.callout.weight(.medium))
        }.padding(.horizontal, 13).padding(.vertical, 9)
            .background(Brand.surface, in: Capsule()).overlay(Capsule().strokeBorder(.quaternary))
            .accessibilityIdentifier("connection-status")
    }
}

struct HearingAidArtwork: View {
    var right = false
    var body: some View {
        Image(nsImage: AppResources.hearingAid).resizable().scaledToFit()
            .scaleEffect(x: right ? -1.4 : 1.4, y: 1.4)
            .frame(width: 120, height: 175).accessibilityHidden(true)
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
