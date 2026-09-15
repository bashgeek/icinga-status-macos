import Foundation

public enum IcingaWebInterface: String, Codable, CaseIterable, Sendable {
    case automatic, monitoring, icingadb

    public var title: String {
        switch self {
        case .automatic: "Automatic from URL"
        case .monitoring: "Icinga Web 2 Monitoring"
        case .icingadb: "Icinga DB Web"
        }
    }
}

extension InstanceConfiguration {
    /// Uses object names, never display names or the API's combined host!service identifier.
    public func objectWebURL(hostName: String, serviceName: String? = nil) -> URL? {
        guard !hostName.isEmpty, serviceName != "",
              var parts = URLComponents(string: webURL),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }

        // Accept either the installation root or a copied monitoring module page.
        // Work on encoded components to retain reverse proxy prefixes verbatim.
        var path = parts.percentEncodedPath.split(separator: "/").map(String.init)
        let moduleIndex = path.firstIndex { ["monitoring", "icingadb"].contains($0.removingPercentEncoding ?? $0) }
        let inferred: IcingaWebInterface = moduleIndex.map {
            path[$0].removingPercentEncoding == "icingadb" ? .icingadb : .monitoring
        } ?? .monitoring
        let selected = webInterface ?? .automatic
        let module = selected == .automatic ? inferred : selected
        if let moduleIndex { path = Array(path.prefix(moduleIndex)) }

        var query: [URLQueryItem]
        if module == .icingadb {
            path += ["icingadb", serviceName == nil ? "host" : "service"]
            query = [URLQueryItem(name: "name", value: serviceName ?? hostName)]
            if serviceName != nil { query.append(URLQueryItem(name: "host.name", value: hostName)) }
        } else {
            path += ["monitoring", serviceName == nil ? "host" : "service", "show"]
            query = [URLQueryItem(name: "host", value: hostName)]
            if let serviceName { query.append(URLQueryItem(name: "service", value: serviceName)) }
        }
        parts.percentEncodedPath = "/" + path.joined(separator: "/")
        parts.fragment = nil
        parts.queryItems = query
        // PHP decodes a literal plus as a space, unlike URLComponents.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}
