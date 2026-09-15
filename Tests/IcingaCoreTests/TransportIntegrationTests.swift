import Foundation
import Testing
@testable import IcingaCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ICINGA_TLS_TEST_URL"] != nil))
struct TransportIntegrationTests {
    private func endpoint(_ path: String, wrongHostname: Bool = false) throws -> URL {
        let base = try #require(ProcessInfo.processInfo.environment["ICINGA_TLS_TEST_URL"])
        var parts = try #require(URLComponents(string: base))
        if wrongHostname { parts.host = "127.0.0.1" }
        return try #require(parts.url).appendingPathComponent(path)
    }
    private func trustedTransport() throws -> SessionTransport {
        let path = try #require(ProcessInfo.processInfo.environment["ICINGA_TLS_TEST_CA"])
        return try SessionTransport(customCA: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    @Test func privateCAConnectsThroughURLSession() async throws {
        let transport = try trustedTransport()
        let response = try await transport.send(URLRequest(url: endpoint("ok")))
        #expect(response.statusCode == 200)
    }

    @Test func customCADoesNotDisableHostnameValidation() async throws {
        let transport = try trustedTransport()
        let request = try URLRequest(url: endpoint("ok", wrongHostname: true))
        await #expect(throws: (any Error).self) { try await transport.send(request) }
    }

    @Test func privateCAIsNotTrustedByDefault() async throws {
        let transport = try SessionTransport()
        let request = try URLRequest(url: endpoint("ok"))
        await #expect(throws: (any Error).self) { try await transport.send(request) }
    }

    @Test func authenticatedRequestsNeverFollowRedirects() async throws {
        let transport = try trustedTransport()
        var request = try URLRequest(url: endpoint("redirect"))
        request.setValue("Basic Zml4dHVyZTpwYXNzd29yZA==", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        #expect(response.statusCode == 302)
    }

    @Test func clientFetchesBothQueriesOverRealTLS() async throws {
        let config = try InstanceConfiguration(name: "Local fixture", apiURL: endpoint("").absoluteString, username: "fixture")
        let client = try IcingaClient(instance: config, password: "password", transport: trustedTransport())
        let snapshot = try await client.fetchSnapshot()
        #expect(snapshot.objects.count == 2)
        #expect(snapshot.objects.first { $0.id.kind == .service }?.severity == .critical)
    }
}
