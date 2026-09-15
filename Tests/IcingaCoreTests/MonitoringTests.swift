import Foundation
import Testing
@testable import IcingaCore

private let testID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let time = Date(timeIntervalSince1970: 1_800_000_000)

private func object(_ state: Int, kind: ObjectKind = .service, instanceID: UUID = testID,
                    checked: Bool = true, hard: Bool = true, acknowledged: Bool = false, downtime: Bool = false,
                    name: String = "Disk") -> MonitoredObject {
    MonitoredObject(id: ObjectID(instanceID: instanceID, kind: kind, name: kind == .host ? "db-01" : "db-01!\(name)"),
                    hostName: "db-01", serviceName: kind == .service ? name : nil, displayName: name,
                    state: state, hasBeenChecked: checked, isHardState: hard,
                    isAcknowledged: acknowledged, isInDowntime: downtime)
}

private func instance(_ id: UUID = testID) -> InstanceConfiguration {
    InstanceConfiguration(id: id, name: "Test", apiURL: "https://example.com:5665", username: "monitor")
}

@Test func nativeStatesMapToExplicitSeverity() {
    #expect(object(1, kind: .host).severity == .critical)
    #expect(object(1).severity == .warning)
    #expect(object(2).severity > object(3).severity)
    #expect(object(3).severity > object(1).severity)
    #expect(object(0, checked: false).severity == .pending)
    #expect(!object(2, checked: false).isProblem)
    #expect(object(9).severity == .unknown)
}

@Test func fullStatusSeparatesHostsAndServicesAndIncludesFilteredStates() {
    let objects = [object(0, kind: .host), object(1, kind: .host),
                   object(0), object(1, hard: false), object(2, acknowledged: true),
                   object(3, downtime: true), object(0, checked: false)]
    let aggregate = AggregateStatus(instances: [instance()], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: objects, fetchedAt: time))
    ], filters: FilterSettings(), now: time)
    #expect(aggregate.hosts.total == 2)
    #expect(aggregate.hosts[.healthy] == 1)
    #expect(aggregate.hosts[.critical] == 1)
    #expect(aggregate.hosts[.warning] == 0)
    #expect(aggregate.services.total == 5)
    for severity in Severity.allCases { #expect(aggregate.services[severity] == 1) }
    #expect(aggregate.problems.count == 1)
    #expect(aggregate.suppressedCount == 3)
}

@Test func fullStatusRetainsStaleCountsButExcludesDisabledInstances() {
    let secondID = UUID()
    var disabled = instance(secondID)
    disabled.isEnabled = false
    let aggregate = AggregateStatus(instances: [instance(), disabled], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(2)], fetchedAt: time.addingTimeInterval(-120))),
        secondID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(0, kind: .host, instanceID: secondID)], fetchedAt: time))
    ], filters: FilterSettings(), now: time)
    #expect(aggregate.services[.critical] == 1)
    #expect(aggregate.hosts.total == 0)
    #expect(aggregate.hasIncompleteCoverage)
    #expect(aggregate.allObjects.count == 1)
    #expect(aggregate.listedObjects(in: .services).count == 1)
    #expect(aggregate.listedObjects(in: .hosts).isEmpty)
}

@Test func inventoryIncludesEveryStateRegardlessOfIncidentFilters() {
    let objects = [object(0, kind: .host), object(0, name: "Healthy"),
                   object(1, hard: false, name: "Soft"), object(2, acknowledged: true, name: "Acknowledged"),
                   object(3, downtime: true, name: "Downtime"), object(0, checked: false, name: "Pending"),
                   object(2, name: "Ignored"), object(2, name: "Actionable")]
    var filters = FilterSettings()
    filters.ignoredServices = "Ignored"
    let status = AggregateStatus(instances: [instance()], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: objects, fetchedAt: time))
    ], filters: filters, isPaused: true, now: time)
    #expect(status.allObjects.count == 8)
    #expect(status.listedObjects(in: .hosts).count == 1)
    #expect(status.listedObjects(in: .services).count == 7)
    #expect(status.listedObjects(in: .problems).map(\.displayName) == ["Actionable"])
    #expect(status.count(for: .hosts) == 1)
    #expect(status.count(for: .services) == 7)
    #expect(status.count(for: .problems) == 1)
}

@Test func inventorySearchAndInstanceFiltersKeepIdenticalNamesSeparate() {
    let otherID = UUID()
    let status = AggregateStatus(instances: [instance(), instance(otherID)], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(0, name: "Disk 10"), object(0, name: "Disk 2")], fetchedAt: time)),
        otherID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(0, instanceID: otherID, name: "Disk 2")], fetchedAt: time))
    ], filters: FilterSettings(), now: time)
    #expect(status.listedObjects(in: .services).count == 3)
    #expect(status.listedObjects(in: .services, instanceID: testID).map(\.displayName) == ["Disk 2", "Disk 10"])
    #expect(status.listedObjects(in: .services, search: "  DISK 2  ").count == 2)
    #expect(status.listedObjects(in: .services, search: "db-01").count == 3)
    #expect(status.listedObjects(in: .services, search: "staging", instanceNames: [otherID: "Staging"]).map(\.id.instanceID) == [otherID])
    #expect(status.listedObjects(in: .services, instanceID: otherID, search: "Disk 10").isEmpty)
    #expect(status.listedObjects(in: .problems).isEmpty)
}

@Test func inventorySearchMatchesObjectNamesAndOutputWhenDisplayNameDiffers() {
    let check = MonitoredObject(id: ObjectID(instanceID: testID, kind: .service, name: "db-01!http-check"),
                                hostName: "db-01", serviceName: "http-check", displayName: "Website",
                                state: 0, output: "HTTP 200 in 0.1 seconds")
    let status = AggregateStatus(instances: [instance()], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [check], fetchedAt: time))
    ], filters: FilterSettings(), now: time)
    for search in ["http-check", "Website", "HTTP 200"] {
        #expect(status.listedObjects(in: .services, search: search).map(\.id) == [check.id])
    }
}

@Test func existingPreferencesDecodeAndKeepIconOnlyChoice() throws {
    var preferences = AppPreferences()
    for iconOnly in [true, false] {
        preferences.iconOnly = iconOnly
        let data = try JSONEncoder().encode(preferences)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "menuBarDisplay")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(AppPreferences.self, from: oldData)
        #expect(restored.effectiveMenuBarDisplay == (iconOnly ? .icon : .fullStatus))
    }
    preferences.menuBarDisplay = .problemCount
    let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(restored.effectiveMenuBarDisplay == .problemCount)
}

@Test func filteringUsesActionableStates() {
    var filters = FilterSettings()
    #expect(filters.includes(object(2)))
    #expect(!filters.includes(object(0)))
    #expect(!filters.includes(object(2, hard: false)))
    #expect(!filters.includes(object(2, acknowledged: true)))
    #expect(!filters.includes(object(2, downtime: true)))
    filters.includeSoftStates = true
    filters.includeAcknowledged = true
    filters.includeDowntime = true
    #expect(filters.includes(object(2, hard: false, acknowledged: true, downtime: true)))
}

@Test func ignorePatternsAreFullGlobsWithLiteralRegexCharacters() {
    #expect(FilterSettings.matches("DB-01", patterns: "web-*\n db-?? \n"))
    #expect(!FilterSettings.matches("my-db-01", patterns: "db-*"))
    #expect(FilterSettings.matches("Disk (root)", patterns: "Disk (root)"))
    #expect(!FilterSettings.matches("Disk root", patterns: "Disk (root)"))
    var filters = FilterSettings()
    filters.ignoredServices = "dis?"
    #expect(!filters.includes(object(2)))
    #expect(filters.includes(object(1, kind: .host)))
}

@Test func offlineInstanceCannotProduceHealthyAggregate() {
    let second = UUID()
    let aggregate = AggregateStatus(instances: [instance(), instance(second)], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(0)], fetchedAt: time)),
        second: InstanceRuntime(error: "Offline")
    ], filters: FilterSettings(), now: time)
    #expect(!aggregate.isHealthy)
    #expect(aggregate.unavailableCount == 1)
    #expect(aggregate.title == "Monitoring is incomplete")
}

@Test func staleCriticalResultsStayVisibleAndIncomplete() {
    let snapshot = InstanceSnapshot(objects: [object(2)], fetchedAt: time.addingTimeInterval(-91))
    let aggregate = AggregateStatus(instances: [instance()], runtimes: [testID: InstanceRuntime(snapshot: snapshot)], filters: FilterSettings(), now: time)
    #expect(aggregate.problems.count == 1)
    #expect(aggregate.severity == .critical)
    #expect(aggregate.unavailableCount == 1)
    #expect(!aggregate.isHealthy)
}

@Test func noInstancesPausedPendingAndEmptyAreNotHealthy() {
    let blank = AggregateStatus(instances: [], runtimes: [:], filters: FilterSettings(), now: time)
    #expect(!blank.isHealthy)
    let loading = AggregateStatus(instances: [instance()], runtimes: [:], filters: FilterSettings(), now: time)
    #expect(loading.waitingCount == 1)
    #expect(!loading.isHealthy)
    for objects in [[], [object(0, checked: false)]] {
        let status = AggregateStatus(instances: [instance()], runtimes: [testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: objects, fetchedAt: time))], filters: FilterSettings(), now: time)
        #expect(!status.isHealthy)
    }
    let paused = AggregateStatus(instances: [instance()], runtimes: [testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(0)], fetchedAt: time))], filters: FilterSettings(), isPaused: true, now: time)
    #expect(!paused.isHealthy)
    #expect(paused.title == "Monitoring paused")
}

@Test func disabledInstancesDoNotContributeProblemsOrFailures() {
    var disabled = instance()
    disabled.isEnabled = false
    let status = AggregateStatus(instances: [disabled], runtimes: [testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(2)], fetchedAt: time), error: "Offline")], filters: FilterSettings(), now: time)
    #expect(status.problems.isEmpty)
    #expect(status.unavailableCount == 0)
    #expect(!status.isHealthy)
}

@Test func identicalNamesAcrossInstancesRemainDistinct() {
    let second = UUID()
    let firstObject = object(2), secondObject = object(2, instanceID: second)
    #expect(firstObject.id != secondObject.id)
    let status = AggregateStatus(instances: [instance(), instance(second)], runtimes: [
        testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [firstObject], fetchedAt: time)),
        second: InstanceRuntime(snapshot: InstanceSnapshot(objects: [secondObject], fetchedAt: time))
    ], filters: FilterSettings(), now: time)
    #expect(status.problems.count == 2)
}

@Test func suppressedProblemsAreCountedSeparately() {
    let status = AggregateStatus(instances: [instance()], runtimes: [testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: [object(2, acknowledged: true)], fetchedAt: time))], filters: FilterSettings(), now: time)
    #expect(status.isHealthy)
    #expect(status.suppressedCount == 1)
    #expect(status.title == "No actionable problems")
}

@Test func notificationBaselineAndRepeatedPollsAreQuiet() {
    var tracker = IncidentTracker()
    let snapshot = InstanceSnapshot(objects: [object(2)])
    #expect(tracker.changes(instanceID: testID, snapshot: snapshot, filters: FilterSettings()).isEmpty)
    #expect(tracker.changes(instanceID: testID, snapshot: snapshot, filters: FilterSettings()).isEmpty)
}

@Test func notificationsDetectEscalationAndConfirmedRecovery() {
    var tracker = IncidentTracker()
    _ = tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: [object(1)]), filters: FilterSettings())
    let escalated = tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: [object(2)]), filters: FilterSettings())
    #expect(escalated.count == 1)
    #expect(escalated.first?.kind == .problem)
    let recovered = tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: [object(0)]), filters: FilterSettings())
    #expect(recovered.count == 1)
    #expect(recovered.first?.kind == .recovery)
}

@Test func removedAcknowledgedAndSoftHealthyObjectsDoNotGenerateRecoveries() {
    for next in [[], [object(2, acknowledged: true)], [object(0, hard: false)]] {
        var tracker = IncidentTracker()
        _ = tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: [object(2)]), filters: FilterSettings())
        #expect(tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: next), filters: FilterSettings()).isEmpty)
    }
}

@Test func reconnectRebaselinesWithoutAnAlertFlood() {
    var tracker = IncidentTracker()
    _ = tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: [object(0)]), filters: FilterSettings())
    tracker.reset(instanceID: testID)
    #expect(tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: [object(2)]), filters: FilterSettings()).isEmpty)
}

@Test func newObjectAfterBaselineGeneratesOneAlert() {
    var tracker = IncidentTracker()
    _ = tracker.changes(instanceID: testID, snapshot: InstanceSnapshot(objects: []), filters: FilterSettings())
    let snapshot = InstanceSnapshot(objects: [object(2)])
    #expect(tracker.changes(instanceID: testID, snapshot: snapshot, filters: FilterSettings()).count == 1)
    #expect(tracker.changes(instanceID: testID, snapshot: snapshot, filters: FilterSettings()).isEmpty)
}

@Test func configurationNormalizesVersionSuffixAndPreservesProxyPath() throws {
    var config = instance()
    config.apiURL = "https://example.com/icinga-api/v1/"
    #expect(try config.validatedBaseURL().absoluteString == "https://example.com/icinga-api")
    for url in ["http://example.com", "https://user:secret@example.com", "https://example.com?token=secret", "https://example.com#fragment", "nonsense"] {
        config.apiURL = url
        #expect(throws: (any Error).self) { try config.validate() }
    }
}

@Test func configurationRoundTripsWithoutCredentials() throws {
    var configuration = AppConfiguration()
    configuration.instances = [instance()]
    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(decoded == configuration)
    #expect(!String(decoding: data, as: UTF8.self).contains("password"))
}

@Test func largeInventoryKeepsEveryIncident() {
    let objects = (0..<10_000).map { object($0 % 100 == 0 ? 2 : 0, name: "Check-\($0)") }
    let status = AggregateStatus(instances: [instance()], runtimes: [testID: InstanceRuntime(snapshot: InstanceSnapshot(objects: objects, fetchedAt: time))], filters: FilterSettings(), now: time)
    #expect(status.objectCount == 10_000)
    #expect(status.problems.count == 100)
}
