# OpenAI 燈光生成設定

> （本檔前身為 Apple Foundation Models 設定；visionOS 26 port 已改為 OpenAI 雲端，內容已全面改寫。）

LumaStage 的 AI 燈光生成使用 **OpenAI 雲端 API**，不再使用 Apple 裝置端 Foundation Models。因此需要一支 **OpenAI API 金鑰**與**網路連線**才能生成燈光腳本。

## 需求

- 以支援 **visionOS 26** 的 Xcode 建置（工具鏈 Xcode 26.4；部署目標：visionOS 26 / iOS 26 companion）。
- 一支有效的 **OpenAI API 金鑰**。
- 生成時需要**網路連線**（呼叫 OpenAI 雲端服務）。

## 設定金鑰

1. 在 `ProjectSelectionView`（專案選擇畫面）右上角點齒輪，開啟 `OpenAISettingsView`。
2. 貼上 OpenAI API 金鑰並儲存；也可在此清除已存的金鑰。
3. 金鑰存放於裝置的 Keychain（`OpenAIKeychain`），存取權限為 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（僅本裝置、解鎖後可讀）。

## 使用的模型與 API

- 走 OpenAI **Responses API**，搭配 strict `json_schema` 結構化輸出。
- 使用的 model 為 `gpt-5.5`。
- 實作為 `OpenAILightingService`（Foundation-only：`URLSession` 透過可注入的 `HTTPSend` 介面，金鑰經 `apiKeyProvider` 取得）。

## 可用性行為

- 生成可用性 = Keychain 中存在**非空**的 OpenAI 金鑰。
- 若金鑰未設定或為空，AI 對話框會顯示無法使用的原因，並**停用語音與送出按鈕**，**不會生成燈光**。
- 所有生成失敗一律以繁體中文的 `.generationFailed(<原因>)` 呈現。

> 音樂分析（`MusicUnderstanding`，音樂 → 自動整場演出）與燈光 AI 生成不同：音樂理解仍**完全在裝置端離線**完成，不需要 OpenAI 金鑰或網路。只有**燈光腳本生成**走雲端 OpenAI。

## 模型輸出與驗證

OpenAI 回傳的結構化輸出會映射進 Foundation-only 的 `LightingLookDraft`，再由 `LightingLookDraft.makeValidatedLook()` 組裝成 `LightingLook`，並通過 `LightingLook.validate()` 的所有不變量檢查：

- `schemaVersion == "1.0"`。
- `ambient.preset == standardNight`。
- cue 為**非空的 cue stack**（`cues` 非空，且 `selectedCueId` 指向其中之一；不再強制固定兩個 cue id）。
- `intensity` 介於 `0.0...1.0`。
- 顏色為 RGB hex（`color.mode == rgb`、`#RRGGBB`）。
- 光束角（beam angle）介於 5–120 度。

因此，即使生成內容來自雲端模型，最終套用到舞台的 `LightingLook` 一定通過 `validate()` 的所有不變量檢查。
