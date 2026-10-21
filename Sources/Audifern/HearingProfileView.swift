import SwiftUI

struct HearingProfileView: View {
    @ObservedObject var store: BluetoothStore
    @ObservedObject var workspace: FittingWorkspaceStore
    @ObservedObject var backups: DeviceBackupStore
    @ObservedObject var audiograms: AudiogramEditorStore
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeading(title: L("Hearing profile"), subtitle: L("Your records and plans, together in one place.")) { EmptyView() }
                Text(L("Review your saved settings, keep your hearing tests and prepare for your next fitting."))
                    .font(AppType.body).foregroundStyle(.secondary)
                task(title: L("Saved fitting"), detail: L("Explore the settings already captured from your hearing aids."),
                     symbol: "ear.badge.waveform", action: L("View saved settings…"), destination: .savedFitting)
                task(title: L("Audiograms"), detail: L("Keep a copy of your hearing test and enter its results."),
                     symbol: "chart.xyaxis.line", action: L("Manage audiograms…"), destination: .audiograms)
                task(title: L("Fitting plan"), detail: L("Prepare one step at a time. Your plan stays on this Mac."),
                     symbol: "list.bullet.clipboard", action: L("Continue plan…"), destination: .fittingPlan)
                Surface {
                    HStack(alignment: .center, spacing: 20) {
                        Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 28)).foregroundStyle(Brand.accent)
                            .frame(width: 66, height: 66)
                            .background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Backups")).font(AppType.headline)
                            Text(L("%d saved on this Mac", backups.entries.count)).font(AppType.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { navigation.present(.backups) } label: {
                            Text(L("Manage backups…")).frame(maxWidth: .infinity, minHeight: 26)
                        }.buttonStyle(.bordered).font(AppType.body).frame(width: 208)
                    }
                }
                Label(L("Clinical programming and full fitting restore are still in development."), systemImage: "info.circle")
                    .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(32).frame(maxWidth: 1100)
        }
    }
    private func task(title: String, detail: String, symbol: String, action: String, destination: AppSheet) -> some View {
        Surface {
            HStack(alignment: .center, spacing: 22) {
                Image(systemName: symbol).font(.system(size: 28, weight: .regular)).foregroundStyle(Brand.accent)
                    .frame(width: 66, height: 66).background(Brand.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 23, weight: .semibold))
                    Text(detail).font(AppType.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                Button { navigation.present(destination) } label: {
                    Text(action).frame(maxWidth: .infinity, minHeight: 26)
                }.buttonStyle(.bordered).font(AppType.body).frame(width: 208)
            }
        }
    }
}
