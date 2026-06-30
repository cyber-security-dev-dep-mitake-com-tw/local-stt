# LocalSTT

LocalSTT 是一套針對 Apple Silicon Mac 的本機端繁體中文語音轉文字工具。它可選擇 macOS 的內建麥克風、USB 麥克風或音訊介面，保留原始 WAV 錄音，並在裝置上完成轉錄與臺灣繁體中文轉換。

使用方式請參考 [使用教學](docs/tutorial.md)，開發、編譯、簽署與發佈流程請參考 [安裝、編譯與發佈](docs/install-compile-build-publish.md)。

## 主要功能

- 列出並選擇 Core Audio 輸入裝置。
- 錄製 16 kHz 單聲道 WAV，原始錄音不套用 Noise Gate。
- 可調式 Noise Gate 只作用於即時辨識與後處理。
- 使用 `whisper.cpp` 進行本機中文語音辨識。
- 使用 OpenCC `s2twp` 將結果正規化為臺灣繁體中文。
- 從「我是 Dennis」、「我叫王小明」等明確自我介紹，自動替該說話者命名。
- 儲存工作階段，並匯出 UTF-8 TXT 或 SRT。
- 未安裝模型時，主畫面可直接下載並驗證模型。

## 模型與引擎

| 元件 | 用途 | 目前整合方式 |
| --- | --- | --- |
| `whisper.cpp` / `whisper-cli` | 語音轉文字 | 必要；Homebrew 安裝後由 App 呼叫本機執行檔 |
| `ggml-large-v3-turbo-q5_0.bin` | 多語 Whisper 模型 | 必要；App 下載約 547 MiB 並驗證 SHA-1 |
| OpenCC | 簡體／混合字形轉臺灣繁體 | 建議；若不存在則使用有限的內建字元轉換 |
| sherpa-onnx | 說話者分段與聲紋嵌入 | 選用／實驗性；需自行指定執行檔及 ONNX 模型 |


<img width="719" height="452" alt="Screenshot 2026-06-30 at 5 40 23 PM" src="https://github.com/user-attachments/assets/235ea13f-5677-463b-a763-dd579f168608" />

<img width="916" height="682" alt="Screenshot 2026-06-30 at 5 56 47 PM" src="https://github.com/user-attachments/assets/3701417a-946e-4076-9c94-d2fdf81b87b3" />


Whisper 模型源自 OpenAI 的開源語音辨識研究，但本專案不呼叫 OpenAI API，也不使用 OpenAI、Claude、Ollama 或其他雲端 LLM。模型下載完成後，錄音與辨識可完全離線運作。

若 sherpa-onnx 尚未設定，轉錄仍會正常完成，但所有片段會暫時標示為 `Speaker 1`。明確自我介紹仍可將它改名，例如 `Dennis`。真正的多說話者計數、分段及跨工作階段聲紋辨識，必須先完成 sherpa-onnx 引擎與模型設定。

## 系統需求

- Apple Silicon Mac
- macOS 14 或更新版本
- Xcode 16 或更新版本；已驗證 Xcode 26.6
- Homebrew

安裝本機引擎：

```bash
brew install whisper-cpp opencc
```

驗證專案：

```bash
swift test
```

啟動開發版本：

```bash
swift run LocalSTT
```

或使用 Xcode 開啟 `Package.swift`，選擇 `LocalSTT` scheme 與 `My Mac`，再按 `⌘R`。

## 下載與團隊內部發佈

本專案預設採用 GitHub Actions 建立團隊測試用 DMG，不需要加入 Apple Developer Program，也不需要 Developer ID 憑證。

- 在 GitHub repository 的 **Actions** 頁面執行 **Build team DMG**，完成後從 **Artifacts** 下載 DMG。
- 推送 `v*` tag 會自動建立 GitHub Release，並附上 DMG 與 SHA-256 校驗檔。
- DMG 為 ad-hoc 簽署且未經 Apple 公證，只適合已知且信任此專案的內部團隊使用。

建立版本 Release：

```bash
git tag v0.1.0
git push origin v0.1.0
```

隊友安裝 DMG 前，需先執行：

```bash
brew install whisper-cpp opencc
```

第一次開啟時，請在 Finder 對 LocalSTT 按右鍵選擇「打開」並確認；若仍被阻擋，到「系統設定 → 隱私權與安全性」允許此次執行。完整流程請參考[安裝、編譯與發佈](docs/install-compile-build-publish.md)。

## 隱私與限制

- App 不會上傳錄音、逐字稿或聲紋資料。
- 第一次下載模型時需要網路，之後可離線使用。
- Noise Gate 只能壓低安靜區段，無法移除與人聲重疊的噪音。
- 單一麥克風遇到多人同時說話時，無法保證分離出每個人的文字。
- 目前發佈版本依賴使用者 Mac 上的 Homebrew `whisper-cli` 與 OpenCC；若要提供完全獨立安裝包，需另外內嵌並處理第三方執行檔、模型與授權。
- 團隊 DMG 未使用 Developer ID 且未經 Apple 公證，因此不適合公開散佈給不熟悉專案來源的一般使用者。

## 授權

本專案採用 MIT License。發佈 App 時仍須分別遵守 whisper.cpp、Whisper 模型、OpenCC、sherpa-onnx 及其模型的授權與標示要求。
