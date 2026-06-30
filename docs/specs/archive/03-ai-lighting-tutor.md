# SPEC 03 — AI 燈光導師（B2）

**Goal**：把目前單一術語的 `explanation` 升級成「**為什麼這樣設計**」的整體講評(為何主光暖、背景冷、對比怎麼建立),呼應「科技賦能教育」的社會價值敘事。低風險、純擴充。

## Ground truth
- `LightingExplanation { term, plainText, actionSummary }` — `LumaStage/LightingModels.swift`。
- `@Generable GeneratedLightingLook.GeneratedExplanation { term, plainText, actionSummary }` — `LumaStage/FoundationModelsLightingService.swift`;由 `makeValidatedLook()` 映射。
- `LightingLookDraft.makeValidatedLook(lookName:mood:cues:explanationTerm:explanationPlainText:explanationActionSummary:)`(static,多 cue 版)+ 兩 cue 版 `makeValidatedLook()` — `LumaStage/LightingAIService.swift`。
- composer 的 `.explaining` 狀態已顯示 `explanation.actionSummary` + `term — plainText`(`VisionAIComposerBox.swift` 的 `feedback`)。

## Work items
### 1. `LightingModels.swift`（owner A）
`LightingExplanation` 加 `var rationale: String = ""`(additive、Codable、back-compat 預設空字串)。所有現有 `LightingExplanation(...)` 建構點(mvpDemo/showcaseDemo/StageState patches/AppModel)用預設值即可,**不需逐一改**(有預設)。

### 2. `LightingAIService.swift`（owner A）
`makeValidatedLook(cues:...)` 與兩 cue 版各加參數 `explanationRationale: String = ""`,塞進 `LightingExplanation(rationale:)`。

### 3. `FoundationModelsLightingService.swift`（owner B）
- `GeneratedExplanation` 加 `@Guide(description: "2–3 sentence design rationale a beginner can learn from: why the front is warm/cool, what the backlight separates, how contrast/mood is built")` 的 `var rationale: String`。
- `makeValidatedLook()` 傳 `explanationRationale: explanation.rationale`。
- `instructions` 末段補:also give a short teaching rationale tying the look's choices to one or two lighting principles。

### 4. `VisionAIComposerBox.swift`（owner C）
在 `.explaining` 回饋下,若 `appModel.lastExplanation.rationale` 非空,多顯示一段「設計理由」(可摺疊或第三行,沿用 glass + textSecondary 樣式 + Dynamic Type + 無障礙 label)。

### 5. `Tests`（owner A）
新 test:draft 帶 rationale → 組裝後 `look.explanation.rationale` 保留;舊 JSON(無 rationale)解為 ""。註冊 `main()`。

## Constraints / 並行
- owner A 先加欄位 + 參數;B/C 對契約寫。不動 AppModel(其 `LightingExplanation(...)` 用預設 rationale)。

## Verification
- smoke → passed(含新 test)。完整 build → SUCCEEDED。

## Caveats
- rationale 的實際品質(是否真在教東西、不過長)需實機看 FM 輸出微調 prompt。
