import Foundation
import Testing
@testable import LocalSTTCore

@Test func noiseGateSuppressesSilenceAndOpensForSpeech() {
    var gate = NoiseGate(configuration: .init(thresholdDB: -30, attackMilliseconds: 1, holdMilliseconds: 0, releaseMilliseconds: 1))
    let quiet = gate.process([Float](repeating: 0.001, count: 160), sampleRate: 16_000)
    #expect(!gate.isOpen)
    #expect(quiet.max()! < 0.001)
    _ = gate.process([Float](repeating: 0.1, count: 160), sampleRate: 16_000)
    #expect(gate.isOpen)
}

@Test func extractsOnlyExplicitIntroductions() {
    #expect(SpokenNameExtractor.extract(from: "大家好，我是王小明") == "王小明")
    #expect(SpokenNameExtractor.extract(from: "大家好,我是Dennis") == "Dennis")
    #expect(SpokenNameExtractor.extract(from: "My name is Dennis") == "Dennis")
    #expect(SpokenNameExtractor.extract(from: "王小明今天請假") == nil)
}

@Test func assignsTurnByLargestOverlap() {
    let segment = TranscriptSegment(start: 1, end: 3, rawText: "測試")
    let turns = [SpeakerTurn(start: 0, end: 1.2, speakerID: "A"), SpeakerTurn(start: 1.2, end: 4, speakerID: "B")]
    #expect(TurnReconciler.assign([segment], to: turns)[0].speakerID == "B")
}

@Test func rendersValidSRT() {
    let value = SRTExporter.render([TranscriptSegment(start: 1.234, end: 62.5, rawText: "你好", speakerID: "Dennis")])
    #expect(value.contains("00:00:01,234 --> 00:01:02,500"))
    #expect(value.contains("[Dennis] 你好"))
}

@Test func speakerMatchingRequiresThresholdAndMargin() {
    #expect(SpeakerMatcher.cosineSimilarity([1, 0], [1, 0]) == 1)
    #expect(SpeakerMatcher.accepted(best: 0.9, runnerUp: 0.7))
    #expect(!SpeakerMatcher.accepted(best: 0.9, runnerUp: 0.86))
    #expect(!SpeakerMatcher.accepted(best: 0.7, runnerUp: nil))
}

@Test func sessionStoreRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SessionStore(root: root)
    let session = RecordingSession(title: "Test", audioFilename: "audio.wav", inputDevice: .init(id: "1", name: "Mic"))
    try await store.save(session)
    let loaded = try await store.loadSessions()
    #expect(loaded.count == 1)
    #expect(loaded.first?.id == session.id)
    #expect(loaded.first?.title == session.title)
    #expect(loaded.first?.inputDevice == session.inputDevice)
}
