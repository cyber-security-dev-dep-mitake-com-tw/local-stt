import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section("Noise Gate") {
                LabeledContent("Threshold") {
                    HStack { Slider(value: $model.gateConfiguration.thresholdDB, in: -70 ... -10); Text("\(Int(model.gateConfiguration.thresholdDB)) dB").monospacedDigit().frame(width: 55) }
                }
                Toggle("Bypass noise gate", isOn: $model.gateConfiguration.bypass)
                Text("The original recording remains unchanged. The gate affects transcription and speaker analysis only.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Local Engines") {
                PathPicker(title: "whisper-cli", path: $model.engineConfiguration.whisperBinary)
                PathPicker(title: "Whisper model", path: $model.engineConfiguration.whisperModel)
                HStack {
                    Button("Download large-v3-turbo Q5 (547 MiB)") { Task { await model.installWhisperModel() } }
                    if let progress = model.modelDownloadProgress { ProgressView(value: progress).frame(width: 160); Text(progress, format: .percent.precision(.fractionLength(0))) }
                }
                PathPicker(title: "sherpa-onnx", path: $model.engineConfiguration.sherpaBinary)
                PathPicker(title: "Segmentation model", path: $model.engineConfiguration.segmentationModel)
                PathPicker(title: "Speaker embedding model", path: $model.engineConfiguration.embeddingModel)
                PathPicker(title: "OpenCC (optional)", path: $model.engineConfiguration.openCCBinary)
            }
            Text("All engines execute as local child processes. LocalSTT does not upload recordings or transcripts.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).padding()
    }
}

private struct PathPicker: View {
    let title: String
    @Binding var path: String
    var body: some View {
        LabeledContent(title) {
            HStack { TextField("Not configured", text: $path).textFieldStyle(.roundedBorder); Button("Choose…") { choose() } }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}
