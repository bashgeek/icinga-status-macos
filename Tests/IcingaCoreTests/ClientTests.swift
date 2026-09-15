import Foundation
import Testing
@testable import IcingaCore

private actor StubTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let serviceCode: Int
    let serviceData: Data
    let actionData: Data
    init(serviceCode: Int = 200, serviceData: Data = serviceFixture,
         actionData: Data = Data(#"{"results":[{"code":200.0,"status":"Done"}]}"#.utf8)) {
        self.serviceCode = serviceCode; self.serviceData = serviceData; self.actionData = actionData
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        if request.url!.path.contains("actions") { return HTTPResponse(data: actionData, statusCode: 200) }
        if request.url!.path.hasSuffix("services") { return HTTPResponse(data: serviceData, statusCode: serviceCode) }
        return HTTPResponse(data: hostFixture, statusCode: 200)
    }
}

private let hostFixture = Data(#"{"results":[{"name":"db-01","type":"Host","attrs":{"name":"db-01","display_name":"Database","state":0.0,"state_type":1.0,"acknowledgement":0.0,"downtime_depth":0.0,"last_state_change":1700000000.0,"last_check_result":{"output":"UP"}}}]}"#.utf8)
private let serviceFixture = Data(#"{"results":[{"name":"db-01!disk","type":"Service","attrs":{"name":"disk","host_name":"db-01","display_name":"Disk space","state":2.0,"state_type":1.0,"acknowledgement":0.0,"downtime_depth":0.0,"last_state_change":1700000000.0,"last_check_result":{"output":"CRITICAL: disk almost full"}},"extra_future_field":42}]}"#.utf8)

private func configuration(actions: Bool = false) -> InstanceConfiguration {
    InstanceConfiguration(name: "Test", apiURL: "https://example.com:5665/proxy/v1/", username: "monitor", allowsActions: actions)
}

private func serviceResponse(edit: (inout [String: Any]) -> Void) throws -> Data {
    var response = try #require(JSONSerialization.jsonObject(with: serviceFixture) as? [String: Any])
    var results = try #require(response["results"] as? [[String: Any]])
    var attrs = try #require(results[0]["attrs"] as? [String: Any])
    edit(&attrs)
    results[0]["attrs"] = attrs
    response["results"] = results
    return try JSONSerialization.data(withJSONObject: response)
}

@Test func icingaCheckResultDeterminesWhetherObjectsHaveBeenChecked() async throws {
    // The Icinga 2 Checkable schema exposes last_check_result, not has_been_checked:
    // https://github.com/Icinga/icinga2/blob/master/lib/icinga/checkable.ti
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport())
    let snapshot = try await client.fetchSnapshot()
    #expect(snapshot.objects.allSatisfy { $0.hasBeenChecked })
    #expect(snapshot.objects.first { $0.id.kind == .service }?.isProblem == true)
}

@Test(arguments: [true, false]) func nullOrAbsentCheckResultsRemainPending(explicitNull: Bool) async throws {
    let data = try serviceResponse { attrs in
        if explicitNull { attrs["last_check_result"] = NSNull() }
        else { attrs.removeValue(forKey: "last_check_result") }
    }
    let config = configuration()
    let client = try IcingaClient(instance: config, password: "secret", transport: StubTransport(serviceData: data))
    let snapshot = try await client.fetchSnapshot()
    let service = try #require(snapshot.objects.first { $0.id.kind == .service })
    #expect(!service.hasBeenChecked)
    #expect(service.severity == .pending)
    #expect(!service.isProblem)
    let status = AggregateStatus(instances: [config], runtimes: [config.id: InstanceRuntime(snapshot: snapshot)], filters: FilterSettings())
    #expect(!status.isHealthy)
    #expect(status.pendingCount == 1)
}

@Test func checkResultWithoutOutputStillCountsAsChecked() async throws {
    let data = try serviceResponse { $0["last_check_result"] = ["output": NSNull()] }
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: data))
    let service = try #require(try await client.fetchSnapshot().objects.first { $0.id.kind == .service })
    #expect(service.hasBeenChecked)
    #expect(service.isProblem)
    #expect(service.output.isEmpty)
}

@Test func decodingErrorsIdentifyTheFieldWithoutExposingResponseValues() async throws {
    let data = try serviceResponse {
        $0["state"] = "private-server-detail"
        $0["last_check_result"] = ["output": "confidential check output"]
    }
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: data))
    do {
        _ = try await client.fetchSnapshot()
        Issue.record("Invalid state should reject the snapshot")
    } catch let error as IcingaError {
        let message = error.localizedDescription
        #expect(message.contains("services response"))
        #expect(message.contains("results[0].attrs.state"))
        #expect(!message.contains("private-server-detail"))
        #expect(!message.contains("confidential"))
        #expect(!message.contains("secret"))
    }
}

@Test func missingRequiredStateReportsItsPath() async throws {
    let data = try serviceResponse { $0.removeValue(forKey: "state") }
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: data))
    do {
        _ = try await client.fetchSnapshot()
        Issue.record("Missing state should reject the snapshot")
    } catch let error as IcingaError {
        #expect(error.localizedDescription.contains("Missing field results[0].attrs.state"))
    }
}

@Test func htmlResponseReportsContentMismatch() async throws {
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: Data("<html>Private login page</html>".utf8)))
    do {
        _ = try await client.fetchSnapshot()
        Issue.record("HTML should reject the snapshot")
    } catch let error as IcingaError {
        #expect(error.localizedDescription.contains("HTML instead of JSON"))
        #expect(!error.localizedDescription.contains("Private login page"))
    }
}

@Test func clientDecodesIcingaNumericStatesAndUsesMinimalQueries() async throws {
    let transport = StubTransport()
    let config = configuration()
    let client = try IcingaClient(instance: config, password: "secret", transport: transport)
    let result = try await client.fetchSnapshot()
    #expect(result.objects.count == 2)
    let service = try #require(result.objects.first { $0.id.kind == .service })
    #expect(service.hostName == "db-01")
    #expect(service.severity == .critical)
    #expect(service.id.instanceID == config.id)
    let requests = await transport.requests
    #expect(requests.count == 2)
    for request in requests {
        #expect(request.url?.path.hasPrefix("/proxy/v1/objects/") == true)
        #expect(request.value(forHTTPHeaderField: "X-HTTP-Method-Override") == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("monitor:secret".utf8).base64EncodedString())
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["attrs"] != nil)
        #expect((body["attrs"] as? [String])?.contains("has_been_checked") == false)
        #expect(body["filter"] == nil)
    }
}

@Test(arguments: [401, 403, 500]) func partialFailuresDoNotReturnSnapshots(code: Int) async throws {
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceCode: code))
    await #expect(throws: IcingaError.self) { try await client.fetchSnapshot() }
}

@Test func malformedServiceResponseDoesNotClearIncidents() async throws {
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: Data("<html>Login</html>".utf8)))
    await #expect(throws: IcingaError.self) { try await client.fetchSnapshot() }
}

@Test func emptyResultsAreValidButDistinctFromHealthyInventory() async throws {
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: Data(#"{"results":[]}"#.utf8)))
    let snapshot = try await client.fetchSnapshot()
    #expect(snapshot.objects.count == 1)
}

@Test func duplicateObjectIdentitiesRejectTheSnapshot() async throws {
    let decoded = try #require(JSONSerialization.jsonObject(with: serviceFixture) as? [String: Any])
    let results = try #require(decoded["results"] as? [[String: Any]])
    let duplicate = try JSONSerialization.data(withJSONObject: ["results": results + results])
    let client = try IcingaClient(instance: configuration(), password: "secret", transport: StubTransport(serviceData: duplicate))
    await #expect(throws: IcingaError.self) { try await client.fetchSnapshot() }
}

@Test func actionUsesExactParameterizedIdentity() async throws {
    let config = configuration(actions: true), transport = StubTransport()
    let client = try IcingaClient(instance: config, password: "secret", transport: transport)
    let hostileName = "db-01!disk\" || true"
    try await client.perform(.acknowledge(author: "Operator", comment: "Investigating"), on: ObjectID(instanceID: config.id, kind: .service, name: hostileName))
    let request = try #require(await transport.requests.first)
    let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    #expect(body["filter"] as? String == "service.__name == target_name")
    #expect((body["filter_params"] as? [String: String])?["target_name"] == hostileName)
    #expect(body["comment"] as? String == "Investigating")
    #expect(body["notify"] as? Bool == false)
    #expect(request.value(forHTTPHeaderField: "X-HTTP-Method-Override") == nil)
}

@Test func actionsRequireOptInAndMatchingInstance() async throws {
    let transport = StubTransport(), config = configuration()
    let client = try IcingaClient(instance: config, password: "secret", transport: transport)
    await #expect(throws: IcingaError.self) {
        try await client.perform(.recheck, on: ObjectID(instanceID: config.id, kind: .host, name: "db-01"))
    }
    let allowed = try IcingaClient(instance: configuration(actions: true), password: "secret", transport: transport)
    await #expect(throws: IcingaError.self) {
        try await allowed.perform(.recheck, on: ObjectID(instanceID: UUID(), kind: .host, name: "db-01"))
    }
    #expect(await transport.requests.isEmpty)
}

@Test(arguments: [#"{"results":[]}"#, #"{"results":[{"code":403,"status":"Permission denied"}]}"#])
func actionChecksPerObjectResults(json: String) async throws {
    let config = configuration(actions: true)
    let client = try IcingaClient(instance: config, password: "secret", transport: StubTransport(actionData: Data(json.utf8)))
    await #expect(throws: IcingaError.self) {
        try await client.perform(.recheck, on: ObjectID(instanceID: config.id, kind: .host, name: "db-01"))
    }
}

@Test func invalidCertificateAndMissingPasswordAreRejected() {
    #expect(throws: IcingaError.self) { try CertificateBundle.certificates(from: Data("not a certificate".utf8)) }
    #expect(throws: IcingaError.self) { try IcingaClient(instance: configuration(), password: "") }
}
