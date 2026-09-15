import SwiftUI

@main
struct IcingaStatusApp: App {
    @State private var store: AppStore

    init() {
        #if DEBUG
        _store = State(initialValue: DevelopmentPreview.makeStore())
        #else
        _store = State(initialValue: AppStore())
        #endif
        _ = AppUpdater.shared
    }

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
        .defaultSize(width: 760, height: 570)
        .commands {
            AboutCommands()
            CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
        }

        #if DEBUG
        Window("Icinga Status", id: "preview") {
            DevelopmentPreview(store: store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(ProcessInfo.processInfo.arguments.contains("--preview") ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        #endif

        Window("About Icinga Status", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
