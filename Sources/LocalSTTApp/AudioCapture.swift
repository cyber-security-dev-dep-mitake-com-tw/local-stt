import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import LocalSTTCore

final class AudioCapture: @unchecked Sendable {
    var onLevel: (@Sendable (Float, Bool) -> Void)?
    var onGatedSamples: (@Sendable ([Float]) -> Void)?

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var gate = NoiseGate()
    private let processingQueue = DispatchQueue(label: "LocalSTT.audio-processing")
    private(set) var startedAt: Date?

    static func devices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            return AudioInputDevice(id: String(id), name: stringProperty(id, kAudioObjectPropertyName) ?? "Audio Input \(id)", manufacturer: stringProperty(id, kAudioObjectPropertyManufacturer) ?? "")
        }
    }

    func start(device: AudioInputDevice, outputURL: URL, configuration: NoiseGateConfiguration) throws {
        guard let id = AudioDeviceID(device.id) else { throw EngineError.malformedOutput("Invalid Core Audio device ID") }
        var mutableID = id
        let unit = engine.inputNode.audioUnit!
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &mutableID, UInt32(MemoryLayout.size(ofValue: mutableID)))
        guard status == noErr else { throw EngineError.processFailed("Could not select input device (Core Audio \(status))") }

        let input = engine.inputNode
        let sourceFormat = input.inputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else { throw EngineError.processFailed("Could not create 16 kHz format") }
        converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        outputFile = try AVAudioFile(forWriting: outputURL, settings: targetFormat.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        gate.update(configuration: configuration)

        input.installTap(onBus: 0, bufferSize: 2048, format: sourceFormat) { [weak self] buffer, _ in self?.process(buffer, targetFormat: targetFormat) }
        engine.prepare(); try engine.start(); startedAt = .now
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0); engine.stop()
        processingQueue.sync { outputFile = nil; converter = nil }
        startedAt = nil
    }

    private func process(_ source: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        processingQueue.async { [weak self] in
            guard let self, let converter = self.converter else { return }
            let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 16_000 / source.format.sampleRate)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return source
            }
            guard error == nil, converted.frameLength > 0, let channel = converted.floatChannelData?[0] else { return }
            try? self.outputFile?.write(from: converted)
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            let rms = sqrt(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, samples.count)))
            let level = 20 * log10(max(rms, 0.000_001))
            let gated = self.gate.process(samples, sampleRate: 16_000)
            self.onLevel?(level, self.gate.isOpen); self.onGatedSamples?(gated)
        }
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
        let pointer = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(pointer)
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value as String : nil
    }
}
