import AppKit
import Foundation
import IcingaCore
import Network
import Observation

@MainActor @Observable
final class AppStore {
    private(set) var configuration = AppConfiguration()
    private(set) var runtimes: [UUID: InstanceRuntime] = [:]
    private(set) var isPaused = false
    private(set) var isSleeping = false
    private(set) var mutedUntil: Date?
    private(set) var now = Date.now
    private(set) var isRefreshHighlighted = false
    var storageError: String?
    let isDemo: Bool
    #if DEBUG
    private(set) var demoScenario: DemoScenario?
    #endif

    @ObservationIgnored private var persistence: ConfigurationStore?
    @ObservationIgnored private let credentials = CredentialSession(storage: KeychainStore())
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private var tracker = IncidentTracker()
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [UUID: UUID] = [:]
    @ObservationIgnored private var clients: [UUID: IcingaClient] = [:]
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let networkMonitor = NWPathMonitor()
    @ObservationIgnored private var wasOffline = false
    @ObservationIgnored private var refreshPulse = RefreshPulsePolicy()
    @ObservationIgnored private var pulseTask: Task<Void, Never>?

    var instances: [InstanceConfiguration] { configuration.instances }
    var preferences: AppPreferences { configuration.preferences }
    var isMuted: Bool { mutedUntil.map { $0 > now } ?? false }
    var aggregate: AggregateStatus {
        AggregateStatus(instances: instances, runtimes: runtimes, filters: preferences.filters,
                        isPaused: isPaused || isSleeping, now: now)
    }

    init(demo: Bool = false, isolated: Bool = false) {
        #if DEBUG
        isDemo = demo || isolated
        if demo {
            configuration.preferences.menuBarDisplay = .browserBadge
            setDemoScenario(.mixed)
        }
        #else
        isDemo = false
        #endif
        if !isDemo {
            do {
                let store = try ConfigurationStore()
                configuration = try store.load()
                persistence = store
            } catch { storageError = error.localizedDescription }
        }
        if !isDemo { installLifecycleObservers() }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self else { return }
                #if DEBUG
                if self.demoScenario != nil { self.advanceDemoClock(); continue }
                #endif
                self.now = .now
            }
        }
        restartPolling()
    }

    func password(for id: UUID) throws -> String {
        if isDemo { return "" }
        return try credentials.password(for: id) ?? ""
    }

    func unlockPassword(for id: UUID) throws -> String {
        if isDemo { return "" }
        let password = try credentials.password(for: id, retryAccess: true) ?? ""
        if let instance = instances.first(where: { $0.id == id }) {
            cancel(id)
            clients.removeValue(forKey: id)
            startPolling(instance)
        }
        return password
    }

    func save(instance: InstanceConfiguration, password: String) throws {
        try instance.validate()
        guard !password.isEmpty else { throw IcingaError.missingPassword }
        var updated = configuration
        if let index = updated.instances.firstIndex(where: { $0.id == instance.id }) { updated.instances[index] = instance }
        else { updated.instances.append(instance) }
        if !isDemo {
            guard persistence != nil else { throw StorageError.unavailable }
            let oldPassword = try credentials.password(for: instance.id)
            let passwordChanged = oldPassword != password
            if passwordChanged { try credentials.save(password, for: instance.id) }
            do { try persist(updated) }
            catch {
                if passwordChanged {
                    if let oldPassword { try? credentials.save(oldPassword, for: instance.id) }
                    else { try? credentials.delete(instance.id) }
                }
                throw error
            }
        }
        configuration = updated
        cancel(instance.id)
        runtimes.removeValue(forKey: instance.id)
        clients.removeValue(forKey: instance.id)
        tracker.reset(instanceID: instance.id)
        notifications.cancelPending()
        startPolling(instance)
    }

    func remove(_ instance: InstanceConfiguration) throws {
        var updated = configuration
        updated.instances.removeAll { $0.id == instance.id }
        // Persist first so a storage failure leaves the working connection intact.
        try persist(updated)
        configuration = updated
        cancel(instance.id)
        runtimes.removeValue(forKey: instance.id)
        clients.removeValue(forKey: instance.id)
        tracker.reset(instanceID: instance.id)
        notifications.cancelPending()
        if !isDemo { try credentials.delete(instance.id) }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) throws {
        var updated = configuration
        guard let index = updated.instances.firstIndex(where: { $0.id == id }) else { return }
        updated.instances[index].isEnabled = enabled
        try persist(updated)
        configuration = updated
        cancel(id)
        tracker.reset(instanceID: id)
        notifications.cancelPending()
        startPolling(updated.instances[index])
    }

    func updatePreferences(_ preferences: AppPreferences) throws {
        let previous = configuration.preferences
        let needsBaseline = previous.filters != preferences.filters
            || previous.notificationsEnabled != preferences.notificationsEnabled
        var updated = configuration
        updated.preferences = preferences
        try persist(updated)
        configuration = updated
        if needsBaseline { tracker.reset() }
        if previous.effectiveMenuBarDisplay != preferences.effectiveMenuBarDisplay
            || previous.effectivePulseOnRefresh != preferences.effectivePulseOnRefresh {
            clearRefreshPulse()
        }
        if needsBaseline || previous.notificationSound != preferences.notificationSound
            || previous.recoveryNotifications != preferences.recoveryNotifications {
            notifications.cancelPending()
        }
    }

    func enableNotifications() async throws -> Bool {
        guard !isDemo else { return false }
        let granted = try await notifications.requestAuthorization()
        if granted {
            var updated = preferences
            updated.notificationsEnabled = true
            try updatePreferences(updated)
        }
        return granted
    }

    func togglePaused() {
        isPaused.toggle()
        restartPolling()
    }

    func muteForOneHour() {
        mutedUntil = .now.addingTimeInterval(3600)
        now = .now
        notifications.cancelPending()
    }

    func unmute() { mutedUntil = nil }

    func refreshAll() {
        #if DEBUG
        if let demoScenario { setDemoScenario(demoScenario); return }
        #endif
        guard !isPaused, !isSleeping else { return }
        for instance in instances where instance.isEnabled {
            if runtimes[instance.id]?.isRefreshing == true { continue }
            cancel(instance.id)
            startPolling(instance)
        }
    }

    func testConnection(_ instance: InstanceConfiguration, password: String) async throws -> InstanceSnapshot {
        guard !isDemo else { throw IcingaError.actionFailed("Connection tests are unavailable with sample data.") }
        let client = try IcingaClient(instance: instance, password: password)
        return try await client.fetchSnapshot()
    }

    func perform(_ action: IcingaAction, on object: MonitoredObject) async throws {
        guard !isDemo, !isPaused, !isSleeping,
              let instance = instances.first(where: { $0.id == object.id.instanceID && $0.isEnabled }),
              let runtime = runtimes[instance.id], !runtime.isStale(interval: instance.pollingInterval, now: .now) else {
            throw IcingaError.actionFailed("Refresh this instance before trying again.")
        }
        let client = try client(for: instance)
        let generation = generations[instance.id]
        try await client.perform(action, on: object.id)
        guard generations[instance.id] == generation,
              instances.first(where: { $0.id == instance.id }) == instance else { return }
        // Restart to invalidate a poll that might have begun before the action completed.
        cancel(instance.id)
        startPolling(instance)
    }

    func canPerformActions(on object: MonitoredObject) -> Bool {
        guard !isDemo, !isPaused, !isSleeping,
              let instance = instances.first(where: { $0.id == object.id.instanceID }),
              instance.isEnabled, instance.allowsActions,
              let runtime = runtimes[instance.id] else { return false }
        return !runtime.isStale(interval: instance.pollingInterval, now: now)
    }

    func instanceName(_ id: UUID) -> String { instances.first { $0.id == id }?.name ?? "Unknown instance" }

    func webURL(for id: UUID) -> URL? {
        guard let instance = instances.first(where: { $0.id == id }), !instance.webURL.isEmpty else { return nil }
        return URL(string: instance.webURL)
    }

    func webURL(for object: MonitoredObject, hostOnly: Bool = false) -> URL? {
        guard let instance = instances.first(where: { $0.id == object.id.instanceID }) else { return nil }
        if !hostOnly, object.id.kind == .service, object.serviceName == nil { return nil }
        return instance.objectWebURL(hostName: object.hostName,
                                     serviceName: hostOnly || object.id.kind == .host ? nil : object.serviceName)
    }

    private func persist(_ updated: AppConfiguration) throws {
        if isDemo { return }
        guard let persistence else { throw StorageError.unavailable }
        try persistence.save(updated)
    }

    private func client(for instance: InstanceConfiguration) throws -> IcingaClient {
        if let client = clients[instance.id] { return client }
        let client = try IcingaClient(instance: instance, password: password(for: instance.id))
        clients[instance.id] = client
        return client
    }

    private func cancel(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        generations.removeValue(forKey: id)
        if runtimes[id] != nil { runtimes[id]?.isRefreshing = false }
    }

    private func restartPolling() {
        clearRefreshPulse()
        for id in Array(tasks.keys) { cancel(id) }
        tracker.reset()
        notifications.cancelPending()
        for instance in instances { startPolling(instance) }
    }

    private func startPolling(_ instance: InstanceConfiguration) {
        guard !isDemo, instance.isEnabled, !isPaused, !isSleeping else { return }
        let generation = UUID()
        generations[instance.id] = generation
        tasks[instance.id] = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.generations[instance.id] == generation else { return }
                var runtime = self.runtimes[instance.id] ?? InstanceRuntime()
                runtime.isRefreshing = true
                self.runtimes[instance.id] = runtime
                do {
                    let snapshot = try await self.client(for: instance).fetchSnapshot()
                    guard !Task.isCancelled, self.generations[instance.id] == generation else { return }
                    self.now = .now
                    self.runtimes[instance.id] = InstanceRuntime(snapshot: snapshot)
                    let changes = self.tracker.changes(instanceID: instance.id, snapshot: snapshot, filters: self.preferences.filters)
                    if !self.isMuted { self.notifications.enqueue(changes, instanceName: instance.name, preferences: self.preferences) }
                    failures = 0
                } catch {
                    guard !Task.isCancelled, self.generations[instance.id] == generation else { return }
                    runtime.isRefreshing = false
                    runtime.error = Self.connectionError(error)
                    self.runtimes[instance.id] = runtime
                    self.tracker.reset(instanceID: instance.id)
                    failures += 1
                }
                self.highlightRefresh()
                let delay = min(300, instance.pollingInterval * pow(2, Double(min(failures, 4))))
                do { try await Task.sleep(for: .seconds(max(instance.pollingInterval, delay))) }
                catch { return }
            }
        }
    }

    private func clearRefreshPulse() {
        pulseTask?.cancel()
        pulseTask = nil
        isRefreshHighlighted = false
    }

    private func highlightRefresh() {
        let state = BrowserBadgeStatus(aggregate).state
        guard state == .problems || state == .connectionFailure else {
            clearRefreshPulse()
            return
        }
        guard refreshPulse.shouldPulse(at: .now,
                                      enabled: preferences.effectiveMenuBarDisplay == .browserBadge && preferences.effectivePulseOnRefresh,
                                      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else { return }
        isRefreshHighlighted = true
        pulseTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(RefreshPulsePolicy.duration)) } catch { return }
            self?.isRefreshHighlighted = false
            self?.pulseTask = nil
        }
    }

    private static func connectionError(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed, .cancelled:
                return "TLS connection failed. Check the server certificate, hostname, and custom CA in Settings."
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return "Authentication or certificate trust failed. Check credentials and certificate settings."
            case .timedOut: return "The API did not respond in time. Retrying automatically."
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "Cannot reach the API. Check the address, network, or VPN."
            default: break
            }
        }
        return error.localizedDescription
    }

    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isSleeping = true; self?.restartPolling() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isSleeping = false; self?.now = .now; self?.restartPolling() }
        })
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                guard let self else { return }
                if self.wasOffline && !offline { self.restartPolling() }
                self.wasOffline = offline
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "net.blendbyte.icingastatus.network"))
    }

    #if DEBUG
    func setDemoScenario(_ scenario: DemoScenario) {
        guard isDemo else { return }
        clearRefreshPulse()
        now = .now
        let data = DemoData(scenario: scenario, now: now)
        demoScenario = scenario
        configuration.instances = data.instances
        runtimes = data.runtimes
        isPaused = data.isPaused
        isSleeping = false
        storageError = nil
        highlightRefresh()
    }

    private func advanceDemoClock() {
        let next = Date.now
        let elapsed = next.timeIntervalSince(now)
        // Preserve the scenario's freshness: all-green must not become stale merely
        // because the preview has been open for a few minutes.
        for id in Array(runtimes.keys) {
            if let fetchedAt = runtimes[id]?.snapshot?.fetchedAt {
                runtimes[id]?.snapshot?.fetchedAt = fetchedAt.addingTimeInterval(elapsed)
            }
        }
        now = next
    }
    #endif
}
