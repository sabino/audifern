import CompanionCore
import SwiftUI

struct DevicesPageView: View {
    @ObservedObject var store: BluetoothStore
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var navigation: AppNavigation
    @State private var showNearby = true
    @State private var showAll = false
    private var visible: [NearbyDevice] { store.devices.filter { showAll || $0.isCandidate } }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            PageHeading(title: L("Devices"), subtitle: L("Connect your pair and view each aid’s information.")) { ConnectionBadge(store: store) }
                .padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 20)
            if !store.orderedConnections.isEmpty {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(store.orderedConnections.sorted { $0.sideLabel == "Left" && $1.sideLabel != "Left" }) { aid in
                        let right = aid.sideLabel == "Right"
                        Surface {
                            VStack(spacing: 20) {
                                Text(L(aid.sideLabel)).font(.system(size: 25, weight: .semibold))
                                Label(L(aid.phase.label), systemImage: aid.isConnected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(aid.isConnected ? Brand.accent : Color.secondary)
                                HearingAidArtwork(right: right).padding(.vertical, 16)
                                Text(aid.model ?? L("Hearing aid")).font(AppType.headline)
                                AidBatteryView(store: store, aid: aid)
                                Button(L("Device details…")) { navigation.present(.device(aid.id)) }
                                    .buttonStyle(.bordered).font(AppType.body).controlSize(.large)
                                if aid.isConnected {
                                    Button(L("Disconnect")) { store.disconnect(aid.id) }.disabled(store.isDemo)
                                }
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }.padding(.horizontal, 30)
            }
            VStack(alignment: .leading, spacing: 12) {
                ExpandableSection(L("Available devices"), isExpanded: $showNearby) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(store.isScanning ? L("Stop scanning") : L("Scan nearby")) { store.isScanning ? store.stopScan() : store.startScan() }
                                .disabled(!store.isPoweredOn || store.isDemo)
                            if store.isScanning { ProgressView().controlSize(.small) }
                            Spacer()
                            if store.pairCandidateIDs.count == 2 {
                                Button(L("Connect both hearing aids")) { store.connectPair() }
                                    .buttonStyle(.borderedProminent).font(AppType.body).disabled(!store.isPoweredOn || store.connectedCount == 2 || store.isDemo)
                                    .accessibilityIdentifier("connect-matched-pair")
                            }
                        }
                        if visible.isEmpty {
                            Text(L("Keep your hearing aids nearby. Devices already paired with macOS can appear without advertising."))
                                .font(AppType.callout).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) { ForEach(visible) { device in deviceCard(device) } }.padding(.vertical, 4)
                        }
                        Toggle(L("Show all nearby BLE devices"), isOn: $showAll).toggleStyle(.checkbox).font(AppType.caption)
                    }.padding(.top, 12)
                }
            }.padding(18).background(Brand.surface, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 30)
            Button(L("Advanced diagnostics…")) { navigation.present(.diagnostics) }.padding(.horizontal, 30)
        }.padding(.bottom, 30).frame(maxWidth: 1120) }
        .onChange(of: store.connectedCount) { _, count in if count > 0 { showNearby = false } }
        .onAppear { if store.connectedCount > 0 { showNearby = false } }
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
                Button(L("Details")) { store.select(device.id) }.buttonStyle(.borderless)
                Spacer()
                if state?.isConnected == true || state?.phase == .connecting {
                    Button(L("Disconnect")) { store.disconnect(device.id) }.buttonStyle(.borderless)
                } else {
                    Button(L("Connect")) { store.connect(to: device.id) }.buttonStyle(.bordered).font(AppType.body)
                        .disabled(!store.isPoweredOn || busy || store.isDemo || (device.isConnectable == false && !device.isSystemConnected))
                }
            }.font(AppType.caption)
        }.padding(14).frame(width: 240)
            .background(Brand.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.accent.opacity(0.14)))
    }
}
