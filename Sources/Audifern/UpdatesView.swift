import AppKit
import SwiftUI

struct UpdatesView: View {
    @ObservedObject var controller: AppUpdateController
    @State private var selectedRelease = "current"
    @State private var copied = false
    private var selected: AppRelease? { controller.releases.first { $0.id == selectedRelease } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Surface(insets: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(nsImage: AppResources.brandMark).resizable().scaledToFit().frame(width: 34, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Version %@ · Build %@", controller.installedVersion, controller.installedBuild)).font(AppType.headline)
                            Text(controller.detecting ? L("Identifying installation…") : controller.installation.title)
                                .font(AppType.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button(L("Check for Updates…")) { Task { await controller.checkForUpdates(presentingInstaller: true) } }
                            .disabled(controller.checking || controller.detecting)
                            .accessibilityIdentifier("check-for-updates")
                    }
                    HStack(spacing: 8) {
                        if controller.checking { ProgressView().controlSize(.small) }
                        Text(status).font(AppType.callout).foregroundStyle(controller.failed ? Color.orange : .secondary)
                            .lineLimit(2).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    }
                    if let command = controller.installation.upgradeCommand {
                        Divider()
                        Text(L("This installation is managed by %@. Update it with the same package manager.", controller.installation.title))
                            .font(AppType.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(command).font(.system(size: 14, design: .monospaced)).textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string); copied = true
                            } label: { Label(copied ? L("Copied") : L("Copy command"), systemImage: copied ? "checkmark" : "doc.on.doc").frame(width: 126) }
                            .accessibilityIdentifier("copy-upgrade-command")
                        }
                    } else if controller.installation == .direct, controller.updaterReady {
                        Divider()
                        HStack {
                            Toggle(L("Automatically check for updates"), isOn: $controller.automaticallyChecks).toggleStyle(.switch).font(AppType.callout)
                            Spacer(minLength: 6)
                            if controller.updateAvailable {
                                Button(L("Install update…")) { Task { await controller.installUpdate() } }
                                    .buttonStyle(.borderedProminent).tint(Brand.controlTint).disabled(!controller.canInstall)
                                    .accessibilityIdentifier("install-update")
                            }
                        }
                        Text(L("Updates are signed and verified before installation. You can choose when to install and reopen Audifern."))
                            .font(AppType.caption).foregroundStyle(.secondary)
                    } else {
                        Text(controller.installation == .development
                             ? L("Development builds do not replace your installed app. Use a published release for in-app updates.")
                             : controller.installation == .uncertain
                             ? L("Audifern could not identify who manages this installation. In-app installation is disabled; try identifying it again.")
                             : L("In-app updates will be available after the signed update feed is configured."))
                            .font(AppType.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Text(L("Changelog")).font(AppType.headline)
                Spacer()
                Picker(L("Release"), selection: $selectedRelease) {
                    Text(L("%@ · Installed", controller.installedVersion)).tag("current")
                    ForEach(controller.releases.filter { $0.version != controller.installedVersion }) { release in
                        Text(release.version).tag(release.id)
                    }
                }.labelsHidden().frame(width: 180).accessibilityIdentifier("changelog-release")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selected { ReleaseNotesBody(text: selected.body ?? L("No release notes are available.")) }
                    else if let installed = controller.releases.first(where: { $0.version == controller.installedVersion }) {
                        ReleaseNotesBody(text: installed.body ?? L("No release notes are available."))
                    } else { currentNotes }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }.background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            HStack {
                Text(L("Release history is fetched from GitHub when you open this page or check for updates."))
                    .font(AppType.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Link(L("All releases"), destination: URL(string: "https://github.com/sabino/audifern/releases")!).font(AppType.caption)
            }
        }.task { if controller.checkedAt == nil { await controller.checkForUpdates() } }
            .accessibilityIdentifier("updates-and-changelog")
    }
    private var status: String {
        if controller.checking { return L("Checking for updates…") }
        if controller.failed { return L("Could not load releases. Check your connection and try again.") }
        if controller.updateAvailable, let latest = controller.latest { return L("Version %@ is available.", latest.version) }
        if controller.checkedAt != nil { return L("You’re up to date.") }
        return L("Check for a newer version and read what changed.")
    }
    private var currentNotes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("What’s new")).font(AppType.headline)
            Label(L("Prominent connection controls and reconnect status in the menu bar."), systemImage: "menubar.rectangle")
            Label(L("Automatic reconnection recovers after missed lock or wake notifications."), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            Label(L("Grouping controls stay disabled until both hearing aids are connected."), systemImage: "link")
            Label(L("Changelog and updates that respect how you installed Audifern."), systemImage: "arrow.down.circle")
        }.font(AppType.callout)
    }
}

private struct ReleaseNotesBody: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let lines = Array(text.prefix(30_000).components(separatedBy: .newlines).enumerated())
            ForEach(lines, id: \.offset) { _, line in
                if line.hasPrefix("#") {
                    Text(String(line.drop(while: { $0 == "#" || $0 == " " }))).font(AppType.headline)
                } else if !line.isEmpty {
                    Text((try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line))
                        .font(AppType.callout).textSelection(.enabled)
                }
            }
        }
    }
}
