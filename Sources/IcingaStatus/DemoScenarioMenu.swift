#if DEBUG
import SwiftUI
import IcingaCore

struct DemoScenarioMenu: View {
    let store: AppStore
    let scenario: DemoScenario

    var body: some View {
        Menu {
            Text("Sample data only")
            Picker("Scenario", selection: Binding(get: { scenario }, set: { store.setDemoScenario($0) })) {
                ForEach(DemoScenario.allCases, id: \.self) { scenario in
                    Text(scenario.title).tag(scenario)
                }
            }
            Divider()
            Picker("Menu bar style", selection: Binding(
                get: { store.preferences.effectiveMenuBarDisplay },
                set: { value in
                    var preferences = store.preferences
                    preferences.menuBarDisplay = value
                    preferences.iconOnly = value == .icon
                    try? store.updatePreferences(preferences)
                }
            )) {
                ForEach(MenuBarDisplay.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Divider()
            Button("Replay scenario") { store.setDemoScenario(scenario) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "testtube.2")
                Text("Dev data")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.08), in: Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Sample scenario: \(scenario.title). Switch scenarios and menu bar styles.")
        .accessibilityLabel("Development data: \(scenario.title)")
        .accessibilityIdentifier("demoScenarioMenu")
    }
}
#endif
