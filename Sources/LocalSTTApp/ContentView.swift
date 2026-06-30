import AppKit
import LocalSTTCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSession) {
                Section("Sessions") {
                    ForEach(model.sessions) { session in
                        VStack(alignment: .leading) {
                            Text(session.title)
                            Text("\(session.speakerCount) speakers · \(session.duration.formattedDuration)").font(.caption).foregroundStyle(.secondary)
                        }.tag(session)
                        .contextMenu { Button("Delete", role: .destructive) { Task { await model.delete(session) } } }
                    }
                }
            }.navigationTitle("LocalSTT")
        } detail: {
            VStack(spacing: 0) {
                recordingBar
                Divider()
                if model.isRecording { transcript(model.liveSegments, provisional: true) }
                else if let session = model.selectedSession { sessionView(session) }
                else { ContentUnavailableView("No Recording Selected", systemImage: "waveform", description: Text("Choose an input and start recording.")) }
                Divider()
                HStack { Circle().fill(model.gateOpen ? .green : .gray).frame(width: 8); Text(model.status).font(.caption); Spacer() }.padding(10)
            }
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 14) {
            Picker("Input", selection: $model.selectedDeviceID) {
                ForEach(model.devices) { Text($0.name).tag($0.id) }
            }.frame(maxWidth: 330)
            LevelMeter(levelDB: model.inputLevel, thresholdDB: model.gateConfiguration.thresholdDB)
            HStack(spacing: 6) {
                Image(systemName: "waveform.badge.minus").help("Noise gate threshold")
                Slider(value: $model.gateConfiguration.thresholdDB, in: -70 ... -10, step: 1)
                    .frame(width: 120)
                Text("\(Int(model.gateConfiguration.thresholdDB)) dB")
                    .font(.caption.monospacedDigit()).frame(width: 48, alignment: .trailing)
            }.help("Raise the threshold to suppress more background noise; lower it for quiet voices")
            if let progress = model.modelDownloadProgress {
                ProgressView(value: progress).frame(width: 120)
                Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            } else if !model.isTranscriptionReady {
                Button("Download Model", systemImage: "arrow.down.circle") { Task { await model.installWhisperModel() } }.buttonStyle(.borderedProminent)
            } else if model.isRecording {
                Button("Stop", systemImage: "stop.fill") { Task { await model.stop() } }.buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button("Record", systemImage: "record.circle") { Task { await model.start() } }.buttonStyle(.borderedProminent).disabled(model.isProcessing)
            }
            if model.isProcessing { ProgressView().controlSize(.small) }
        }.padding()
    }

    private func sessionView(_ session: RecordingSession) -> some View {
        VStack(spacing: 0) {
            if !model.nameProposals.isEmpty {
                ForEach(model.nameProposals) { proposal in
                    HStack {
                        Image(systemName: "person.wave.2")
                        Text("Did \(proposal.speakerID) introduce themselves as \(proposal.name)?")
                        Spacer()
                        Button("No") { model.dismiss(proposal) }
                        Button("Confirm") { Task { await model.confirm(proposal) } }.buttonStyle(.borderedProminent)
                    }.padding(10).background(.blue.opacity(0.08))
                }
            }
            HStack {
                VStack(alignment: .leading) { Text(session.title).font(.title2); Text("\(session.speakerCount) detected speakers").foregroundStyle(.secondary) }
                Spacer()
                Button("TXT") { export(session, type: "txt") }
                Button("SRT") { export(session, type: "srt") }
            }.padding()
            transcript(session.segments, provisional: false)
        }
    }

    private func transcript(_ segments: [TranscriptSegment], provisional: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if provisional { Text("Live captions are provisional; speaker attribution is finalized after stopping.").font(.caption).foregroundStyle(.secondary) }
                ForEach(segments) { segment in
                    HStack(alignment: .top) {
                        Text(segment.start.formattedDuration).monospacedDigit().foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                        Text(segment.speakerID).fontWeight(.semibold).frame(width: 100, alignment: .leading)
                        Text(segment.traditionalText).textSelection(.enabled)
                    }.opacity(segment.isProvisional ? 0.7 : 1)
                }
            }.padding()
        }
    }

    private func export(_ session: RecordingSession, type: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(session.title).\(type)"; panel.allowedContentTypes = type == "srt" ? [.init(filenameExtension: "srt")!] : [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { if type == "srt" { try model.exportSRT(session, to: url) } else { try model.exportTXT(session, to: url) } }
        catch { NSAlert(error: error).runModal() }
    }
}

private struct LevelMeter: View {
    let levelDB: Float, thresholdDB: Float
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(levelDB >= thresholdDB ? .green : .blue).frame(width: geometry.size.width * CGFloat(max(0, min(1, (levelDB + 60) / 60))))
                Rectangle().fill(.orange).frame(width: 2).offset(x: geometry.size.width * CGFloat(max(0, min(1, (thresholdDB + 60) / 60))))
            }
        }.frame(width: 130, height: 8).help("Input level; orange marker is the noise gate threshold")
    }
}

private extension TimeInterval {
    var formattedDuration: String { String(format: "%02d:%02d", Int(self) / 60, Int(self) % 60) }
}
