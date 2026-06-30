import AVFoundation
import Foundation
import LocalSTTCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    struct NameProposal: Identifiable, Hashable {
        let id = UUID()
        let speakerID: String
        let name: String
    }
    @Published var devices: [AudioInputDevice] = []
    @Published var selectedDeviceID = ""
    @Published var sessions: [RecordingSession] = []
    @Published var selectedSession: RecordingSession?
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var inputLevel: Float = -60
    @Published var gateOpen = false
    @Published var status = "Ready"
    @Published var nameProposals: [NameProposal] = []
    @Published var modelDownloadProgress: Double?
    @Published var gateConfiguration = NoiseGateConfiguration()
    @Published var engineConfiguration: EngineConfiguration {
        didSet { if let data = try? JSONEncoder().encode(engineConfiguration) { UserDefaults.standard.set(data, forKey: "engineConfiguration") } }
    }

    var isTranscriptionReady: Bool {
        FileManager.default.isExecutableFile(atPath: engineConfiguration.whisperBinary)
            && FileManager.default.fileExists(atPath: engineConfiguration.whisperModel)
    }

    private let capture = AudioCapture()
    private var store: SessionStore?
    private var activeSession: RecordingSession?
    private var gatedSamples: [Float] = []
    private var liveTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "engineConfiguration"), let value = try? JSONDecoder().decode(EngineConfiguration.self, from: data) { engineConfiguration = value }
        else { engineConfiguration = .init() }
        capture.onLevel = { [weak self] level, open in Task { @MainActor in self?.inputLevel = level; self?.gateOpen = open } }
        capture.onGatedSamples = { [weak self] samples in Task { @MainActor in self?.gatedSamples.append(contentsOf: samples) } }
        Task { await bootstrap() }
    }

    func bootstrap() async {
        if engineConfiguration.whisperBinary.isEmpty, FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-cli") {
            engineConfiguration.whisperBinary = "/opt/homebrew/bin/whisper-cli"
        }
        if !FileManager.default.isExecutableFile(atPath: engineConfiguration.openCCBinary), FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/opencc") {
            engineConfiguration.openCCBinary = "/opt/homebrew/bin/opencc"
        }
        devices = AudioCapture.devices(); selectedDeviceID = devices.first?.id ?? ""
        do {
            store = try SessionStore()
            var loaded = try await store?.loadSessions() ?? []
            for index in loaded.indices {
                let migrated = applyingIntroducedNames(to: loaded[index])
                if migrated != loaded[index] { try await store?.save(migrated); loaded[index] = migrated }
            }
            sessions = loaded
        }
        catch { status = error.localizedDescription }
        if !isTranscriptionReady { status = "Setup required: download the local Whisper model" }
    }

    func start() async {
        guard isTranscriptionReady else { status = "Download the local Whisper model before recording"; return }
        guard let device = devices.first(where: { $0.id == selectedDeviceID }), let store else { status = "Select an input device"; return }
        let permission = await AVCaptureDevice.requestAccess(for: .audio)
        guard permission else { status = "Microphone access was denied in System Settings"; return }
        let id = UUID(), title = Date.formattedSessionTitle
        let session = RecordingSession(id: id, title: title, audioFilename: "audio.wav", inputDevice: device)
        let folder = await store.directory(for: id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try capture.start(device: device, outputURL: folder.appendingPathComponent("audio.wav"), configuration: gateConfiguration)
            activeSession = session; gatedSamples = []; liveSegments = []; isRecording = true; status = "Recording"
            scheduleLiveInference()
        } catch { status = error.localizedDescription }
    }

    func stop() async {
        guard var session = activeSession, let store else { return }
        liveTask?.cancel(); capture.stop(); isRecording = false; isProcessing = true; status = "Finalizing transcript and speakers…"
        session.duration = Date().timeIntervalSince(session.createdAt)
        let audio = await store.directory(for: session.id).appendingPathComponent(session.audioFilename)
        do {
            let engine = LocalInferenceEngine(configuration: engineConfiguration)
            var transcript = try await engine.transcribe(audioURL: audio)
            for index in transcript.indices { transcript[index].traditionalText = await engine.convertToTraditional(transcript[index].rawText) }
            if let turns = try? await engine.diarize(audioURL: audio), !turns.isEmpty {
                session.segments = TurnReconciler.assign(transcript, to: turns)
                session.speakerCount = Set(turns.map(\.speakerID)).count
            } else {
                session.segments = transcript.map { var segment = $0; segment.speakerID = "Speaker 1"; return segment }
                session.speakerCount = transcript.isEmpty ? 0 : 1
            }
            session = applyingIntroducedNames(to: session)
            try await store.save(session); sessions = try await store.loadSessions(); selectedSession = session
            nameProposals = []
            status = "Finished — \(session.speakerCount) speaker(s)"
        } catch {
            try? await store.save(session); status = "Audio saved; processing failed: \(error.localizedDescription)"
        }
        activeSession = nil; isProcessing = false
    }

    func delete(_ session: RecordingSession) async {
        do { try await store?.delete(session); sessions = try await store?.loadSessions() ?? []; if selectedSession?.id == session.id { selectedSession = nil } }
        catch { status = error.localizedDescription }
    }

    func confirm(_ proposal: NameProposal) async {
        guard var session = selectedSession, let store else { return }
        for index in session.segments.indices where session.segments[index].speakerID == proposal.speakerID {
            session.segments[index].speakerID = proposal.name
        }
        do {
            try await store.save(session); sessions = try await store.loadSessions(); selectedSession = session
            nameProposals.removeAll { $0.id == proposal.id }
            status = "Named \(proposal.speakerID) as \(proposal.name)"
        } catch { status = error.localizedDescription }
    }

    func dismiss(_ proposal: NameProposal) { nameProposals.removeAll { $0.id == proposal.id } }

    func installWhisperModel() async {
        modelDownloadProgress = 0; status = "Downloading local Whisper model…"
        do {
            let url = try await ModelInstaller().install { [weak self] value in Task { @MainActor in self?.modelDownloadProgress = value } }
            engineConfiguration.whisperModel = url.path; status = "Whisper model installed and verified"
        } catch { status = "Model installation failed: \(error.localizedDescription)" }
        modelDownloadProgress = nil
    }

    func exportSRT(_ session: RecordingSession, to url: URL) throws { try SRTExporter.render(session.segments).write(to: url, atomically: true, encoding: .utf8) }
    func exportTXT(_ session: RecordingSession, to url: URL) throws {
        let text = session.segments.map { "[\($0.speakerID)] \($0.traditionalText)" }.joined(separator: "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func scheduleLiveInference() {
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8)); guard let self, self.isRecording, self.gatedSamples.count >= 48_000 else { continue }
                let window = Array(self.gatedSamples.suffix(16_000 * 24)), start = max(0, Double(self.gatedSamples.count - window.count) / 16_000)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString).wav")
                do {
                    try WAVWriter.write(samples: window, to: url)
                    let engine = LocalInferenceEngine(configuration: self.engineConfiguration)
                    let result = try await engine.transcribe(audioURL: url)
                    self.liveSegments = result.map { var s = $0; s.start += start; s.end += start; s.isProvisional = true; return s }
                    try? FileManager.default.removeItem(at: url)
                } catch { self.status = "Recording (live preview unavailable: \(error.localizedDescription))" }
            }
        }
    }

    private func applyingIntroducedNames(to original: RecordingSession) -> RecordingSession {
        var session = original
        let introducedNames = Dictionary(grouping: session.segments, by: \.speakerID).compactMapValues { segments in
            segments.lazy.compactMap { SpokenNameExtractor.extract(from: $0.traditionalText) }.first
        }
        for index in session.segments.indices {
            if let name = introducedNames[session.segments[index].speakerID] { session.segments[index].speakerID = name }
        }
        return session
    }
}

private extension Date {
    static var formattedSessionTitle: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: .now)
    }
}
