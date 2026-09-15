import Foundation

public enum ObjectKind: String, Codable, Sendable { case host = "Host", service = "Service" }

public enum Severity: Int, Codable, Comparable, Sendable, CaseIterable {
    case healthy = 0, pending = 1, warning = 2, unknown = 3, critical = 4
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var title: String {
        switch self {
        case .healthy: "OK"
        case .pending: "Pending"
        case .warning: "Warning"
        case .unknown: "Unknown"
        case .critical: "Critical"
        }
    }
}

public struct ObjectID: Hashable, Codable, Sendable {
    public let instanceID: UUID
    public let kind: ObjectKind
    public let name: String
    public init(instanceID: UUID, kind: ObjectKind, name: String) {
        self.instanceID = instanceID; self.kind = kind; self.name = name
    }
}

public struct MonitoredObject: Identifiable, Equatable, Sendable {
    public let id: ObjectID
    public let hostName: String
    public let serviceName: String?
    public let displayName: String
    public let state: Int
    public let hasBeenChecked: Bool
    public let isHardState: Bool
    public let isAcknowledged: Bool
    public let isInDowntime: Bool
    public let output: String
    public let lastStateChange: Date?

    public init(id: ObjectID, hostName: String, serviceName: String? = nil, displayName: String,
                state: Int, hasBeenChecked: Bool = true, isHardState: Bool = true,
                isAcknowledged: Bool = false, isInDowntime: Bool = false,
                output: String = "", lastStateChange: Date? = nil) {
        self.id = id; self.hostName = hostName; self.serviceName = serviceName
        self.displayName = displayName; self.state = state; self.hasBeenChecked = hasBeenChecked
        self.isHardState = isHardState; self.isAcknowledged = isAcknowledged
        self.isInDowntime = isInDowntime; self.output = output; self.lastStateChange = lastStateChange
    }

    public var severity: Severity {
        guard hasBeenChecked else { return .pending }
        if id.kind == .host { return state == 0 ? .healthy : (state == 1 ? .critical : .unknown) }
        return switch state {
        case 0: .healthy
        case 1: .warning
        case 2: .critical
        default: .unknown
        }
    }
    public var stateTitle: String {
        if id.kind == .host, hasBeenChecked, state == 1 { return "Down" }
        return severity.title
    }
    public var isProblem: Bool { hasBeenChecked && severity > .pending }
}

public struct InstanceSnapshot: Equatable, Sendable {
    public var objects: [MonitoredObject]
    public var fetchedAt: Date
    public init(objects: [MonitoredObject], fetchedAt: Date = .now) {
        self.objects = objects; self.fetchedAt = fetchedAt
    }
}

public struct InstanceRuntime: Equatable, Sendable {
    public var snapshot: InstanceSnapshot?
    public var error: String?
    public var isRefreshing = false
    public init(snapshot: InstanceSnapshot? = nil, error: String? = nil) {
        self.snapshot = snapshot; self.error = error
    }
    public func isStale(interval: Double, now: Date) -> Bool {
        guard let snapshot else { return true }
        return error != nil || now.timeIntervalSince(snapshot.fetchedAt) > max(90, interval * 3)
    }
}

public struct CheckCounts: Equatable, Sendable {
    private var counts: [Severity: Int] = [:]
    public init(objects: [MonitoredObject]) {
        for object in objects { counts[object.severity, default: 0] += 1 }
    }
    public subscript(_ severity: Severity) -> Int { counts[severity, default: 0] }
    public var total: Int { counts.values.reduce(0, +) }
}

public struct AggregateStatus: Sendable {
    public let hosts: CheckCounts
    public let services: CheckCounts
    /// All retained checks from enabled instances, unaffected by incident filters.
    public let allObjects: [MonitoredObject]
    public let problems: [MonitoredObject]
    public let suppressedCount: Int
    public let objectCount: Int
    public let pendingCount: Int
    public let enabledCount: Int
    public let unavailableCount: Int
    public let waitingCount: Int
    public let emptyCount: Int
    public let isPaused: Bool
    public let configuredCount: Int
    public var severity: Severity { problems.map(\.severity).max() ?? .healthy }
    public var hasIncompleteCoverage: Bool { unavailableCount > 0 || waitingCount > 0 || emptyCount > 0 || pendingCount > 0 }
    public var isHealthy: Bool {
        enabledCount > 0 && !isPaused && !hasIncompleteCoverage && problems.isEmpty
    }

    public init(instances: [InstanceConfiguration], runtimes: [UUID: InstanceRuntime],
                filters: FilterSettings, isPaused: Bool = false, now: Date = .now) {
        configuredCount = instances.count
        self.isPaused = isPaused
        let enabled = instances.filter(\.isEnabled)
        enabledCount = enabled.count
        var all: [MonitoredObject] = []
        var unavailable = 0, waiting = 0, empty = 0
        for instance in enabled {
            let runtime = runtimes[instance.id] ?? InstanceRuntime()
            if runtime.error != nil { unavailable += 1 }
            else if runtime.snapshot == nil { waiting += 1 }
            else if runtime.isStale(interval: instance.pollingInterval, now: now) { unavailable += 1 }
            if let snapshot = runtime.snapshot {
                all += snapshot.objects
                if snapshot.objects.isEmpty { empty += 1 }
            }
        }
        unavailableCount = unavailable; waitingCount = waiting; emptyCount = empty
        objectCount = all.count
        allObjects = all
        hosts = CheckCounts(objects: all.filter { $0.id.kind == .host })
        services = CheckCounts(objects: all.filter { $0.id.kind == .service })
        pendingCount = all.filter { !$0.hasBeenChecked }.count
        problems = all.filter(filters.includes).sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.hostName != $1.hostName { return $0.hostName.localizedStandardCompare($1.hostName) == .orderedAscending }
            if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
            return $0.id.instanceID.uuidString < $1.id.instanceID.uuidString
        }
        suppressedCount = all.filter(\.isProblem).count - problems.count
    }

    public var title: String {
        if configuredCount == 0 { return "Connect your first instance" }
        if isPaused || enabledCount == 0 { return "Monitoring paused" }
        if !problems.isEmpty { return "\(problems.count) \(problems.count == 1 ? "problem needs" : "problems need") attention" }
        if unavailableCount > 0 { return "Monitoring is incomplete" }
        if waitingCount > 0 { return "Connecting to your instances" }
        if emptyCount > 0 { return "No objects visible" }
        if pendingCount > 0 { return "Waiting for check results" }
        return suppressedCount > 0 ? "No actionable problems" : "All systems operational"
    }
}
