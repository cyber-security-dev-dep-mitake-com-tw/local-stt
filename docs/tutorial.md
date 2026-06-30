# LocalSTT 使用教學

本教學說明如何用 LocalSTT 從 Mac 的音訊輸入裝置錄音，並取得繁體中文逐字稿。

## 1. 第一次設定

先確認本機已安裝必要引擎：

```bash
brew install whisper-cpp opencc
```

啟動 LocalSTT 後，主畫面若顯示 **Download Model**，請按下按鈕。App 會下載約 547 MiB 的 `large-v3-turbo Q5` 模型並驗證檔案；完成前不能開始錄音。

需要檢查路徑時，按 `⌘,` 開啟設定：

- `whisper-cli`：Apple Silicon Homebrew 預設為 `/opt/homebrew/bin/whisper-cli`。
- `Whisper model`：由 App 下載後自動填入。
- `OpenCC`：預設為 `/opt/homebrew/bin/opencc`。
- sherpa-onnx 三個欄位可先留白；此時仍可轉錄，但只有單一 `Speaker 1` 標籤。

## 2. 選擇聲音輸入

在主畫面的 **Input** 選單選擇來源，例如：

- MacBook Pro Microphone
- USB Webcam 麥克風
- Scarlett 2i4 USB 等音訊介面
- iPhone Continuity Camera 麥克風

選擇 Scarlett 2i4 等介面時，請先確認麥克風接在正確的實體輸入、Gain 不為零，且訊號沒有削波。主畫面的音量條有變化，才代表 App 收得到聲音。

## 3. 調整 Noise Gate

主畫面音量條旁的滑桿是 Noise Gate 門檻，單位為 dB：

- 往右提高門檻：濾掉更多風扇、冷氣或底噪，也可能漏掉較小聲的人聲。
- 往左降低門檻：保留較小聲的人聲，但也會保留更多背景聲。
- 一般安靜房間可從 `-45 dB` 開始。
- 辦公室可嘗試 `-40 dB`。
- 說話很小聲時可降到 `-55 dB` 左右。

橘色標記代表門檻，綠色表示目前訊號已通過 Noise Gate。Noise Gate 只影響辨識用音訊；儲存的 WAV 永遠保留原始錄音。它無法消除與人聲同時出現的噪音。

設定視窗中可勾選 **Bypass noise gate** 暫時停用 Noise Gate。

## 4. 錄音與轉錄

1. 選好 Input。
2. 按 **Record**。
3. 說話時保持穩定距離，避免麥克風爆音。
4. 錄音超過數秒後，App 會嘗試顯示暫時性的即時字幕。
5. 按 **Stop**。
6. 等待完整錄音重新轉錄、繁體中文轉換及說話者處理完成。

長錄音與大型模型需要較多處理時間。完成前不要強制結束 App。

## 5. 讓 App 使用說話者姓名

每位說話者第一次發言時，請使用明確自我介紹，例如：

- 「大家好，我是 Dennis。」
- 「我叫王小明。」
- 「我的名字是陳美玲。」
- “My name is Alice.”

App 會把同一說話者群組原本的 `Speaker 1`、`Speaker 2` 標籤改為辨識到的姓名。請使用完整句子並稍作停頓，以提高姓名擷取成功率。

沒有設定 sherpa-onnx 時，App 無法可靠區分多人的聲音，整段錄音會先視為同一位 `Speaker 1`。因此多人會議要正確套用不同姓名，必須設定說話者分段及 embedding 模型。

## 6. 查看與匯出

左側 **Sessions** 顯示已儲存的錄音。選取一筆工作階段即可查看：

- 時間戳
- 說話者名稱或編號
- 繁體中文逐字稿
- 偵測到的說話者數量

右上方匯出按鈕：

- **TXT**：每行包含說話者與文字。
- **SRT**：包含時間碼，可用於影片字幕。

在左側工作階段按右鍵可刪除。刪除會一併移除該工作階段的中繼資料與本機 WAV，請先匯出需要保留的內容。

## 7. 常見問題

### 顯示 `Required local file is missing`

按 **Download Model**，並以 `⌘,` 檢查 `whisper-cli` 與模型路徑。也可在 Terminal 驗證：

```bash
command -v whisper-cli
command -v opencc
```

### 音量條沒有變化

確認 macOS「系統設定 → 隱私權與安全性 → 麥克風」允許 LocalSTT 使用麥克風，再檢查選取裝置、實體接線及 Gain。

### 逐字稿仍顯示 `Speaker 1`

單人錄音請先說「我是〈姓名〉」。多人錄音若要分離說話者，需設定 sherpa-onnx；否則這是預期行為。

### 沒有即時文字，但停止後有逐字稿

即時辨識需先累積足夠音訊，而且大型模型在較舊的 Mac 上可能跟不上即時速度。最終轉錄會以完整 WAV 重新處理，應以最終結果為準。
