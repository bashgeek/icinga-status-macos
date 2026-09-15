import Foundation
import Security
import IcingaCore

struct KeychainStore: CredentialStorage {
    private let service = "net.blendbyte.icingastatus.api"

    func password(for id: UUID) throws -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return password
    }

    func save(_ password: String, for id: UUID) throws {
        let data = Data(password.utf8)
        let query = baseQuery(id)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    func delete(_ id: UUID) throws {
        let status = SecItemDelete(baseQuery(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        if [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed].contains(status) {
            return "Keychain access was not authorized. In Settings → Instances, choose Unlock saved password to retry."
        }
        return "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Could not access the stored credential (\(status)).")"
    }
}

struct ConfigurationStore {
    let fileURL: URL
    init() throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("IcingaStatus", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("configuration.json")
    }

    func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppConfiguration() }
        let value = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: fileURL))
        guard value.version == 1 else { throw StorageError.unsupportedVersion }
        guard Set(value.instances.map(\.id)).count == value.instances.count else { throw StorageError.duplicateInstances }
        for instance in value.instances { try instance.validate() }
        return value
    }

    func save(_ configuration: AppConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

enum StorageError: LocalizedError {
    case unsupportedVersion, duplicateInstances, unavailable
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This configuration was written by a newer version of Icinga Status. Update the app to open it."
        case .duplicateInstances: "The configuration contains duplicate instance IDs. Restore a valid configuration before making changes."
        case .unavailable: "Configuration storage is unavailable. Resolve the storage error before making changes."
        }
    }
}
