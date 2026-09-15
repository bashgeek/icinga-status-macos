import AppKit
import SwiftUI
import ServiceManagement
import IcingaCore

enum SettingsTab: Hashable { case instances, monitoring, notifications, general }

struct SettingsView: View {
    let store: AppStore
    @State var tab: SettingsTab = .instances
    @State private var visitedTabs: Set<SettingsTab> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                AppLogo(size: 24)
                Text("Settings").font(.headline)
                Spacer()
                Picker("Settings section", selection: $tab) {
                    Text("Instances").tag(SettingsTab.instances)
                    Text("Monitoring").tag(SettingsTab.monitoring)
                    Text("Notifications").tag(SettingsTab.notifications)
                    Text("General").tag(SettingsTab.general)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            .padding(20)
            Divider()
            ZStack {
                page(.instances) { InstancesSettings(store: store) }
                page(.monitoring) {
                    SettingsPage(title: "Monitoring", subtitle: "Choose which checks need your attention.") {
                        MonitoringSettings(store: store)
                    }
                }
                page(.notifications) {
                    SettingsPage(title: "Notifications", subtitle: "Stay informed without the noise.") {
                        NotificationSettings(store: store)
                    }
                }
                page(.general) {
                    SettingsPage(title: "General", subtitle: "Make Icinga Status feel at home on your Mac.") {
                        GeneralSettings(store: store)
                    }
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 800, minHeight: 600, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: tab, initial: true) { _, value in visitedTabs.insert(value) }
        .overlay(alignment: .bottom) {
            if let error = store.storageError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                    .padding(16).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private func page<Content: View>(_ section: SettingsTab, @ViewBuilder content: () -> Content) -> some View {
        // Keep visited forms alive so changing sections does not discard an unsaved instance.
        if tab == section || visitedTabs.contains(section) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(tab == section ? 1 : 0)
                .allowsHitTesting(tab == section)
                .disabled(tab != section)
                .accessibilityHidden(tab != section)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
            content
        }
    }
}

private struct MonitoringSettings: View {
    let store: AppStore
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Toggle("Include acknowledged problems", isOn: filterBinding(\.includeAcknowledged))
                Toggle("Include problems in scheduled downtime", isOn: filterBinding(\.includeDowntime))
                Toggle("Include soft states", isOn: filterBinding(\.includeSoftStates))
            } header: { Text("Actionable problems") } footer: {
                Text("These filters apply to the problem count, problem list, and notifications. Full-status totals show all checks. Soft states are checks that Icinga is still retrying.")
            }
            Section {
                LabeledContent("Ignore hosts") {
                    TextField("backup-*\ntest-?", text: filterBinding(\.ignoredHosts), axis: .vertical)
                        .lineLimit(3...6).frame(minWidth: 260)
                }
                LabeledContent("Ignore services") {
                    TextField("Disk space*", text: filterBinding(\.ignoredServices), axis: .vertical)
                        .lineLimit(3...6).frame(minWidth: 260)
                }
            } header: { Text("Ignore patterns") } footer: {
                Text("One pattern per line, matched without case sensitivity. Use * for any text and ? for a single character. Patterns match the full host or service name.")
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.formStyle(.grouped)
    }

    private func filterBinding<Value>(_ keyPath: WritableKeyPath<FilterSettings, Value>) -> Binding<Value> {
        Binding(get: { store.preferences.filters[keyPath: keyPath] }, set: { value in
            var updated = store.preferences
            updated.filters[keyPath: keyPath] = value
            do { try store.updatePreferences(updated); error = nil }
            catch { self.error = error.localizedDescription }
        })
    }
}

private struct NotificationSettings: View {
    let store: AppStore
    @State private var error: String?
    @State private var requesting = false
    var body: some View {
        Form {
            Section {
                Toggle("Notify about new problems and escalations", isOn: Binding(
                    get: { store.preferences.notificationsEnabled },
                    set: { enabled in
                        if enabled {
                            requesting = true
                            Task {
                                do {
                                    if try await !store.enableNotifications() { error = "Notifications are disabled in macOS. Allow Icinga Status in System Settings → Notifications." }
                                    else { error = nil }
                                } catch { self.error = error.localizedDescription }
                                requesting = false
                            }
                        } else { update { $0.notificationsEnabled = false } }
                    }
                )).disabled(requesting || store.isDemo)
                Toggle("Notify when problems recover", isOn: Binding(
                    get: { store.preferences.recoveryNotifications }, set: { value in update { $0.recoveryNotifications = value } }
                )).disabled(!store.preferences.notificationsEnabled)
                Toggle("Play a notification sound", isOn: Binding(
                    get: { store.preferences.notificationSound }, set: { value in update { $0.notificationSound = value } }
                )).disabled(!store.preferences.notificationsEnabled)
            } header: { Text("Incident notifications") } footer: {
                Text("Existing problems are quiet on startup and reconnect. New changes are grouped to reduce bursts, and repeated polls do not repeat alerts. Notifications follow your monitoring filters and macOS Focus settings.")
            }
            Section {
                Button(store.isMuted ? "Unmute notifications" : "Mute for one hour") {
                    if store.isMuted { store.unmute() } else { store.muteForOneHour() }
                }
                if let date = store.mutedUntil, store.isMuted {
                    Text("Muted until \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.formStyle(.grouped)
    }

    private func update(_ edit: (inout AppPreferences) -> Void) {
        var updated = store.preferences
        edit(&updated)
        do { try store.updatePreferences(updated); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct GeneralSettings: View {
    let store: AppStore
    @State private var loginStatus = SMAppService.Status.notRegistered
    @State private var error: String?
    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Display", selection: Binding(
                    get: { store.preferences.effectiveMenuBarDisplay },
                    set: { value in
                        var updated = store.preferences
                        updated.menuBarDisplay = value
                        updated.iconOnly = value == .icon
                        do { try store.updatePreferences(updated) }
                        catch { self.error = error.localizedDescription }
                    }
                )) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(store.preferences.effectiveMenuBarDisplay.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                MenuBarDisplayExamples(mode: store.preferences.effectiveMenuBarDisplay)
                if store.preferences.effectiveMenuBarDisplay == .browserBadge {
                    Toggle("Pulse on refresh when there are issues", isOn: Binding(
                        get: { store.preferences.effectivePulseOnRefresh },
                        set: { value in
                            var updated = store.preferences
                            updated.pulseOnRefresh = value
                            do { try store.updatePreferences(updated) }
                            catch { self.error = error.localizedDescription }
                        }
                    ))
                    Text("Highlights problems and connection failures after a refresh. Healthy updates stay quiet, and Reduce Motion is respected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            error = nil
                        } catch { self.error = error.localizedDescription }
                        loginStatus = SMAppService.mainApp.status
                    }
                )).disabled(store.isDemo)
                if loginStatus == .requiresApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section("Icinga Status") {
                HStack(spacing: 12) {
                    AppLogo(size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppInformation.name).font(.headline)
                        Text("Version \(AppInformation.version) (\(AppInformation.build))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(AppInformation.copyright).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Link("Icinga 2 API documentation ↗", destination: URL(string: "https://icinga.com/docs/icinga-2/latest/doc/12-icinga2-api/")!)
                if store.isDemo { Text("Demo mode uses sample data and does not save configuration or send API actions.").foregroundStyle(.secondary) }
                Text(AppInformation.communityNotice)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("generalCommunityNotice")
                Link("View on GitHub ↗", destination: AppInformation.repositoryURL)
                    .help("github.com/bashgeek/icinga-status-macos")
                    .accessibilityIdentifier("generalGitHubLink")
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

}

private struct MenuBarDisplayExamples: View {
    let mode: MenuBarDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu bar examples").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            example("Healthy", state: "healthy")
            example("Problems", state: "problems")
            example("API unavailable", state: "unavailable")
        }
        .padding(.vertical, 6)
        .help("Examples use sample data. Your menu bar shows your own monitoring results.")
        .accessibilityIdentifier("menuBarDisplayExamples")
    }

    private func example(_ title: String, state: String) -> some View {
        HStack(spacing: 16) {
            Text(title).font(.caption).foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Image("MenuBarExample-\(mode.rawValue)-\(state)")
                .resizable().interpolation(.high)
                .frame(width: 360, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
                .accessibilityLabel("\(title) example of the selected menu bar style")
            Spacer(minLength: 0)
        }
    }
}

// Presentation names are independent of the persisted display-mode identifiers.
extension MenuBarDisplay {
    var title: String {
        switch self {
        case .browserBadge: "Status summary"
        case .fullStatus: "Detailed counts"
        case .problemCount: "Problem count"
        case .icon: "Icon only"
        }
    }

    var explanation: String {
        switch self {
        case .browserBadge: "A colored badge showing affected hosts and services in red, monitored totals in green, and connection failures in amber."
        case .fullStatus: "Two rows of host and service totals, split into OK, warning, down or critical, and unknown states. Pending checks appear when present."
        case .problemCount: "Counts host and service problems included by your monitoring filters. Shows just a status icon when the count is zero."
        case .icon: "Status symbols without numbers, showing problems, incomplete results, or paused monitoring."
        }
    }
}
