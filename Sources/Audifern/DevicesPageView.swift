import CompanionCore
import SwiftUI

struct DevicesPageView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showAll = false
    private var visible: [NearbyDevice] { store.devices.filter { showAll || $0.isCandidate } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Available devices")).font(.system(size: 28, weight: .bold))
                    Text(L("Keep your hearing aids nearby. Devices already paired with macOS can appear without advertising."))
                        .font(AppType.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isScanning { ProgressView().controlSize(.small) }
                Button(store.isScanning ? L("Stop scanning") : L("Scan nearby")) {
                    store.isScanning ? store.stopScan() : store.startScan()
                }.disabled(!store.isPoweredOn || store.isDemo)
            }
            if store.pairCandidateIDs.count == 2 {
                Button(L("Connect both hearing aids")) { store.connectPair() }
                    .buttonStyle(.borderedProminent).font(AppType.body)
                    .disabled(!store.isPoweredOn || store.connectedCount == 2 || store.isDemo)
                    .accessibilityIdentifier("connect-matched-pair")
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(visible) { device in deviceCard(device) }
                }.padding(2)
                if visible.isEmpty {
                    ContentUnavailableView(L("No hearing aids found"), systemImage: "ear.badge.waveform")
                }
            }
            HStack {
                Toggle(L("Show all nearby BLE devices"), isOn: $showAll).toggleStyle(.checkbox).font(AppType.caption)
                Spacer()
                Button(L("Advanced diagnostics…")) { navigation.present(.diagnostics) }.font(AppType.callout)
            }
        }.padding(24)
    }

    private func deviceCard(_ device: NearbyDevice) -> some View {
        let state = store.connections[device.id]
        let busy = state?.phase == .connecting || state?.phase == .disconnecting
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "ear").font(.title2).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state?.model ?? device.name).font(AppType.callout.weight(.semibold)).lineLimit(1)
                    Text(state.map { $0.isConnected ? L("%@ · Connected", L($0.sideLabel)) : L($0.phase.label) }
                         ?? (device.isSystemConnected ? L("Available on this Mac") : L("Nearby")))
                        .font(AppType.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if busy { ProgressView().controlSize(.mini) }
                Button(L("Details")) { navigation.present(.device(device.id)) }.buttonStyle(.borderless)
                Spacer()
                if state?.isConnected == true || state?.phase == .connecting {
                    Button(L("Disconnect")) { store.disconnect(device.id) }.buttonStyle(.borderless).disabled(store.isDemo)
                } else {
                    Button(L("Connect")) { store.connect(to: device.id) }.buttonStyle(.bordered).font(AppType.body)
                        .disabled(!store.isPoweredOn || busy || store.isDemo || (device.isConnectable == false && !device.isSystemConnected))
                }
            }.font(AppType.caption)
        }.padding(18).frame(maxWidth: .infinity)
            .background(Brand.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.accent.opacity(0.14)))
    }
}
