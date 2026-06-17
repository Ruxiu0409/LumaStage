# Apple Foundation Models 設定

LumaStage 的 AI 燈光生成使用 Apple 裝置端 **Foundation Models**（Apple Intelligence），不再呼叫雲端 OpenAI API，也**不需要 API key**、不需任何網路設定。

## 需求

- 以 **Xcode 27** 建置（部署目標：visionOS 27 / iOS 27）。
- 支援 Apple Intelligence 的裝置或模擬器（visionOS 27 / iOS 27）。
- 在「設定」中啟用 Apple Intelligence。
- 首次使用時，系統可能需要先下載裝置端模型。

## 行為

- 生成完全在裝置上進行：無網路請求、無 API key、無外部相依。
- App 在開啟專案與每次生成前會檢查 `SystemLanguageModel.default.availability`。
- 若 Apple Intelligence 無法使用（裝置不支援、未啟用、模型尚未就緒），AI 對話框會顯示無法使用的原因，並停用語音與送出按鈕，**不會生成燈光**（沒有本機 demo fallback）。

## 模型輸出與驗證

模型透過 `@Generable` 結構化輸出填入受限的 `GeneratedLightingLook`（`FoundationModelsLightingService`），再由 Foundation-only 的 `LightingLookDraft.makeValidatedLook()` 組裝成 `LightingLook`，並通過 `LightingLook.validate()` 的所有不變量檢查：

- 固定兩個 cue：`Opening` 與 `Highlight`（cue id 與名稱由 app 指定，不由模型決定）。
- `ambient.preset == standardNight`。
- `intensity` 介於 `0.0...1.0`。
- 顏色為 RGB hex（`#RRGGBB`）。
- fixture role 限制在 `wash`、`spot`、`frontLight`、`backgroundWash`。

cue 識別固定在 app 端、只有 fixture 內容／look 名稱／mood／explanation 由模型產生，因此生成結果一定能通過 `validate()`。
