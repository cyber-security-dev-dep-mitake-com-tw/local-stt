# LocalSTT

A fully local macOS speech-to-text application for Traditional Chinese. It records a selected microphone, preserves original audio, applies an inference-only noise gate, transcribes with `whisper.cpp`, attributes turns with `sherpa-onnx`, and remembers confirmed spoken introductions as encrypted local voice profiles.

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode 16+ (the command-line tools alone can run core tests but cannot package microphone entitlements)
- Local `whisper-cli` and `sherpa-onnx-offline-speaker-diarization` executables
- `ggml-large-v3-turbo-q5_0.bin` and sherpa-onnx diarization/embedding ONNX models
- Optional `opencc` executable for Taiwan phrase conversion; a conservative built-in character converter is used when it is unavailable

No audio, transcript, or voiceprint is sent to a server. Network access is not used by the application.

## Run

1. Open `Package.swift` in Xcode.
2. Select the `LocalSTT` executable scheme and sign it locally.
3. Set the executable target's Base Configuration to `Config/LocalSTT.xcconfig` (or copy its microphone usage and entitlement settings into the target).
4. Build and run. In Settings, choose the local engine binaries and model files.

From Terminal, validate the core with:

```sh
swift test
```

## Privacy and limitations

Voice embeddings are biometric data. Profiles are created only after the user confirms a name inferred from an explicit self-introduction. Profile payloads are encrypted with an application key stored in Keychain. Noise gating suppresses quiet intervals; it does not remove noise overlapping speech. Simultaneous speakers may not yield separable text from a single microphone.
