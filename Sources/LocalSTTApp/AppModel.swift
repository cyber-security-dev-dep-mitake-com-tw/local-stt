import AVFoundation
import Foundation
import LocalSTTCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
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
    @Published var gateConfiguration = NoiseGateConfiguration()
    @Published var engineConfiguration: EngineConfiguration {
        didSet { if let data = try? JSONEncoder().encode(engineConfiguration) { UserDefaults.standard.set(data, forKey: "engineConfiguration") } }
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
        devices = AudioCapture.devices(); selectedDeviceID = devices.first?.id ?? ""
        do { store = try SessionStore(); sessions = try await store?.loadSessions() ?? [] }
        catch { status = error.localizedDescription }
    }

    func start() async {
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
            async let transcriptResult = engine.transcribe(audioURL: audio)
            async let turnsResult = engine.diarize(audioURL: audio)
            var transcript = try await transcriptResult
            for index in transcript.indices { transcript[index].traditionalText = await engine.convertToTraditional(transcript[index].rawText) }
            let turns = try await turnsResult
            session.segments = TurnReconciler.assign(transcript, to: turns)
            session.speakerCount = Set(turns.map(\.speakerID)).count
            try await store.save(session); sessions = try await store.loadSessions(); selectedSession = session
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
}

private extension Date {
    static var formattedSessionTitle: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: .now)
    }
}
