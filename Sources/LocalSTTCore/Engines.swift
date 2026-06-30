import Foundation

public struct EngineConfiguration: Codable, Equatable, Sendable {
    public var whisperBinary: String
    public var whisperModel: String
    public var sherpaBinary: String
    public var segmentationModel: String
    public var embeddingModel: String
    public var openCCBinary: String
    public init(whisperBinary: String = "", whisperModel: String = "", sherpaBinary: String = "", segmentationModel: String = "", embeddingModel: String = "", openCCBinary: String = "/opt/homebrew/bin/opencc") {
        self.whisperBinary = whisperBinary; self.whisperModel = whisperModel
        self.sherpaBinary = sherpaBinary; self.segmentationModel = segmentationModel
        self.embeddingModel = embeddingModel; self.openCCBinary = openCCBinary
    }
}

public enum EngineError: LocalizedError {
    case missingFile(String), processFailed(String), malformedOutput(String)
    public var errorDescription: String? {
        switch self {
        case .missingFile(let path): "Required local file is missing: \(path)"
        case .processFailed(let message): "Local engine failed: \(message)"
        case .malformedOutput(let message): "Could not read local engine output: \(message)"
        }
    }
}

public actor LocalInferenceEngine {
    public let configuration: EngineConfiguration
    public init(configuration: EngineConfiguration) { self.configuration = configuration }

    public func validate() throws {
        for path in [configuration.whisperBinary, configuration.whisperModel, configuration.sherpaBinary, configuration.segmentationModel, configuration.embeddingModel] {
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { throw EngineError.missingFile(path.isEmpty ? "not configured" : path) }
        }
    }

    public func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        try validate()
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: prefix.appendingPathExtension("json")) }
        _ = try await ProcessRunner.run(configuration.whisperBinary, arguments: [
            "-m", configuration.whisperModel, "-f", audioURL.path, "-l", "zh", "-oj", "-of", prefix.path, "--no-prints"
        ])
        let data = try Data(contentsOf: prefix.appendingPathExtension("json"))
        return try WhisperJSONParser.parse(data)
    }

    public func diarize(audioURL: URL) async throws -> [SpeakerTurn] {
        try validate()
        let output = try await ProcessRunner.run(configuration.sherpaBinary, arguments: [
            "--segmentation-pyannote-model=\(configuration.segmentationModel)",
            "--embedding-model=\(configuration.embeddingModel)", audioURL.path
        ])
        return RTTMParser.parse(output)
    }

    public func convertToTraditional(_ text: String) async -> String {
        guard FileManager.default.isExecutableFile(atPath: configuration.openCCBinary) else {
            return ConservativeTraditionalConverter.convert(text)
        }
        return (try? await ProcessRunner.run(configuration.openCCBinary, arguments: ["-c", "s2twp.json"], standardInput: text))?.trimmingCharacters(in: .newlines) ?? ConservativeTraditionalConverter.convert(text)
    }
}

enum ProcessRunner {
    static func run(_ executable: String, arguments: [String], standardInput: String? = nil) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.isExecutableFile(atPath: executable) else { throw EngineError.missingFile(executable) }
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.standardOutput = output; process.standardError = errors
            if let standardInput {
                let input = Pipe(); process.standardInput = input
                try process.run(); input.fileHandleForWriting.write(Data(standardInput.utf8)); try input.fileHandleForWriting.close()
            } else { try process.run() }
            process.waitUntilExit()
            let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            guard process.terminationStatus == 0 else { throw EngineError.processFailed(stderr.isEmpty ? stdout : stderr) }
            return stdout
        }.value
    }
}

enum WhisperJSONParser {
    private struct Document: Decodable { let transcription: [Item] }
    private struct Item: Decodable {
        let text: String
        let offsets: Offsets?
        struct Offsets: Decodable { let from: Int; let to: Int }
    }
    static func parse(_ data: Data) throws -> [TranscriptSegment] {
        do {
            return try JSONDecoder().decode(Document.self, from: data).transcription.map {
                TranscriptSegment(start: Double($0.offsets?.from ?? 0) / 1000, end: Double($0.offsets?.to ?? 0) / 1000, rawText: $0.text)
            }
        } catch { throw EngineError.malformedOutput(error.localizedDescription) }
    }
}

enum RTTMParser {
    static func parse(_ text: String) -> [SpeakerTurn] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let p = line.split(whereSeparator: \.isWhitespace)
            guard p.count >= 8, p[0] == "SPEAKER", let start = Double(p[3]), let duration = Double(p[4]) else { return nil }
            return SpeakerTurn(start: start, end: start + duration, speakerID: String(p[7]))
        }
    }
}

public enum ConservativeTraditionalConverter {
    private static let mapping: [Character: Character] = ["汉":"漢", "语":"語", "声":"聲", "说":"說", "话":"話", "这":"這", "个":"個", "们":"們", "为":"為", "时":"時", "间":"間", "开":"開", "关":"關", "录":"錄", "听":"聽", "后":"後", "发":"發", "现":"現", "识":"識", "别":"別", "来":"來", "应":"應", "请":"請", "记":"記", "东":"東", "台":"臺"]
    public static func convert(_ text: String) -> String { String(text.map { mapping[$0] ?? $0 }) }
}
