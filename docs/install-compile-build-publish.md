# LocalSTT 安裝、編譯、建置與發佈

本文件供開發者使用。所有命令都應在專案根目錄執行。

## 1. 安裝開發環境

### 安裝 Xcode

開啟 Mac App Store 的 Xcode 頁面：

```bash
open "macappstore://itunes.apple.com/app/id497799835"
```

安裝完成後：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
swift --version
```

### 安裝本機語音工具

```bash
brew install whisper-cpp opencc
command -v whisper-cli
command -v opencc
```

Apple Silicon Homebrew 通常會安裝到 `/opt/homebrew/bin`。App 啟動時會自動偵測這兩個預設路徑。

## 2. 取得與驗證原始碼

```bash
git clone <YOUR_REPOSITORY_URL> local-stt
cd local-stt
swift package resolve
swift test
```

成功時應看到六個測試全部通過。若剛切換 Xcode 版本後遇到「compiled module was created by a different version」，執行：

```bash
swift package clean
swift test
```

## 3. 開發模式執行

Terminal：

```bash
swift run LocalSTT
```

Xcode：

```bash
open -a Xcode Package.swift
```

在 Xcode 頂端 scheme 選單選擇 **LocalSTT**，不是 `LocalSTT-Package` 或 `LocalSTTCore`；Destination 選 **My Mac**，再按 `⌘R`。

麥克風權限文字與 entitlement 位於：

- `Config/LocalSTT.xcconfig`
- `Config/LocalSTT.entitlements`

若 Xcode 的 Swift Package scheme 沒有套用 Base Configuration，請在正式 App target 中複製以下設定：

- `NSMicrophoneUsageDescription`
- `com.apple.security.device.audio-input = true`
- Hardened Runtime

目前 App Sandbox 設為關閉，因為 App 需要執行 Homebrew 安裝的外部工具。若未來把所有引擎內嵌到 App bundle，應重新評估並啟用 Sandbox。

## 4. Debug 與 Release 編譯

Debug：

```bash
swift build --product LocalSTT
```

Release：

```bash
swift build -c release --product LocalSTT
```

Release 執行檔位於：

```text
.build/release/LocalSTT
```

執行完整檢查：

```bash
swift test
swift build -c release --product LocalSTT
git diff --check
```

## 5. 建立可發佈的 `.app`

目前專案是 Swift Package executable，而不是傳統 `.xcodeproj` Application target。以下流程可建立基本 App bundle。正式長期發佈建議建立 macOS App target，將 `LocalSTTCore` 作為 dependency，以便由 Xcode 管理版本、資產、簽署與 Archive。

先設定版本與 Bundle ID：

```bash
export APP_NAME=LocalSTT
export BUNDLE_ID=com.example.localstt
export VERSION=1.0.0
export BUILD_NUMBER=1
```

建立 bundle：

```bash
swift build -c release --product LocalSTT
mkdir -p "dist/$APP_NAME.app/Contents/MacOS"
mkdir -p "dist/$APP_NAME.app/Contents/Resources"
cp ".build/release/LocalSTT" "dist/$APP_NAME.app/Contents/MacOS/LocalSTT"
```

建立 `dist/LocalSTT.app/Contents/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
  <key>CFBundleExecutable</key><string>LocalSTT</string>
  <key>CFBundleIdentifier</key><string>com.example.localstt</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>LocalSTT</string>
  <key>CFBundleDisplayName</key><string>LocalSTT</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>LocalSTT 需要麥克風權限，才能在本機錄音並轉為文字。</string>
</dict>
</plist>
```

先用 ad-hoc 簽署測試：

```bash
codesign --force --deep --sign - --entitlements Config/LocalSTT.entitlements "dist/LocalSTT.app"
codesign --verify --deep --strict --verbose=2 "dist/LocalSTT.app"
open "dist/LocalSTT.app"
```

## 6. Developer ID 簽署與公證

需要付費 Apple Developer Program 帳號，以及 Keychain 中有效的 `Developer ID Application` 憑證。

查看身分：

```bash
security find-identity -v -p codesigning
```

設定實際身分並簽署：

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
codesign --force --deep --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" \
  --entitlements Config/LocalSTT.entitlements \
  "dist/LocalSTT.app"
codesign --verify --deep --strict --verbose=2 "dist/LocalSTT.app"
spctl --assess --type execute --verbose=4 "dist/LocalSTT.app"
```

建立公證用 ZIP：

```bash
ditto -c -k --keepParent "dist/LocalSTT.app" "dist/LocalSTT-notarize.zip"
```

第一次先儲存公證憑證：

```bash
xcrun notarytool store-credentials LocalSTT-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

送出並等待結果：

```bash
xcrun notarytool submit "dist/LocalSTT-notarize.zip" \
  --keychain-profile LocalSTT-notary \
  --wait
xcrun stapler staple "dist/LocalSTT.app"
xcrun stapler validate "dist/LocalSTT.app"
```

最後建立給使用者下載的 ZIP：

```bash
ditto -c -k --keepParent "dist/LocalSTT.app" "dist/LocalSTT-$VERSION-macOS.zip"
shasum -a 256 "dist/LocalSTT-$VERSION-macOS.zip"
```

## 7. 發佈前檢查清單

- 在乾淨的 Apple Silicon Mac 測試安裝、首次啟動與麥克風權限。
- 測試內建麥克風、USB 麥克風及至少一款音訊介面。
- 確認模型下載、SHA-1 驗證及離線轉錄。
- 確認 Noise Gate 不會修改儲存的原始 WAV。
- 確認 TXT 與 SRT 匯出為 UTF-8，時間碼正確。
- 確認明確自我介紹能正確替說話者命名。
- 確認沒有 sherpa-onnx 時會退回 `Speaker 1`，而不會讓整次轉錄失敗。
- 使用 `codesign`、`spctl` 與 `stapler` 驗證發佈檔。
- 在 About／Licenses 畫面及發佈頁列出所有第三方授權。

## 8. 目前發佈限制

這個版本仍從 `/opt/homebrew/bin` 呼叫 `whisper-cli` 與 OpenCC，因此接收 ZIP 的使用者也必須先安裝 Homebrew 套件。若要提供真正的一鍵安裝版本，下一階段應：

1. 將 whisper.cpp 以 XCFramework 或靜態函式庫整合進 App。
2. 將 OpenCC 函式庫與 `s2twp` 字典放入 App Resources。
3. 將已確認授權可再散佈的說話者模型及 runtime 內嵌。
4. 啟用 App Sandbox，改用使用者選取檔案的 security-scoped bookmarks。
5. 建立正式 `.xcodeproj` Application target、App Icon、About／Licenses 與自動化 Archive pipeline。

## 9. GitHub Actions 團隊測試 DMG（不需要 Developer ID）

`.github/workflows/team-dmg.yml` 使用 GitHub 的 Apple Silicon `macos-15` runner，執行測試、Release 編譯、建立 `.app`、ad-hoc 簽署及產生 DMG。此流程不使用 Apple Developer 帳號、憑證或公證。

### 手動執行

1. 將變更 push 到 GitHub。
2. 開啟 repository 的 **Actions**。
3. 選擇 **Build team DMG**。
4. 按 **Run workflow**，輸入版本。
5. 完成後，在該次 workflow 的 **Artifacts** 下載 DMG。

### 用 tag 建立 GitHub Release

```bash
git tag v0.1.0
git push origin v0.1.0
```

workflow 會建立 GitHub Release，附上 DMG 與 SHA-256 檔案。

### 本機建立相同 DMG

```bash
chmod +x scripts/build-team-dmg.sh
VERSION=0.1.0 ./scripts/build-team-dmg.sh
```

輸出：

```text
dist/LocalSTT-0.1.0-team-unsigned.dmg
dist/LocalSTT-0.1.0-team-unsigned.dmg.sha256
```

隊友使用前必須先安裝：

```bash
brew install whisper-cpp opencc
```

這是未公證的內部測試版本。第一次開啟時，在 Finder 對 LocalSTT 按右鍵選擇「打開」並確認；若仍被阻擋，到「系統設定 → 隱私權與安全性」允許此次執行。不要全域停用 Gatekeeper。
