import Foundation
import Testing
@testable import IcingaCore

@Test func objectLinksUseEachModulesDetailRoutes() {
    var instance = InstanceConfiguration(webURL: "https://example.com/icingaweb2/")
    instance.webInterface = .monitoring
    #expect(instance.objectWebURL(hostName: "db-01")?.absoluteString ==
            "https://example.com/icingaweb2/monitoring/host/show?host=db-01")
    #expect(instance.objectWebURL(hostName: "db-01", serviceName: "disk")?.absoluteString ==
            "https://example.com/icingaweb2/monitoring/service/show?host=db-01&service=disk")
    instance.webInterface = .icingadb
    #expect(instance.objectWebURL(hostName: "db-01")?.absoluteString ==
            "https://example.com/icingaweb2/icingadb/host?name=db-01")
    #expect(instance.objectWebURL(hostName: "db-01", serviceName: "disk")?.absoluteString ==
            "https://example.com/icingaweb2/icingadb/service?name=disk&host.name=db-01")
}

@Test func objectLinksNormalizeModulePagesAndPreserveInstallationPrefixes() {
    var instance = InstanceConfiguration(webURL: "https://example.com:8443/proxy%20path/icingaweb2/icingadb/services?state=2#!/old/page")
    #expect(instance.objectWebURL(hostName: "db-01")?.absoluteString ==
            "https://example.com:8443/proxy%20path/icingaweb2/icingadb/host?name=db-01")
    instance.webInterface = .monitoring
    #expect(instance.objectWebURL(hostName: "db-01")?.absoluteString ==
            "https://example.com:8443/proxy%20path/icingaweb2/monitoring/host/show?host=db-01")
    instance.webInterface = .automatic
    instance.webURL = "http://example.com/monitoring/host/show?host=old"
    #expect(instance.objectWebURL(hostName: "new")?.absoluteString ==
            "http://example.com/monitoring/host/show?host=new")
    instance.webURL = "https://example.com"
    #expect(instance.objectWebURL(hostName: "new")?.path == "/monitoring/host/show")
}

@Test(arguments: [IcingaWebInterface.monitoring, .icingadb])
func objectLinksEncodeNamesForPHP(module: IcingaWebInterface) throws {
    var instance = InstanceConfiguration(webURL: "https://example.com/icingaweb2")
    instance.webInterface = module
    let host = "host + & # ? % / 台灣"
    let service = "Disk / + &name=other; %2B #?!=東京"
    let url = try #require(instance.objectWebURL(hostName: host, serviceName: service))
    let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(parts.fragment == nil)
    // Simulate PHP's form decoding, including '+' becoming a space.
    let query = try #require(parts.percentEncodedQuery)
    let values = Dictionary(uniqueKeysWithValues: query.split(separator: "&").map { pair in
        let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
        return (pieces[0], pieces[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding!)
    })
    #expect(values.count == 2)
    #expect(values[module == .icingadb ? "host.name" : "host"] == host)
    #expect(values[module == .icingadb ? "name" : "service"] == service)
}

@Test func webInterfaceChoicePersistsAndOlderInstancesStillDecode() throws {
    var instance = InstanceConfiguration(webURL: "https://example.com/icingadb")
    let oldJSON = try JSONEncoder().encode(instance)
    let oldInstance = try JSONDecoder().decode(InstanceConfiguration.self, from: oldJSON)
    #expect(oldInstance.webInterface == nil)
    #expect(oldInstance.objectWebURL(hostName: "db-01")?.path == "/icingadb/host")
    instance.webInterface = .icingadb
    let restored = try JSONDecoder().decode(InstanceConfiguration.self, from: JSONEncoder().encode(instance))
    #expect(restored.webInterface == .icingadb)
}

@Test(arguments: ["", "not a URL", "file:///tmp/icinga", "javascript:alert(1)", "https://user:password@example.com"])
func missingOrInvalidWebURLsHaveNoObjectLinks(base: String) {
    #expect(InstanceConfiguration(webURL: base).objectWebURL(hostName: "db-01") == nil)
}
