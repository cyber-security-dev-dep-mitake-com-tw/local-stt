import Foundation

public struct AudioInputDevice: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public init(id: String, name: String, manufacturer: String = "") {
        self.id = id; self.name = name; self.manufacturer = manufacturer
    }
}

public struct SpeakerTurn: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var speakerID: String
    public var confidence: Double
    public var overlaps: Bool
    public init(start: TimeInterval, end: TimeInterval, speakerID: String, confidence: Double = 1, overlaps: Bool = false) {
        self.start = start; self.end = end; self.speakerID = speakerID
        self.confidence = confidence; self.overlaps = overlaps
    }
}

public struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var rawText: String
    public var traditionalText: String
    public var speakerID: String
    public var isProvisional: Bool
    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, rawText: String, traditionalText: String? = nil, speakerID: String = "Speaker 1", isProvisional: Bool = false) {
        self.id = id; self.start = start; self.end = end; self.rawText = rawText
        self.traditionalText = traditionalText ?? rawText
        self.speakerID = speakerID; self.isProvisional = isProvisional
    }
}

public struct SpeakerProfile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var encryptedEmbedding: Data
    public var sampleCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), name: String, encryptedEmbedding: Data, sampleCount: Int = 1, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.name = name; self.encryptedEmbedding = encryptedEmbedding
        self.sampleCount = sampleCount; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct RecordingSession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFilename: String
    public var inputDevice: AudioInputDevice
    public var segments: [TranscriptSegment]
    public var speakerCount: Int
    public init(id: UUID = UUID(), title: String, createdAt: Date = .now, duration: TimeInterval = 0, audioFilename: String, inputDevice: AudioInputDevice, segments: [TranscriptSegment] = [], speakerCount: Int = 0) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.duration = duration
        self.audioFilename = audioFilename; self.inputDevice = inputDevice
        self.segments = segments; self.speakerCount = speakerCount
    }
}
