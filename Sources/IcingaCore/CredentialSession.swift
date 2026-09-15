import Foundation

public protocol CredentialStorage {
    func password(for id: UUID) throws -> String?
    func save(_ password: String, for id: UUID) throws
    func delete(_ id: UUID) throws
}

/// Keeps authorized credentials in memory and prevents polling or view appearances from repeating denied reads.
@MainActor
public final class CredentialSession {
    private let storage: any CredentialStorage
    private var cached: [UUID: Result<String?, any Error>] = [:]

    public init(storage: any CredentialStorage) { self.storage = storage }

    public func password(for id: UUID, retryAccess: Bool = false) throws -> String? {
        if retryAccess { cached.removeValue(forKey: id) }
        if let result = cached[id] { return try result.get() }
        let result = Result { try storage.password(for: id) }
        cached[id] = result
        return try result.get()
    }

    public func save(_ password: String, for id: UUID) throws {
        try storage.save(password, for: id)
        cached[id] = .success(password)
    }

    public func delete(_ id: UUID) throws {
        try storage.delete(id)
        cached.removeValue(forKey: id)
    }
}
