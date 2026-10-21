import QuickAccessKit
import SwiftUI

struct AidBatteryView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @ObservedObject var store: BluetoothStore
    let aid: AidConnection
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let reading = aid.batteryReading(at: context.date)
            let percentage = aid.battery ?? reading?.percentage
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 7) {
                    Label(percentage.map { "\($0)%" } ?? "—", systemImage: batterySymbol(percentage ?? 0))
                        .font(AppType.callout.monospacedDigit())
                        .foregroundStyle((percentage ?? 100) < 20 ? Color.orange : Color.primary)
                        .frame(width: 74, alignment: .trailing)
                        .accessibilityIdentifier("battery-\(aid.sideLabel.lowercased())-percentage")
                    Button { store.refreshBattery(aid.id) } label: {
                        ZStack {
                            Image(systemName: "arrow.clockwise").opacity(aid.advancedBusy ? 0 : 1)
                            if aid.advancedBusy { ProgressView().controlSize(.mini) }
                        }.frame(width: 16, height: 16)
                    }.buttonStyle(.borderless)
                        .disabled(!aid.isConnected || aid.actionPending || aid.advancedBusy || aid.groupActionPending)
                        .accessibilityLabel(L("Read %@ battery time", L(aid.sideLabel)))
                }
                Text(runtimeLabel(reading, at: context.date))
                    .font(AppType.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .lineLimit(1).frame(width: compact ? 142 : 185, height: 18, alignment: .trailing)
                    .accessibilityIdentifier("battery-\(aid.sideLabel.lowercased())-time")
                    .help(runtimeHelp(reading))
            }.frame(minHeight: 49).transaction { $0.animation = nil }
        }
    }

    private func runtimeLabel(_ reading: BatteryRuntimeReading?, at now: Date) -> String {
        guard let reading else { return compact ? "—" : aid.isConnected ? L("Reading time left…") : L("Time estimate unavailable") }
        let cached = !aid.isConnected || aid.batteryTelemetryUpdatedAt != reading.measuredAt
        if reading.isCharged { return cached ? L("Last known: charged") : L("Charged") }
        if reading.isCharging { return cached ? L("Last known: charging") : L("Charging") }
        guard let seconds = reading.remainingSeconds(at: now), let duration = Self.duration(seconds) else { return L("Time estimate unavailable") }
        if compact { return cached ? L("Cached: %@", duration) : "~" + duration }
        return cached ? L("Cached estimate: %@", duration) : L("About %@ left", duration)
    }
    private func runtimeHelp(_ reading: BatteryRuntimeReading?) -> String {
        guard let reading else { return L("Remaining time needs a device reading; it is not calculated from the battery percentage.") }
        let stamp = reading.measuredAt.formatted(.dateTime.day().month().hour().minute().locale(Localization.shared.formattingLocale))
        return L("Device reading: %@. Counts down locally; refreshes about hourly while connected.", stamp)
    }
    private func batterySymbol(_ percentage: Int) -> String {
        if percentage < 10 { return "battery.0percent" }
        if percentage <= 30 { return "battery.25percent" }
        if percentage <= 60 { return "battery.50percent" }
        if percentage <= 85 { return "battery.75percent" }
        return "battery.100percent"
    }
    static func duration(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 60) else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1 min" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours) h \(minutes % 60) min" : "\(minutes) min"
    }
}
