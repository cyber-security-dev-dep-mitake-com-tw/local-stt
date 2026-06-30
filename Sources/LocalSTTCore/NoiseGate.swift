import Foundation

public struct NoiseGateConfiguration: Codable, Equatable, Sendable {
    public var thresholdDB: Float
    public var hysteresisDB: Float
    public var attackMilliseconds: Double
    public var holdMilliseconds: Double
    public var releaseMilliseconds: Double
    public var bypass: Bool
    public init(thresholdDB: Float = -45, hysteresisDB: Float = 6, attackMilliseconds: Double = 10, holdMilliseconds: Double = 150, releaseMilliseconds: Double = 250, bypass: Bool = false) {
        self.thresholdDB = thresholdDB; self.hysteresisDB = hysteresisDB
        self.attackMilliseconds = attackMilliseconds; self.holdMilliseconds = holdMilliseconds
        self.releaseMilliseconds = releaseMilliseconds; self.bypass = bypass
    }
}

public struct NoiseGate: Sendable {
    public private(set) var configuration: NoiseGateConfiguration
    public private(set) var isOpen = false
    private var gain: Float = 0
    private var holdFrames = 0

    public init(configuration: NoiseGateConfiguration = .init()) { self.configuration = configuration }

    public mutating func update(configuration: NoiseGateConfiguration) { self.configuration = configuration }

    public mutating func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard !configuration.bypass, !samples.isEmpty else { isOpen = true; return samples }
        let rms = sqrt(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count))
        let db = 20 * log10(max(rms, 0.000_001))
        let openThreshold = configuration.thresholdDB
        let closeThreshold = openThreshold - configuration.hysteresisDB
        if db >= openThreshold {
            isOpen = true
            holdFrames = Int(sampleRate * configuration.holdMilliseconds / 1000)
        } else if isOpen && db < closeThreshold {
            holdFrames -= samples.count
            if holdFrames <= 0 { isOpen = false }
        }
        let timeMS = isOpen ? configuration.attackMilliseconds : configuration.releaseMilliseconds
        let target: Float = isOpen ? 1 : 0
        let coefficient = Float(1 - exp(-Double(samples.count) / max(1, sampleRate * timeMS / 1000)))
        gain += (target - gain) * coefficient
        return samples.map { $0 * gain }
    }

    public static func calibratedThreshold(samples: [Float], marginDB: Float = 10) -> Float {
        guard !samples.isEmpty else { return -45 }
        let rms = sqrt(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count))
        return min(-10, 20 * log10(max(rms, 0.000_001)) + marginDB)
    }
}
