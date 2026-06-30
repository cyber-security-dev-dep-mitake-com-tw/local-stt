import CryptoKit
import Foundation
import Security

public actor SessionStore {
    public let root: URL
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public init(root: URL? = nil) throws {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LocalSTT", isDirectory: true)
        self.root = base
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    public func directory(for id: UUID) -> URL { root.appendingPathComponent("Sessions/\(id.uuidString)", isDirectory: true) }

    public func save(_ session: RecordingSession) throws {
        let folder = directory(for: session.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(session).write(to: folder.appendingPathComponent("session.json"), options: .atomic)
    }

    public func loadSessions() throws -> [RecordingSession] {
        let folder = root.appendingPathComponent("Sessions", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return try urls.compactMap { url in
            let metadata = url.appendingPathComponent("session.json")
            guard FileManager.default.fileExists(atPath: metadata.path) else { return nil }
            return try decoder.decode(RecordingSession.self, from: Data(contentsOf: metadata))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(_ session: RecordingSession) throws { try FileManager.default.removeItem(at: directory(for: session.id)) }
}

public final class VoiceProfileVault: @unchecked Sendable {
    private let service = "local-stt.voice-profile-key"
    public init() {}

    public func encrypt(_ embedding: [Float]) throws -> Data {
        let bytes = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
        return try AES.GCM.seal(bytes, using: key()).combined!
    }

    public func decrypt(_ data: Data) throws -> [Float] {
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key())
        return plain.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func key() throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecValueData as String: data]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw EngineError.processFailed("Unable to store voice-profile encryption key in Keychain") }
        return SymmetricKey(data: data)
    }
}
