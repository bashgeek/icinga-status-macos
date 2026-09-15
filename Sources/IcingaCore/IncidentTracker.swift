import Foundation

public struct IncidentChange: Sendable, Equatable {
    public enum Kind: Sendable { case problem, recovery }
    public let object: MonitoredObject
    public let kind: Kind
}

public struct IncidentTracker: Sendable {
    private var previous: [UUID: [ObjectID: MonitoredObject]] = [:]
    public init() {}

    public mutating func reset(instanceID: UUID? = nil) {
        if let instanceID { previous.removeValue(forKey: instanceID) }
        else { previous.removeAll() }
    }

    public mutating func changes(instanceID: UUID, snapshot: InstanceSnapshot, filters: FilterSettings) -> [IncidentChange] {
        let current = Dictionary(snapshot.objects.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        defer { previous[instanceID] = current }
        guard let baseline = previous[instanceID] else { return [] }
        var changes: [IncidentChange] = []
        for object in snapshot.objects {
            let old = baseline[object.id]
            if filters.includes(object), old.map({ !filters.includes($0) || object.severity > $0.severity }) ?? true {
                changes.append(IncidentChange(object: object, kind: .problem))
            } else if object.hasBeenChecked, object.severity == .healthy, object.isHardState,
                      let old, filters.includes(old) {
                changes.append(IncidentChange(object: object, kind: .recovery))
            }
        }
        // Missing, hidden, acknowledged, and deleted objects are never inferred to have recovered.
        return changes
    }
}
