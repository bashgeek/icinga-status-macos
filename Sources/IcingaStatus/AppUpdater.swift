import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var startupError: String?
    private let controller: SPUStandardUpdaterController?

    var isEnabled: Bool { controller != nil && startupError == nil }

    private init() {
        #if DEBUG
        // Development and sample-data builds must never replace themselves or change update preferences.
        controller = nil
        #else
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastUpdateCheckDate)
        do { try updater.start() }
        catch { startupError = error.localizedDescription }
        #endif
    }

    func checkForUpdates() {
        guard isEnabled, canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isEnabled else { return }
        // Sparkle owns persistence and scheduling for this preference.
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
            .accessibilityIdentifier("checkForUpdates")
    }
}

struct UpdateSettings: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates }, set: updater.setAutomaticChecks
            ))
            .disabled(!updater.isEnabled)
            .accessibilityIdentifier("automaticUpdateChecks")
            HStack {
                CheckForUpdatesButton()
                Spacer()
                if let date = updater.lastUpdateCheckDate {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = updater.startupError {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(updater.isEnabled
                     ? "Checks GitHub for new versions. You choose when to download and install an update."
                     : "Updates are disabled in development builds. Installed release versions can update themselves.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
