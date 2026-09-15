#if DEBUG
import Foundation
import Testing
@testable import IcingaCore

private let demoTime = Date(timeIntervalSince1970: 1_800_000_000)
private func status(_ scenario: DemoScenario, filters: FilterSettings = FilterSettings()) -> AggregateStatus {
    let data = DemoData(scenario: scenario, now: demoTime)
    return AggregateStatus(instances: data.instances, runtimes: data.runtimes, filters: filters,
                           isPaused: data.isPaused, now: demoTime)
}

@Test func healthyDemoHasCompleteGreenInventoryAcrossFourInstances() throws {
    let data = DemoData(scenario: .healthy, now: demoTime)
    #expect(data.instances.count == 4)
    for instance in data.instances {
        try instance.validate()
        #expect(!instance.allowsActions)
        #expect(instance.objectWebURL(hostName: "db-01", serviceName: "Disk space") != nil)
    }
    let aggregate = status(.healthy)
    #expect(aggregate.isHealthy)
    #expect(aggregate.hosts.total == 12)
    #expect(aggregate.services.total == 48)
    #expect(aggregate.problems.isEmpty)
    #expect(aggregate.hosts[.healthy] == 12)
    #expect(aggregate.services[.healthy] == 48)
}

@Test func mixedDemoCoversAllStatesAndHandledProblems() {
    let aggregate = status(.mixed)
    #expect(aggregate.problems.count == 4)
    #expect(aggregate.suppressedCount == 3)
    #expect(aggregate.unavailableCount == 1)
    #expect(aggregate.pendingCount == 1)
    #expect(aggregate.hosts[.critical] == 1)
    for severity in Severity.allCases { #expect(aggregate.services[severity] > 0) }
    #expect(aggregate.allObjects.contains { $0.isAcknowledged })
    #expect(aggregate.allObjects.contains { $0.isInDowntime })
    #expect(aggregate.allObjects.contains { !$0.isHardState })
}

@Test(arguments: [DemoScenario.warnings, .critical, .unknown])
func severityScenariosKeepProblemStatesDistinct(scenario: DemoScenario) {
    let aggregate = status(scenario)
    let expected: Severity = scenario == .warnings ? .warning : scenario == .critical ? .critical : .unknown
    #expect(!aggregate.problems.isEmpty)
    #expect(aggregate.problems.allSatisfy { $0.severity == expected })
    #expect(!aggregate.hasIncompleteCoverage)
    #expect(!aggregate.isHealthy)
}

@Test(arguments: [DemoScenario.acknowledged, .downtime, .softStates])
func handledScenariosCanBeRevealedWithMonitoringFilters(scenario: DemoScenario) {
    let aggregate = status(scenario)
    #expect(aggregate.problems.isEmpty)
    #expect(aggregate.suppressedCount == 4)
    #expect(aggregate.allObjects.filter(\.isProblem).count == 4)
    var filters = FilterSettings()
    filters.includeAcknowledged = true
    filters.includeDowntime = true
    filters.includeSoftStates = true
    #expect(status(scenario, filters: filters).problems.count == 4)
}

@Test func coverageScenariosNeverPretendToBeHealthy() {
    for scenario in [DemoScenario.pending, .connecting, .connectionFailure, .stale, .empty, .paused, .disabled] {
        #expect(!status(scenario).isHealthy)
    }
    #expect(status(.pending).pendingCount == 60)
    #expect(status(.connecting).waitingCount == 4)
    #expect(status(.connectionFailure).unavailableCount == 3)
    #expect(status(.connectionFailure).objectCount == 45)
    #expect(status(.stale).unavailableCount == 4)
    #expect(status(.stale).objectCount == 60)
    #expect(status(.empty).emptyCount == 4)
    #expect(status(.paused).isPaused)
    #expect(status(.disabled).enabledCount == 0)
}

@Test func switchingScenariosKeepsInstanceAndObjectIdentitiesStable() {
    let healthy = DemoData(scenario: .healthy, now: demoTime)
    let mixed = DemoData(scenario: .mixed, now: demoTime)
    #expect(healthy.instances.map(\.id) == mixed.instances.map(\.id))
    #expect(Set(status(.healthy).allObjects.map(\.id)) == Set(status(.mixed).allObjects.map(\.id)))
    #expect(Set(status(.healthy).allObjects.map(\.id)).count == 60)
    #expect(status(.largeInventory).objectCount == 800)
    #expect(Set(status(.largeInventory).allObjects.map(\.id)).count == 800)
}

@Test(arguments: DemoScenario.allCases)
func replayingScenariosRetainsTheirMeaningAtANewTime(scenario: DemoScenario) {
    let later = demoTime.addingTimeInterval(3600)
    let data = DemoData(scenario: scenario, now: later)
    let replay = AggregateStatus(instances: data.instances, runtimes: data.runtimes, filters: FilterSettings(),
                                 isPaused: data.isPaused, now: later)
    let original = status(scenario)
    #expect(replay.isHealthy == original.isHealthy)
    #expect(replay.unavailableCount == original.unavailableCount)
    #expect(replay.pendingCount == original.pendingCount)
    #expect(replay.problems.map(\.id) == original.problems.map(\.id))
}
#endif
