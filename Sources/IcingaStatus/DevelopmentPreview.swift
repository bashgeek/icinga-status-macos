#if DEBUG
import AppKit
import SwiftUI
import IcingaCore

struct DevelopmentPreview: View {
    let store: AppStore
    private let args = ProcessInfo.processInfo.arguments
    private var dark: Bool { args.contains("--preview-dark") }
    private var scope: CheckListScope {
        args.contains("--preview-hosts") ? .hosts : args.contains("--preview-services") ? .services : .problems
    }
    private var settingsTab: SettingsTab {
        if args.contains("--preview-general") { return .general }
        if args.contains("--preview-notifications") { return .notifications }
        if args.contains("--preview-monitoring") { return .monitoring }
        return .instances
    }

    var body: some View {
        content.environment(\.colorScheme, dark ? .dark : .light)
    }

    @ViewBuilder private var content: some View {
        if args.contains("--preview-menubar") {
            MenuBarExampleCapture(store: store, dark: dark)
        } else if args.contains("--preview-integration") {
            VStack(alignment: .trailing, spacing: 12) {
                MenuBarExampleCapture(store: store, dark: dark, width: 640)
                StatusPanel(store: store, scope: scope)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .padding(.trailing, 24).padding(.bottom, 24)
            }
            .frame(width: 640)
            .background(Color(white: dark ? 0.10 : 0.88))
        } else if args.contains("--preview-about") {
            AboutView()
        } else if args.contains("--preview-settings") {
            SettingsView(store: store, tab: settingsTab).frame(width: 800, height: 680)
        } else {
            StatusPanel(store: store, scope: scope, showFilters: args.contains("--preview-filters"))
        }
    }

    static func makeStore() -> AppStore {
        let args = ProcessInfo.processInfo.arguments
        let store = AppStore(demo: args.contains("--demo"), isolated: args.contains("--ui-testing"))
        if let index = args.firstIndex(of: "--scenario"), args.indices.contains(index + 1),
           let scenario = DemoScenario(rawValue: args[index + 1]) {
            store.setDemoScenario(scenario)
        }
        if args.contains("--demo") {
            if args.contains("--capture-preview-stdout") {
                Task { await PreviewCapture.renderDemo(store: store) }
            } else if args.contains("--capture-menubar-examples-stdout") {
                Task { await PreviewCapture.captureMenuBarExamples(store: store) }
            }
        }
        return store
    }
}

@MainActor
private enum PreviewCapture {
    static func captureMenuBarExamples(store: AppStore) async {
        guard store.isDemo else { return }
        for mode in MenuBarDisplay.allCases {
            var preferences = store.preferences
            preferences.menuBarDisplay = mode
            preferences.iconOnly = mode == .icon
            preferences.pulseOnRefresh = false
            try? store.updatePreferences(preferences)
            for (name, scenario) in [("healthy", DemoScenario.healthy), ("problems", .critical), ("unavailable", .connectionFailure)] {
                store.setDemoScenario(scenario)
                for (appearance, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
                    let renderer = ImageRenderer(content: MenuBarExampleCapture(store: store, dark: scheme == .dark)
                        .environment(\.colorScheme, scheme).environment(\.displayScale, 2))
                    renderer.scale = 2
                    guard let bitmap = renderer.cgImage,
                          let png = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]),
                          let json = try? JSONSerialization.data(withJSONObject: [
                            "name": "MenuBarExample-\(mode.rawValue)-\(name)", "appearance": appearance,
                            "png": png.base64EncodedString()
                          ]), let line = String(data: json, encoding: .utf8) else { continue }
                    print("Menu bar example: " + line)
                }
            }
        }
        NSApp.terminate(nil)
    }

    static func renderDemo(store: AppStore) async {
        guard store.isDemo else { return }
        try? await Task.sleep(for: .seconds(1))
        let view = NSHostingView(rootView: DevelopmentPreview(store: store))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: ProcessInfo.processInfo.arguments.contains("--preview-dark") ? .darkAqua : .aqua)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        defer { NSApp.terminate(nil) }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        print("Preview PNG: " + data.base64EncodedString())
    }
}

/// Capture the real label beside representative macOS menu bar controls.
/// Only the resulting PNGs are included in published builds.
private struct MenuBarExampleCapture: View {
    let store: AppStore
    let dark: Bool
    var width: CGFloat = 360

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            MenuBarLabel(store: store)
            Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
            Image(systemName: "switch.2").font(.system(size: 13, weight: .medium))
            Text("09:41").font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
        .font(.system(size: 13))
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 16)
        .frame(width: width, height: 34)
        .background(dark ? Color(red: 0.16, green: 0.17, blue: 0.19) : Color(red: 0.93, green: 0.94, blue: 0.96))
    }
}
#endif
