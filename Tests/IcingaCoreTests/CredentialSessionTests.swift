import Foundation
import Testing
@testable import IcingaCore

private enum CredentialFailure: Error { case denied }

private final class MemoryCredentials: CredentialStorage {
    var values: [UUID: String] = [:]
    var reads = 0
    var denyRead = false
    var denyWrite = false

    func password(for id: UUID) throws -> String? {
        reads += 1
        if denyRead { throw CredentialFailure.denied }
        return values[id]
    }

    func save(_ password: String, for id: UUID) throws {
        if denyWrite { throw CredentialFailure.denied }
        values[id] = password
    }

    func delete(_ id: UUID) throws {
        if denyWrite { throw CredentialFailure.denied }
        values.removeValue(forKey: id)
    }
}

@Suite @MainActor struct CredentialSessionTests {
    @Test func repeatedReadsUseSessionCacheAndKeepInstancesSeparate() throws {
        let storage = MemoryCredentials()
        let first = UUID(), second = UUID()
        storage.values = [first: "first", second: "second"]
        let session = CredentialSession(storage: storage)
        for _ in 0..<10 {
            #expect(try session.password(for: first) == "first")
            #expect(try session.password(for: second) == "second")
        }
        #expect(storage.reads == 2)
    }

    @Test func deniedReadsWaitForExplicitRetry() throws {
        let storage = MemoryCredentials()
        let id = UUID()
        storage.values[id] = "saved"
        storage.denyRead = true
        let session = CredentialSession(storage: storage)
        for _ in 0..<10 {
            #expect(throws: CredentialFailure.self) { try session.password(for: id) }
        }
        #expect(storage.reads == 1)
        storage.denyRead = false
        #expect(throws: CredentialFailure.self) { try session.password(for: id) }
        #expect(try session.password(for: id, retryAccess: true) == "saved")
        #expect(try session.password(for: id) == "saved")
        #expect(storage.reads == 2)
    }

    @Test func missingCredentialIsCachedUntilSaved() throws {
        let storage = MemoryCredentials()
        let session = CredentialSession(storage: storage)
        let id = UUID()
        #expect(try session.password(for: id) == nil)
        #expect(try session.password(for: id) == nil)
        try session.save("new", for: id)
        #expect(try session.password(for: id) == "new")
        #expect(storage.values[id] == "new")
        #expect(storage.reads == 1)
    }

    @Test func failedWritesPreserveAuthorizedCredential() throws {
        let storage = MemoryCredentials()
        let session = CredentialSession(storage: storage)
        let id = UUID()
        try session.save("original", for: id)
        storage.denyWrite = true
        #expect(throws: CredentialFailure.self) { try session.save("replacement", for: id) }
        #expect(throws: CredentialFailure.self) { try session.delete(id) }
        #expect(try session.password(for: id) == "original")
        #expect(storage.values[id] == "original")
        #expect(storage.reads == 0)
    }

    @Test func deletionRemovesCachedCredential() throws {
        let storage = MemoryCredentials()
        let session = CredentialSession(storage: storage)
        let id = UUID()
        try session.save("original", for: id)
        try session.delete(id)
        #expect(try session.password(for: id) == nil)
        #expect(storage.values[id] == nil)
        #expect(storage.reads == 1)
    }
}
