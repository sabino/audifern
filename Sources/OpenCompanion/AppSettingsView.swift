import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var notifications: BatteryNotificationManager
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Settings").font(.system(size: 29, weight: .semibold, design: .rounded))
                Spacer()
                Text("Open Companion \(version)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.top, 24)
            Text("Closing this window keeps your connections and battery monitoring running in the menu bar.")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 28)
            BatteryNotificationSettingsView(manager: notifications)
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
