import Foundation
import Security

public enum IcingaError: LocalizedError, Sendable {
    case authentication, permission, server(Int), invalidResponse, invalidCertificate, actionFailed(String), missingPassword
    case invalidObjectResponse(endpoint: String, detail: String)
    public var errorDescription: String? {
        switch self {
        case .authentication: "Authentication failed. Check the API username and password."
        case .permission: "Permission denied. Check this API user's host and service query permissions."
        case .server(let code): "The API returned HTTP \(code). Check the endpoint and Icinga server."
        case .invalidResponse: "The server returned an unexpected response. Check that this is the Icinga 2 API URL."
        case .invalidObjectResponse(let endpoint, let detail): "Could not read the Icinga \(endpoint) response. \(detail)"
        case .invalidCertificate: "The certificate file is not a valid PEM or DER certificate."
        case .actionFailed(let message): "Icinga could not complete the action: \(message)"
        case .missingPassword: "No password is stored for this instance. Open Settings to enter it."
        }
    }
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public init(data: Data, statusCode: Int) { self.data = data; self.statusCode = statusCode }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public final class SessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init(customCA: Data? = nil) throws {
        if let customCA { _ = try CertificateBundle.certificates(from: customCA) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: TrustDelegate(customCA: customCA), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw IcingaError.invalidResponse }
        return HTTPResponse(data: data, statusCode: response.statusCode)
    }
}

public enum CertificateBundle {
    public static func certificates(from data: Data) throws -> [SecCertificate] {
        if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN CERTIFICATE-----") {
            let certificates = text.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().compactMap { part -> SecCertificate? in
                guard let encoded = part.components(separatedBy: "-----END CERTIFICATE-----").first,
                      let decoded = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else { return nil }
                return SecCertificateCreateWithData(nil, decoded as CFData)
            }
            guard !certificates.isEmpty else { throw IcingaError.invalidCertificate }
            return certificates
        }
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else { throw IcingaError.invalidCertificate }
        return [certificate]
    }
}

private final class TrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    let customCA: Data?
    init(customCA: Data?) { self.customCA = customCA }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let customCA, let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        do {
            let certificates = try CertificateBundle.certificates(from: customCA)
            let policy = SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)
            guard SecTrustSetPolicies(trust, policy) == errSecSuccess,
                  SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
                  SecTrustEvaluateWithError(trust, nil) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        } catch {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // A configured API endpoint must respond directly. Never redirect its Authorization header.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum IcingaAction: Sendable {
    case recheck
    case acknowledge(author: String, comment: String)
}

public struct IcingaClient: Sendable {
    private let instance: InstanceConfiguration
    private let password: String
    private let transport: any HTTPTransport

    public init(instance: InstanceConfiguration, password: String, transport: (any HTTPTransport)? = nil) throws {
        try instance.validate()
        guard !password.isEmpty else { throw IcingaError.missingPassword }
        self.instance = instance
        self.password = password
        self.transport = try transport ?? SessionTransport(customCA: instance.customCA)
    }

    public func fetchSnapshot() async throws -> InstanceSnapshot {
        async let hosts = fetchObjects(kind: .host)
        async let services = fetchObjects(kind: .service)
        // Publish only complete host + service snapshots. A partial query cannot clear incidents.
        return try await InstanceSnapshot(objects: hosts + services)
    }

    public func perform(_ action: IcingaAction, on object: ObjectID) async throws {
        guard object.instanceID == instance.id, instance.allowsActions else { throw IcingaError.permission }
        let path: String
        var body: [String: Any] = [
            "type": object.kind.rawValue,
            "filter": object.kind == .host ? "host.name == target_name" : "service.__name == target_name",
            "filter_params": ["target_name": object.name]
        ]
        switch action {
        case .recheck:
            path = "reschedule-check"
            body["force"] = true
        case .acknowledge(let author, let comment):
            guard !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw IcingaError.actionFailed("Enter an author and comment.")
            }
            path = "acknowledge-problem"
            body["author"] = author
            body["comment"] = comment
            body["sticky"] = true
            body["notify"] = false
            body["persistent"] = false
        }
        let request = try makeRequest(path: "actions/\(path)", body: JSONSerialization.data(withJSONObject: body))
        let data = try await checkedResponse(request)
        let response = try JSONDecoder().decode(ActionResponse.self, from: data)
        guard !response.results.isEmpty else { throw IcingaError.actionFailed("The object was not found or is not accessible.") }
        for result in response.results where !(200..<300).contains(result.code) {
            throw IcingaError.actionFailed(result.status ?? "The server rejected the action.")
        }
    }

    private func fetchObjects(kind: ObjectKind) async throws -> [MonitoredObject] {
        var attrs = ["name", "display_name", "state", "state_type", "acknowledgement",
                     "downtime_depth", "last_check_result", "last_state_change"]
        if kind == .service { attrs.append("host_name") }
        let endpoint = kind == .host ? "hosts" : "services"
        let body = try JSONSerialization.data(withJSONObject: ["attrs": attrs])
        var request = try makeRequest(path: "objects/\(endpoint)", body: body)
        request.setValue("GET", forHTTPHeaderField: "X-HTTP-Method-Override")
        let data = try await checkedResponse(request)
        do {
            let results = try JSONDecoder().decode(ObjectResponse.self, from: data).results
            guard Set(results.map(\.name)).count == results.count else {
                throw IcingaError.invalidObjectResponse(endpoint: endpoint, detail: "The response contains duplicate object identities.")
            }
            return try results.map { result in
                let attrs = result.attrs
                guard kind != .service || attrs.host_name != nil else {
                    throw IcingaError.invalidObjectResponse(endpoint: endpoint, detail: "A service is missing attrs.host_name.")
                }
                return MonitoredObject(
                    id: ObjectID(instanceID: instance.id, kind: kind, name: result.name),
                    hostName: kind == .host ? result.name : attrs.host_name!,
                    serviceName: kind == .service ? attrs.name : nil,
                    displayName: attrs.display_name ?? attrs.name,
                    // Icinga 2 has no has_been_checked attribute. A check result exists only after a check ran.
                    state: attrs.state, hasBeenChecked: attrs.last_check_result != nil,
                    isHardState: attrs.state_type == 1, isAcknowledged: attrs.acknowledgement != 0,
                    isInDowntime: attrs.downtime_depth > 0,
                    output: attrs.last_check_result?.output ?? "",
                    lastStateChange: attrs.last_state_change.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                )
            }
        } catch let error as DecodingError {
            throw Self.decodingError(error, endpoint: endpoint, data: data)
        }
    }

    private static func decodingError(_ error: DecodingError, endpoint: String, data: Data) -> IcingaError {
        let prefix = String(decoding: data.prefix(256), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if prefix.hasPrefix("<") {
            return .invalidObjectResponse(endpoint: endpoint, detail: "The server returned HTML instead of JSON. Check whether a proxy is serving a login or error page.")
        }
        func path(_ keys: [any CodingKey]) -> String {
            keys.reduce("") { result, key in
                if let index = key.intValue { return result + "[\(index)]" }
                return result + (result.isEmpty ? "" : ".") + key.stringValue
            }
        }
        let detail: String
        switch error {
        case .keyNotFound(let key, let context):
            detail = "Missing field \(path(context.codingPath + [key]))."
        case .valueNotFound(_, let context):
            detail = "Unexpected null at \(path(context.codingPath))."
        case .typeMismatch(_, let context):
            detail = "Unexpected value type at \(path(context.codingPath).isEmpty ? "the response root" : path(context.codingPath))."
        case .dataCorrupted(let context):
            detail = context.codingPath.isEmpty ? "The response is not valid JSON." : "Invalid value at \(path(context.codingPath))."
        @unknown default:
            detail = "The response does not match the expected Icinga JSON structure."
        }
        // Include only schema paths, never response bodies, check output, URLs, or credentials.
        return .invalidObjectResponse(endpoint: endpoint, detail: detail)
    }

    private func makeRequest(path: String, body: Data) throws -> URLRequest {
        let url = try instance.validatedBaseURL().appendingPathComponent("v1/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic " + Data("\(instance.username):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        return request
    }

    private func checkedResponse(_ request: URLRequest) async throws -> Data {
        let response = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return response.data
        case 401: throw IcingaError.authentication
        case 403: throw IcingaError.permission
        default: throw IcingaError.server(response.statusCode)
        }
    }
}

private struct ObjectResponse: Decodable {
    let results: [Result]
    struct Result: Decodable {
        let name: String
        let attrs: Attributes
    }
    struct Attributes: Decodable {
        let name: String
        let display_name: String?
        let host_name: String?
        let state: Int
        let state_type: Int
        let acknowledgement: Int
        let downtime_depth: Int
        let last_state_change: Double?
        let last_check_result: CheckResult?
    }
    struct CheckResult: Decodable { let output: String? }
}

private struct ActionResponse: Decodable {
    let results: [Result]
    struct Result: Decodable { let code: Int; let status: String? }
}
