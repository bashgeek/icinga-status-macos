import Foundation

public struct InstanceConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var apiURL: String
    public var username: String
    public var webURL: String
    // Optional so existing saved instances continue to decode.
    public var webInterface: IcingaWebInterface?
    public var refreshInterval: Double
    public var isEnabled: Bool
    public var allowsActions: Bool
    public var customCA: Data?
    public var customCAName: String?

    public init(id: UUID = UUID(), name: String = "", apiURL: String = "", username: String = "",
                webURL: String = "", refreshInterval: Double = 30, isEnabled: Bool = true,
                allowsActions: Bool = false, customCA: Data? = nil, customCAName: String? = nil) {
        self.id = id
        self.name = name
        self.apiURL = apiURL
        self.username = username
        self.webURL = webURL
        self.refreshInterval = refreshInterval
        self.isEnabled = isEnabled
        self.allowsActions = allowsActions
        self.customCA = customCA
        self.customCAName = customCAName
    }

    public var pollingInterval: Double { max(10, min(refreshInterval, 3600)) }

    public func validatedBaseURL() throws -> URL {
        guard var parts = URLComponents(string: apiURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw ConfigurationError.invalidAPIURL
        }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path.hasSuffix("/v1") { parts.path.removeLast(3) }
        guard let url = parts.url else { throw ConfigurationError.invalidAPIURL }
        return url
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.missingName
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.contains(":") else { throw ConfigurationError.invalidUsername }
        _ = try validatedBaseURL()
        if !webURL.isEmpty {
            guard let parts = URLComponents(string: webURL), parts.scheme == "https" || parts.scheme == "http",
                  let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else {
                throw ConfigurationError.invalidWebURL
            }
        }
        guard refreshInterval.isFinite, (10...3600).contains(refreshInterval) else {
            throw ConfigurationError.invalidInterval
        }
    }
}

public enum ConfigurationError: LocalizedError {
    case missingName, invalidAPIURL, invalidUsername, invalidWebURL, invalidInterval
    public var errorDescription: String? {
        switch self {
        case .missingName: "Give this instance a name."
        case .invalidAPIURL: "Enter an HTTPS API URL, for example https://icinga.example.com:5665. Keep credentials in the fields below."
        case .invalidUsername: "Enter an API username without a colon."
        case .invalidWebURL: "Enter a valid HTTP or HTTPS web interface URL without credentials."
        case .invalidInterval: "Choose a refresh interval between 10 and 3,600 seconds."
        }
    }
}

public struct FilterSettings: Codable, Equatable, Sendable {
    public var includeAcknowledged = false
    public var includeDowntime = false
    public var includeSoftStates = false
    public var ignoredHosts = ""
    public var ignoredServices = ""
    public init() {}

    public func includes(_ object: MonitoredObject) -> Bool {
        guard object.isProblem,
              includeAcknowledged || !object.isAcknowledged,
              includeDowntime || !object.isInDowntime,
              includeSoftStates || object.isHardState else { return false }
        return !Self.matches(object.hostName, patterns: ignoredHosts)
            && !Self.matches(object.serviceName ?? "", patterns: ignoredServices)
    }

    /// Case-insensitive glob patterns, one per line. Only * and ? are special.
    public static func matches(_ value: String, patterns: String) -> Bool {
        guard !value.isEmpty else { return false }
        return patterns.components(separatedBy: .newlines).contains { line in
            let pattern = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { return false }
            let expression = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            return value.range(of: expression, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

public enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case browserBadge, fullStatus, problemCount, icon
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var filters = FilterSettings()
    public var iconOnly = false
    // Optional for compatibility with configurations saved before display modes existed.
    public var menuBarDisplay: MenuBarDisplay?
    public var pulseOnRefresh: Bool?
    public var effectivePulseOnRefresh: Bool { pulseOnRefresh ?? true }
    public var effectiveMenuBarDisplay: MenuBarDisplay { menuBarDisplay ?? (iconOnly ? .icon : .fullStatus) }
    public var notificationsEnabled = false
    public var recoveryNotifications = false
    public var notificationSound = false
    public init() {}
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var version = 1
    public var instances: [InstanceConfiguration] = []
    public var preferences = AppPreferences()
    public init() {}
}
