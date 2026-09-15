#if DEBUG
import Foundation

public enum DemoScenario: String, CaseIterable, Sendable {
    case mixed, healthy, warnings, critical, unknown, acknowledged, downtime, softStates
    case pending, connecting, connectionFailure, stale, empty, paused, disabled, largeInventory

    public var title: String {
        switch self {
        case .mixed: "Mixed incidents"
        case .healthy: "All green"
        case .warnings: "Warnings"
        case .critical: "Critical and hosts down"
        case .unknown: "Unknown checks"
        case .acknowledged: "Acknowledged problems"
        case .downtime: "Scheduled downtime"
        case .softStates: "Soft states"
        case .pending: "Pending checks"
        case .connecting: "Connecting"
        case .connectionFailure: "API failures"
        case .stale: "Stale results"
        case .empty: "Empty inventory"
        case .paused: "Monitoring paused"
        case .disabled: "All instances disabled"
        case .largeInventory: "Large inventory"
        }
    }
}

/// Deterministic, in-memory fixtures shared by development previews and tests.
/// Identifiers stay stable across scenarios so navigation and filters keep working.
public struct DemoData: Sendable {
    public let instances: [InstanceConfiguration]
    public let runtimes: [UUID: InstanceRuntime]
    public let isPaused: Bool

    public init(scenario: DemoScenario, now: Date = .now) {
        let names = ["Production · Europe", "Production · US", "Staging", "Office"]
        let domains = ["eu", "us", "staging", "office"]
        instances = names.indices.map { index in
            var instance = InstanceConfiguration(
                id: UUID(uuidString: String(format: "D0000000-0000-0000-0000-%012d", index + 1))!,
                name: names[index], apiURL: "https://\(domains[index]).icinga.example.com:5665", username: "demo-monitor",
                webURL: "https://\(domains[index]).icinga.example.com/icingaweb2", isEnabled: scenario != .disabled)
            instance.webInterface = index.isMultiple(of: 2) ? .icingadb : .monitoring
            return instance
        }
        isPaused = scenario == .paused
        var results: [UUID: InstanceRuntime] = [:]
        for (index, instance) in instances.enumerated() {
            if scenario == .connecting {
                results[instance.id] = InstanceRuntime()
                continue
            }
            var objects: [MonitoredObject] = []
            let hosts = scenario == .largeInventory
                ? (1...40).map { String(format: "node-%03d", $0) } : ["db-01", "api-02", "worker-03"]
            for (hostIndex, host) in hosts.enumerated() {
                let down = (scenario == .mixed && index == 0 && hostIndex == 0)
                    || (scenario == .critical && index < 2 && hostIndex == 0)
                objects.append(MonitoredObject(
                    id: ObjectID(instanceID: instance.id, kind: .host, name: host), hostName: host, displayName: host,
                    state: down ? 1 : 0, hasBeenChecked: scenario != .pending,
                    output: scenario == .pending ? "Waiting for the first host check." : down ? "Host did not respond to the reachability check." : "Host is up. Round-trip time: 1.2 ms.",
                    lastStateChange: now.addingTimeInterval(-3600)))
                for (serviceIndex, service) in ["Disk space", "Response time", "Queue depth", "TLS certificate"].enumerated() {
                    var state = 0, checked = scenario != .pending, hard = true, acknowledged = false, downtime = false
                    let firstHost = hostIndex == 0
                    switch scenario {
                    case .mixed:
                        if index == 0 && firstHost { state = [2, 1, 3, 0][serviceIndex] }
                        if index == 1 && firstHost {
                            state = [2, 1, 2, 0][serviceIndex]
                            acknowledged = serviceIndex == 0
                            downtime = serviceIndex == 1
                            hard = serviceIndex != 2
                        }
                        if index == 2 && firstHost && serviceIndex == 0 { checked = false }
                    case .warnings: if firstHost && serviceIndex == 1 { state = 1 }
                    case .critical: if firstHost && serviceIndex == 0 { state = 2 }
                    case .unknown: if firstHost && serviceIndex == 3 { state = 3 }
                    case .acknowledged: if firstHost && serviceIndex == 0 { state = 2; acknowledged = true }
                    case .downtime: if firstHost && serviceIndex == 2 { state = 2; downtime = true }
                    case .softStates: if firstHost && serviceIndex == 1 { state = 2; hard = false }
                    case .largeInventory: if hostIndex.isMultiple(of: 10) && serviceIndex == 0 { state = 1 }
                    default: break
                    }
                    let output: String
                    if !checked { output = "Waiting for the first service check." }
                    else if acknowledged { output = "DISK CRITICAL: /var has 3% free. Acknowledged while the volume is expanded." }
                    else if downtime { output = "Queue check suspended during scheduled maintenance." }
                    else if !hard { output = "HTTP CRITICAL: connection refused. Retry 1 of 3." }
                    else {
                        output = switch state {
                        case 1: "WARNING: response time 1.82 s exceeds the 1.0 s threshold."
                        case 2: "CRITICAL: /var/lib/postgresql has 2.1 GB (3%) free.\nThreshold: 10% free."
                        case 3: "UNKNOWN: the check plugin returned no usable result."
                        default: ["DISK OK: 128 GB (64%) free.", "HTTP OK: 200, response time 0.12 s.",
                                  "QUEUE OK: 3 jobs waiting, oldest 2 s.", "TLS OK: certificate expires in 83 days."][serviceIndex]
                        }
                    }
                    objects.append(MonitoredObject(
                        id: ObjectID(instanceID: instance.id, kind: .service, name: "\(host)!\(service)"),
                        hostName: host, serviceName: service, displayName: service, state: state,
                        hasBeenChecked: checked, isHardState: hard, isAcknowledged: acknowledged, isInDowntime: downtime,
                        output: output, lastStateChange: checked ? now.addingTimeInterval(-840) : nil))
                }
            }
            var runtime = InstanceRuntime(snapshot: InstanceSnapshot(objects: scenario == .empty ? [] : objects, fetchedAt: now))
            if scenario == .stale || (scenario == .mixed && index == 3) || (scenario == .connectionFailure && index > 0) {
                runtime.snapshot?.fetchedAt = now.addingTimeInterval(-600)
            }
            if scenario == .mixed && index == 3 { runtime.error = "Cannot reach the API. Check the network or VPN." }
            if scenario == .connectionFailure {
                switch index {
                case 1: runtime.error = "TLS connection failed. The server certificate could not be trusted."
                case 2:
                    runtime.error = "Authentication failed (HTTP 401). Check the API credentials."
                    runtime.snapshot = nil
                case 3: runtime.error = "The API did not respond in time. Retrying automatically."
                default: break
                }
            }
            results[instance.id] = runtime
        }
        runtimes = results
    }
}
#endif
