import Foundation

public struct BrowserBadgeStatus: Equatable, Sendable {
    public enum State: Sendable { case healthy, problems, connectionFailure, waiting, paused, unconfigured }
    public let state: State
    public let hostCount: Int
    public let serviceCount: Int
    public let unavailableCount: Int
    public let waitingCount: Int
    public let pendingCount: Int
    public let emptyCount: Int

    public init(_ aggregate: AggregateStatus) {
        unavailableCount = aggregate.unavailableCount
        waitingCount = aggregate.waitingCount
        pendingCount = aggregate.pendingCount
        emptyCount = aggregate.emptyCount
        if aggregate.configuredCount == 0 { state = .unconfigured }
        else if aggregate.isPaused || aggregate.enabledCount == 0 { state = .paused }
        else if !aggregate.problems.isEmpty { state = .problems }
        else if aggregate.unavailableCount > 0 { state = .connectionFailure }
        else if aggregate.hasIncompleteCoverage { state = .waiting }
        else { state = .healthy }

        if state == .problems {
            hostCount = aggregate.problems.filter { $0.id.kind == .host }.count
            serviceCount = aggregate.problems.filter { $0.id.kind == .service }.count
        } else {
            hostCount = aggregate.hosts.total
            serviceCount = aggregate.services.total
        }
    }

    public var accessibilityDescription: String {
        let headline: String
        switch state {
        case .healthy: headline = "No actionable problems. \(hostCount) hosts, \(serviceCount) services monitored."
        case .problems: headline = "\(hostCount) host problems and \(serviceCount) service problems."
        case .connectionFailure: headline = "Monitoring connection failed. Last known totals: \(hostCount) hosts, \(serviceCount) services."
        case .waiting: headline = "Waiting for complete monitoring results. \(hostCount) hosts, \(serviceCount) services visible."
        case .paused: headline = "Monitoring paused. Last known totals: \(hostCount) hosts, \(serviceCount) services."
        case .unconfigured: headline = "Connect your first Icinga instance."
        }
        return headline
            + (unavailableCount > 0 ? " \(unavailableCount) API connections unavailable; retained results may be stale." : "")
            + (waitingCount > 0 ? " Connecting to \(waitingCount) instances." : "")
            + (pendingCount > 0 ? " \(pendingCount) checks pending." : "")
            + (emptyCount > 0 ? " \(emptyCount) instances returned no visible objects." : "")
    }
}

/// Coalesce simultaneous instance completions into at most one brief highlight per second.
public struct RefreshPulsePolicy: Sendable {
    public static let duration: TimeInterval = 0.25
    private var lastStartedAt: Date?
    public init() {}

    public mutating func shouldPulse(at now: Date, enabled: Bool, reduceMotion: Bool) -> Bool {
        guard enabled, !reduceMotion,
              lastStartedAt.map({ now.timeIntervalSince($0) >= 1 }) ?? true else { return false }
        lastStartedAt = now
        return true
    }
}
