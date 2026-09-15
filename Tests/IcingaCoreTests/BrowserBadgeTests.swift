import Foundation
import Testing
@testable import IcingaCore

private let badgeInstance = InstanceConfiguration(name: "Test", apiURL: "https://example.com:5665", username: "monitor")
private func badgeObject(kind: ObjectKind, state: Int = 0, checked: Bool = true, acknowledged: Bool = false) -> MonitoredObject {
    MonitoredObject(id: ObjectID(instanceID: badgeInstance.id, kind: kind, name: kind == .host ? "host" : "host!check"),
                    hostName: "host", serviceName: kind == .service ? "check" : nil, displayName: "Check",
                    state: state, hasBeenChecked: checked, isAcknowledged: acknowledged)
}

private func badge(objects: [MonitoredObject], error: String? = nil, paused: Bool = false, age: TimeInterval = 0) -> BrowserBadgeStatus {
    BrowserBadgeStatus(AggregateStatus(instances: [badgeInstance], runtimes: [
        badgeInstance.id: InstanceRuntime(snapshot: InstanceSnapshot(objects: objects, fetchedAt: .now.addingTimeInterval(-age)), error: error)
    ], filters: FilterSettings(), isPaused: paused))
}

@Test func healthyBrowserBadgeShowsInventoryTotals() {
    let result = badge(objects: [badgeObject(kind: .host), badgeObject(kind: .service)])
    #expect(result.state == .healthy)
    #expect(result.hostCount == 1)
    #expect(result.serviceCount == 1)
}

@Test(arguments: [1, 2, 3]) func browserBadgeShowsProblemCountsInsteadOfTotals(serviceState: Int) {
    let result = badge(objects: [badgeObject(kind: .host), badgeObject(kind: .service, state: serviceState)])
    #expect(result.state == .problems)
    #expect(result.hostCount == 0)
    #expect(result.serviceCount == 1)
}

@Test func hostDownContributesToHostProblemCount() {
    let result = badge(objects: [badgeObject(kind: .host, state: 1), badgeObject(kind: .service)])
    #expect(result.state == .problems)
    #expect(result.hostCount == 1)
    #expect(result.serviceCount == 0)
}

@Test func browserBadgeReportsAPIErrorAlongsideKnownProblems() {
    let result = badge(objects: [badgeObject(kind: .service, state: 2)], error: "Offline")
    #expect(result.state == .problems)
    #expect(result.serviceCount == 1)
    #expect(result.unavailableCount == 1)
    #expect(result.accessibilityDescription.contains("API connections unavailable"))
}

@Test func connectionFailuresAndStaleResultsCannotTurnBadgeGreen() {
    let objects = [badgeObject(kind: .host), badgeObject(kind: .service)]
    #expect(badge(objects: objects, error: "Authentication failed").state == .connectionFailure)
    #expect(badge(objects: objects, age: 120).state == .connectionFailure)
    let id = UUID()
    let other = InstanceConfiguration(id: id, name: "Other", apiURL: "https://other.example.com:5665", username: "monitor")
    let partial = BrowserBadgeStatus(AggregateStatus(instances: [badgeInstance, other], runtimes: [
        badgeInstance.id: InstanceRuntime(snapshot: InstanceSnapshot(objects: objects)),
        id: InstanceRuntime(error: "Offline")
    ], filters: FilterSettings()))
    #expect(partial.state == .connectionFailure)
    #expect(partial.unavailableCount == 1)
    #expect(partial.hostCount == 1)
}

@Test func browserBadgeDistinguishesPausedPendingEmptyAndInitialStates() {
    #expect(badge(objects: [badgeObject(kind: .host)], paused: true).state == .paused)
    #expect(badge(objects: [badgeObject(kind: .service, checked: false)]).state == .waiting)
    #expect(badge(objects: []).state == .waiting)
    let initial = BrowserBadgeStatus(AggregateStatus(instances: [badgeInstance], runtimes: [:], filters: FilterSettings()))
    #expect(initial.state == .waiting)
    #expect(initial.waitingCount == 1)
    let empty = BrowserBadgeStatus(AggregateStatus(instances: [], runtimes: [:], filters: FilterSettings()))
    #expect(empty.state == .unconfigured)
}

@Test func browserBadgeRespectsProblemFiltersWhilePreservingTotals() {
    let result = badge(objects: [badgeObject(kind: .service, state: 2, acknowledged: true)])
    #expect(result.state == .healthy)
    #expect(result.serviceCount == 1)
    #expect(result.accessibilityDescription.contains("No actionable problems"))
}

@Test func refreshPulseCoalescesBurstsAndHonorsReducedMotion() {
    var policy = RefreshPulsePolicy()
    let time = Date(timeIntervalSince1970: 1000)
    let samples: [(TimeInterval, Bool, Bool)] = [
        (0, false, false), (0, true, true), (0, true, false),
        (0.1, true, false), (0.9, true, false), (1, true, false)
    ]
    let results = samples.map { delay, enabled, reduceMotion in
        policy.shouldPulse(at: time.addingTimeInterval(delay), enabled: enabled, reduceMotion: reduceMotion)
    }
    #expect(results == [false, false, true, false, false, true])
}

@Test func browserBadgePreferencesRoundTripWithSafeOldDefaults() throws {
    var preferences = AppPreferences()
    preferences.menuBarDisplay = .browserBadge
    preferences.pulseOnRefresh = false
    let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored.effectiveMenuBarDisplay == .browserBadge)
    #expect(!restored.effectivePulseOnRefresh)
    preferences.pulseOnRefresh = nil
    let old = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(old.effectivePulseOnRefresh)
}
