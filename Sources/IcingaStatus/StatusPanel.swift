import AppKit
import SwiftUI
import IcingaCore

enum PanelStyle {
    static let inset: CGFloat = 20
    static let radius: CGFloat = 12
    static let surface = Color.primary.opacity(0.04)
    static let background = Color(nsColor: .windowBackgroundColor)
}

struct StatusPanel: View {
    let store: AppStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var selectedInstance: UUID?
    @State private var showInstances = false
    @State var scope: CheckListScope = .problems
    @State var showFilters = false
    @FocusState private var searchFocused: Bool

    private var filtersActive: Bool { !search.isEmpty || selectedInstance != nil }
    private var showsCheckList: Bool { scope != .problems || !store.aggregate.problems.isEmpty }
    private var visibleObjects: [MonitoredObject] {
        store.aggregate.listedObjects(in: scope, instanceID: selectedInstance, search: search,
                                      instanceNames: Dictionary(uniqueKeysWithValues: store.instances.map { ($0.id, $0.name) }))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = store.storageError {
                Label(error, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.red).padding(PanelStyle.inset)
            }
            if store.instances.isEmpty {
                welcome
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if scope == .problems {
                            summary
                            StatusOverview(status: store.aggregate)
                            instanceList
                        } else if store.aggregate.hasIncompleteCoverage || store.aggregate.isPaused {
                            coverageNotice
                        }
                        if showsCheckList { checkList }
                    }
                    .padding(PanelStyle.inset)
                }
                .id(scope)
                .defaultScrollAnchor(.top)
            }
            footer
        }
        .frame(width: 460, height: scope == .problems && !showsCheckList && !showInstances && !store.instances.isEmpty ? 460 : 640)
        .background(PanelStyle.background)
        .onChange(of: store.instances.map(\.id)) { _, ids in
            if let selectedInstance, !ids.contains(selectedInstance) { self.selectedInstance = nil }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                AppLogo(size: 24)
                Text("Icinga Status").font(.system(size: 15, weight: .semibold))
                Spacer()
                #if DEBUG
                if let scenario = store.demoScenario {
                    DemoScenarioMenu(store: store, scenario: scenario)
                } else if store.isDemo { Text("Demo").font(.caption).foregroundStyle(.secondary) }
                #endif
                if store.isMuted {
                    Image(systemName: "bell.slash").foregroundStyle(.secondary)
                        .help("Notifications muted for one hour")
                }
            }
            if !store.instances.isEmpty {
                Picker("View", selection: $scope) {
                    Text("Overview").tag(CheckListScope.problems)
                    Text("Hosts · \(store.aggregate.hosts.total)").tag(CheckListScope.hosts)
                    Text("Services · \(store.aggregate.services.total)").tag(CheckListScope.services)
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("checkListScope")
            }
        }
        .padding(.horizontal, PanelStyle.inset).padding(.vertical, 16)
        .background(PanelStyle.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var summary: some View {
        let status = store.aggregate
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .font(.system(size: 20, weight: .medium)).foregroundStyle(status.color)
                .frame(width: 40, height: 40)
                .background(status.color.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(status.title).font(.system(size: 16, weight: .semibold))
                    .accessibilityIdentifier("aggregateTitle")
                Text(summaryDetail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
        }
    }

    private var summaryDetail: String {
        let status = store.aggregate
        if status.isPaused || status.enabledCount == 0 { return "Showing the last known results." }
        if status.unavailableCount > 0 {
            return "\(status.unavailableCount) \(status.unavailableCount == 1 ? "instance is" : "instances are") unavailable. Some results may be out of date."
        }
        if status.waitingCount > 0 { return "Waiting for \(status.waitingCount) \(status.waitingCount == 1 ? "instance" : "instances") to respond." }
        if status.emptyCount > 0 { return "An instance returned no checks. Review its API permissions." }
        if status.pendingCount > 0 { return "\(status.pendingCount) checks are waiting for their first result." }
        if status.suppressedCount > 0 && status.problems.isEmpty { return "\(status.suppressedCount) problems are covered by your monitoring filters." }
        return "\(status.objectCount) checks across \(status.enabledCount) \(status.enabledCount == 1 ? "instance" : "instances")."
    }

    private var coverageNotice: some View {
        Label(summaryDetail, systemImage: store.aggregate.isPaused ? "pause.circle"
              : store.aggregate.unavailableCount > 0 ? "exclamationmark.icloud" : "clock")
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelStyle.surface, in: RoundedRectangle(cornerRadius: PanelStyle.radius))
    }

    private var instanceList: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showInstances.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack").foregroundStyle(.secondary)
                    Text("Instances").fontWeight(.medium)
                    Spacer()
                    Text(store.aggregate.unavailableCount > 0 ? "\(store.aggregate.unavailableCount) unavailable" : "\(store.aggregate.enabledCount) enabled")
                        .font(.caption).foregroundStyle(store.aggregate.unavailableCount > 0 ? Color.orange : .secondary)
                    Image(systemName: showInstances ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(14).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("toggleInstances")
            .accessibilityLabel("\(showInstances ? "Hide" : "Show") instances")
            if showInstances {
                Divider().padding(.horizontal, 14)
                VStack(spacing: 0) {
                    ForEach(store.instances) { instance in
                        InstanceStatusRow(instance: instance, runtime: store.runtimes[instance.id] ?? InstanceRuntime(),
                                          paused: store.isPaused || store.isSleeping, now: store.now, webURL: store.webURL(for: instance.id))
                        if instance.id != store.instances.last?.id { Divider().padding(.leading, 22) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
            }
        }
        .background(PanelStyle.surface, in: RoundedRectangle(cornerRadius: PanelStyle.radius))
    }

    private var checkList: some View {
        let objects = visibleObjects
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(scope.title).font(.headline)
                Text("\(objects.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showFilters.toggle() }
                    searchFocused = showFilters
                } label: {
                    Label(filtersActive ? "Filtered" : "Filter", systemImage: "line.3.horizontal.decrease")
                        .font(.callout).foregroundStyle(showFilters || filtersActive ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless).keyboardShortcut("f")
                .help(showFilters ? "Hide filters (⌘F)" : "Search and filter (⌘F)")
                .accessibilityIdentifier("toggleCheckFilters")
            }
            if showFilters { filterControls }
            if filtersActive && !showFilters {
                HStack(spacing: 8) {
                    Text([search.isEmpty ? nil : "“\(search)”", selectedInstance.map { store.instanceName($0) }].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Clear", action: clearFilters).buttonStyle(.borderless)
                }
                .font(.caption)
            }
            if scope == .problems, store.aggregate.suppressedCount > 0 {
                Text("\(store.aggregate.suppressedCount) more hidden by monitoring filters")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if objects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(filtersActive ? "No matching checks" : "No \(scope.title.lowercased()) yet")
                        .font(.subheadline.weight(.medium))
                    Text(filtersActive ? "Try a different search or clear your filters." : "Checks will appear after an enabled instance returns its inventory.")
                        .font(.callout).foregroundStyle(.secondary)
                    if filtersActive { Button("Clear filters", action: clearFilters).buttonStyle(.borderless) }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(objects) { object in
                        CheckRow(object: object, store: store)
                        if object.id != objects.last?.id { Divider().padding(.leading, 42) }
                    }
                }
                .background(PanelStyle.surface, in: RoundedRectangle(cornerRadius: PanelStyle.radius))
            }
        }
        .accessibilityIdentifier("checkList")
    }

    private var filterControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search checks or output", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused).accessibilityIdentifier("checkSearch")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }
            if store.instances.count > 1 || filtersActive {
                HStack {
                    if store.instances.count > 1 {
                        Picker("Instance", selection: $selectedInstance) {
                            Text("All instances").tag(nil as UUID?)
                            ForEach(store.instances) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .labelsHidden().controlSize(.small).accessibilityLabel("Filter checks by instance")
                    }
                    Spacer()
                    if filtersActive { Button("Reset", action: clearFilters).buttonStyle(.borderless).font(.caption) }
                }
            }
        }
        .padding(12)
        .background(PanelStyle.surface, in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity)
    }

    private func clearFilters() { search = ""; selectedInstance = nil }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            AppLogo(size: 56)
            Text("Keep an eye on\nyour infrastructure.").font(.system(size: 24, weight: .semibold))
            Text("Follow your Icinga 2 instances from the menu bar, and go straight to the checks that need you.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Connect an instance…") { showSettings() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("addFirstInstance")
            Text("You’ll need an API URL and a monitoring account.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(32).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { store.refreshAll() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                .help(store.isDemo ? "Replay sample scenario (⌘R)" : "Refresh now (⌘R)")
                .keyboardShortcut("r").accessibilityLabel(store.isDemo ? "Replay sample scenario" : "Refresh now")
                .disabled(!canRefresh)
            if store.runtimes.values.contains(where: \.isRefreshing) {
                ProgressView().controlSize(.mini).accessibilityLabel("Refreshing")
                Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(activityText)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button(store.isPaused ? "Resume monitoring" : "Pause monitoring") { store.togglePaused() }
                Button(store.isMuted ? "Unmute notifications" : "Mute notifications for 1 hour") {
                    if store.isMuted { store.unmute() } else { store.muteForOneHour() }
                }
                Divider()
                Button("About Icinga Status…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "about")
                }
                .accessibilityIdentifier("openAbout")
                CheckForUpdatesButton()
                Divider()
                Button("Quit Icinga Status") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24, height: 24)
            .help("More options").accessibilityLabel("More options").accessibilityIdentifier("moreOptions")
            Button { showSettings() } label: { Image(systemName: "gearshape").frame(width: 24, height: 24) }
                .keyboardShortcut(",").help("Settings (⌘,)").accessibilityLabel("Settings")
                .accessibilityIdentifier("openSettings")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(PanelStyle.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private var canRefresh: Bool {
        #if DEBUG
        if store.demoScenario != nil { return true }
        #endif
        return !store.isPaused && !store.isSleeping && !store.instances.isEmpty && !store.isDemo
    }

    private var activityText: String {
        #if DEBUG
        if let scenario = store.demoScenario { return "Sample data · \(scenario.title)" }
        #endif
        return store.isPaused || store.isSleeping ? "Monitoring paused"
            : "\(store.aggregate.enabledCount) \(store.aggregate.enabledCount == 1 ? "instance" : "instances") enabled"
    }
}
