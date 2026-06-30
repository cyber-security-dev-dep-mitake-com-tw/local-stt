import Foundation

public enum SRTExporter {
    public static func render(_ segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, segment in
            "\(index + 1)\n\(timestamp(segment.start)) --> \(timestamp(segment.end))\n[\(segment.speakerID)] \(segment.traditionalText.trimmingCharacters(in: .whitespacesAndNewlines))"
        }.joined(separator: "\n\n") + (segments.isEmpty ? "" : "\n")
    }

    private static func timestamp(_ value: TimeInterval) -> String {
        let ms = max(0, Int((value * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}

public enum SpokenNameExtractor {
    private static let patterns = [
        #"(?:大家好[，, ]*)?(?:我是|我叫|我的名字是)\s*([\p{Han}·・]{1,8})(?=[，,。.!！?？\s]|$)"#,
        #"(?i)(?:my name is|i am|i'm)\s+([A-Za-z][A-Za-z'-]{0,31})(?=[,.!！?？\s]|$)"#
    ]

    public static func extract(from text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return nil
    }
}

public enum TurnReconciler {
    public static func assign(_ segments: [TranscriptSegment], to turns: [SpeakerTurn]) -> [TranscriptSegment] {
        segments.map { segment in
            var result = segment
            let best = turns.max { overlap($0, segment) < overlap($1, segment) }
            if let best, overlap(best, segment) > 0 { result.speakerID = best.speakerID }
            return result
        }
    }
    private static func overlap(_ turn: SpeakerTurn, _ segment: TranscriptSegment) -> TimeInterval {
        max(0, min(turn.end, segment.end) - max(turn.start, segment.start))
    }
}

public enum SpeakerMatcher {
    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot: Float = 0, leftNorm: Float = 0, rightNorm: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            leftNorm += lhs[index] * lhs[index]
            rightNorm += rhs[index] * rhs[index]
        }
        guard leftNorm > 0, rightNorm > 0 else { return nil }
        return dot / (sqrt(leftNorm) * sqrt(rightNorm))
    }

    public static func accepted(best: Float, runnerUp: Float?, threshold: Float = 0.75, margin: Float = 0.08) -> Bool {
        best >= threshold && best - (runnerUp ?? -1) >= margin
    }
}
