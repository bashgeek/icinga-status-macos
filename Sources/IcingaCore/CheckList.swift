import Foundation

public enum CheckListScope: String, CaseIterable, Sendable {
    case problems, hosts, services

    public var title: String {
        switch self {
        case .problems: "Problems"
        case .hosts: "Hosts"
        case .services: "Services"
        }
    }
}

extension AggregateStatus {
    public func count(for scope: CheckListScope) -> Int {
        switch scope {
        case .problems: problems.count
        case .hosts: hosts.total
        case .services: services.total
        }
    }

    public func listedObjects(in scope: CheckListScope, instanceID: UUID? = nil, search: String = "",
                              instanceNames: [UUID: String] = [:]) -> [MonitoredObject] {
        Self.filter(orderedObjects(in: scope), instanceID: instanceID, search: search, instanceNames: instanceNames)
    }

    /// Every object in the scope, in display order. Sorting a large inventory is the expensive
    /// part of listing checks, so callers can cache this and filter the result as the user types.
    public func orderedObjects(in scope: CheckListScope) -> [MonitoredObject] {
        // Problems already have severity ordering. Inventory is grouped by host name
        // so the location of healthy checks stays predictable as their state changes.
        guard scope != .problems else { return problems }
        let kind: ObjectKind = scope == .hosts ? .host : .service
        return allObjects.filter { $0.id.kind == kind }.sorted {
            if $0.hostName != $1.hostName {
                return $0.hostName.localizedStandardCompare($1.hostName) == .orderedAscending
            }
            if $0.displayName != $1.displayName {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            if $0.id.instanceID != $1.id.instanceID {
                return $0.id.instanceID.uuidString < $1.id.instanceID.uuidString
            }
            return $0.id.name < $1.id.name
        }
    }

    public static func filter(_ objects: [MonitoredObject], instanceID: UUID? = nil, search: String = "",
                              instanceNames: [UUID: String] = [:]) -> [MonitoredObject] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard instanceID != nil || !query.isEmpty else { return objects }
        return objects.filter { object in
            (instanceID == nil || object.id.instanceID == instanceID)
                && (query.isEmpty || [object.hostName, object.serviceName ?? "", object.displayName,
                                     object.output, instanceNames[object.id.instanceID] ?? ""]
                    .contains { $0.localizedStandardContains(query) })
        }
    }
}
