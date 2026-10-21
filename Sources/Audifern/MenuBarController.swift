import AppKit
import Combine
import QuickAccessUI
import SwiftUI

/// Keep the status button native. A resizable SwiftUI image in MenuBarExtra's
/// label can cause a runaway status-item Auto Layout update on macOS 27.
/// The popover content remains SwiftUI; only its small, fixed button is AppKit.
@MainActor final class MenuBarController: NSObject {
    private let store: BluetoothStore
    private let automation: ConnectionAutomation
    private let help: AppHelpController
    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var observations: [AnyCancellable] = []
    private var layoutSignature = ""
    init(store: BluetoothStore, automation: ConnectionAutomation, help: AppHelpController, preferences: AppPreferences, defaults: UserDefaults) {
        self.store = store; self.automation = automation; self.help = help; self.preferences = preferences; self.defaults = defaults
        item = NSStatusBar.system.statusItem(withLength: 25)
        super.init()
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        if let url = AppResources.bundle.url(forResource: "BrandMark", withExtension: "png"),
           let image = ArtworkRasterizer.image(url: url, size: .init(width: 18, height: 18), scale: 2, mirrored: false)?.copy() as? NSImage {
            image.isTemplate = true; item.button?.image = image
        } else { item.button?.image = NSImage(systemSymbolName: "ear", accessibilityDescription: Brand.name) }
        item.button?.imagePosition = .imageLeading
        popover.behavior = .transient
        observations.append(store.$connections.debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink { [weak self] _ in self?.update() })
        observations.append(preferences.objectWillChange.debounce(for: .milliseconds(30), scheduler: RunLoop.main).sink { [weak self] _ in self?.update() })
        update()
    }
    private func update() {
        item.isVisible = preferences.showMenuBar
        if !preferences.showMenuBar { popover.performClose(nil) }
        let text: String
        switch preferences.menuBarLabel {
        case "minimum":
            text = store.orderedConnections.filter(\.isConnected).compactMap(\.battery).min().map { " \($0)%" } ?? " —"
            item.length = 68
        case "both":
            text = " " + ["Left", "Right"].map { side in
                store.orderedConnections.first { $0.isConnected && $0.sideLabel == side }?.battery.map { "\($0)%" } ?? "—"
            }.joined(separator: " · ")
            item.length = 112
        default: text = ""; item.length = 25
        }
        if item.button?.title != text { item.button?.title = text }
        item.button?.setAccessibilityLabel(L("Audifern, %d hearing aids connected", store.connectedCount))
        item.button?.toolTip = Brand.name
        let layout = [preferences.menuBarExpanded, preferences.menuBarArtwork, preferences.menuBarTime,
                      preferences.menuBarSound, preferences.menuBarPrograms, preferences.menuBarAudio].map(String.init).joined()
        if layout != layoutSignature {
            layoutSignature = layout
            if popover.isShown { sizePanel() }
        }
    }
    private func panel() -> some View {
        MenuBarPanel(store: store, automation: automation, help: help, didChangeLayout: { [weak self] in
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.popover.isShown else { return }
                self.sizePanel()
            }
        })
            .environmentObject(preferences).defaultAppStorage(defaults)
    }
    private func sizePanel() {
        popover.appearance = preferences.appearance == .system ? nil : NSAppearance(named: preferences.appearance == .light ? .aqua : .darkAqua)
        let width: CGFloat = preferences.menuBarExpanded ? 422 : 382
        let measurement = NSHostingView(rootView: panel().fixedSize(horizontal: false, vertical: true))
        measurement.frame.size.width = width
        let natural = measurement.fittingSize.height
        let height = min(max(200, natural), (item.button?.window?.screen?.visibleFrame.height ?? 900) - 32)
        let root = ScrollView { panel() }.scrollBounceBehavior(.basedOnSize)
            .frame(width: width, height: height)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = .init(width: width, height: height)
    }
    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        sizePanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
