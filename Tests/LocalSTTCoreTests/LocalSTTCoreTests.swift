import Foundation
import XCTest
@testable import LocalSTTCore

final class LocalSTTCoreTests: XCTestCase {
    func testNoiseGateSuppressesSilenceAndOpensForSpeech() {
        var gate = NoiseGate(configuration: .init(thresholdDB: -30, attackMilliseconds: 1, holdMilliseconds: 0, releaseMilliseconds: 1))
        let quiet = gate.process([Float](repeating: 0.001, count: 160), sampleRate: 16_000)
        XCTAssertFalse(gate.isOpen)
        XCTAssertLessThan(quiet.max()!, 0.001)
        _ = gate.process([Float](repeating: 0.1, count: 160), sampleRate: 16_000)
        XCTAssertTrue(gate.isOpen)
    }

    func testExtractsOnlyExplicitIntroductions() {
        XCTAssertEqual(SpokenNameExtractor.extract(from: "大家好，我是王小明"), "王小明")
        XCTAssertEqual(SpokenNameExtractor.extract(from: "My name is Dennis"), "Dennis")
        XCTAssertNil(SpokenNameExtractor.extract(from: "王小明今天請假"))
    }

    func testAssignsTurnByLargestOverlap() {
        let segment = TranscriptSegment(start: 1, end: 3, rawText: "測試")
        let turns = [SpeakerTurn(start: 0, end: 1.2, speakerID: "A"), SpeakerTurn(start: 1.2, end: 4, speakerID: "B")]
        XCTAssertEqual(TurnReconciler.assign([segment], to: turns)[0].speakerID, "B")
    }

    func testRendersValidSRT() {
        let value = SRTExporter.render([TranscriptSegment(start: 1.234, end: 62.5, rawText: "你好", speakerID: "Dennis")])
        XCTAssertTrue(value.contains("00:00:01,234 --> 00:01:02,500"))
        XCTAssertTrue(value.contains("[Dennis] 你好"))
    }

    func testSpeakerMatchingRequiresThresholdAndMargin() {
        XCTAssertEqual(SpeakerMatcher.cosineSimilarity([1, 0], [1, 0])!, 1, accuracy: 0.0001)
        XCTAssertTrue(SpeakerMatcher.accepted(best: 0.9, runnerUp: 0.7))
        XCTAssertFalse(SpeakerMatcher.accepted(best: 0.9, runnerUp: 0.86))
        XCTAssertFalse(SpeakerMatcher.accepted(best: 0.7, runnerUp: nil))
    }

    func testSessionStoreRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SessionStore(root: root)
        let session = RecordingSession(title: "Test", audioFilename: "audio.wav", inputDevice: .init(id: "1", name: "Mic"))
        try await store.save(session)
        let loaded = try await store.loadSessions()
        XCTAssertEqual(loaded, [session])
    }
}
