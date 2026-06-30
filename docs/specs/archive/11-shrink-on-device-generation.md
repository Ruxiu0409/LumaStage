# SPEC 11 — 壓縮裝置端生成（讓 on-device FM 不爆 context window）

**Goal**：on-device Apple Foundation Model 的 context window 固定 **4096 tokens（輸入+輸出共用）**，目前的 `@Generable GeneratedLightingLook`（最壞 8 fixtures × 4 cues × 6 欄位/state + 無上限教學文字）把它撐爆，丟 `contextSizeExceeded`、連基本提示都跑不起來。本 spec 用「**輕量壓縮**」把**輸出**砍到約 1/3，讓裝置端穩定生成：A 縮短教學文字、B 降 rig/cue 上限、C 砍掉可由 app 確定性推導的 per-state 欄位。**只動一個檔**（`FoundationModelsLightingService.swift`），不改架構、不動任何 Foundation-only 型別。命中「demo 一定要跑得動」。

## Ground truth（已存在,沿用,勿改）
- **4096 token 上限**、輸入+輸出共用；OS 27 新增 `SystemLanguageModel.contextSize` 與 token 量測 API（用於診斷，見 work item 4）。團隊**已**設 `includeSchemaInPrompt: false`（省輸入端），瓶頸在**輸出**。
- `LightingLookDraft.Fixture`（`LumaStage/LightingAIService.swift:94-111`，**Foundation-only,本 spec 不改**）：`gobo`/`model`/`beamAngleDegrees`/`effect` **全部 `= nil` 預設**。`fixtureGroup(from:)`（同檔 214-243）對 nil 的處理已是我們要的 fallback：
  - `gobo == nil` → plain beam（無 gobo）。
  - `beamAngleDegrees == nil` → 套 `FixtureFineControl.default(role:zone:)` 的 role/zone 預設 beam（wash 寬、spot 窄,合理）。
  - `effect == nil` → 渲染端回退 `LightEffectPlan.suggested(...)`（型號×能量的**確定性動態**,SPEC 01 留下的 fallback 路徑,motion 仍會播,只是非 AI 逐 cue 指定）。
- 因此 C 在 draft/domain 側**零改動**：純粹從 @Generable schema 拿掉欄位、draftFixture 停止傳值即可,自動吃上述預設。
- `validate()` **不**對 fixture/cue 數量設下限（見 `dynamic-rig-architecture` 記憶）,`makeValidatedLook(cues:)` 對 count 容錯（少給的 state 重用最後一筆）,所以降上限安全。
- `FoundationModelsLightingService.swift` 不在 smoke 編譯集（import FoundationModels）→ 本檔改動靠**完整 build** 驗,既有 smoke 不得回歸。

## Work items（精確契約 · owner：單一 agent,全在 `FoundationModelsLightingService.swift`）

### A. 縮短教學文字（省無上限自由文字）
`GeneratedExplanation` 的兩個自由文字 `@Guide` 改成要求單句,**不刪欄位**（domain `LightingExplanation`/UI 不變）：
- `rationale`：描述從「2–3 sentence design rationale…」改為 **「ONE short sentence」** 的設計理由。
- `plainText`：改為 **「ONE short beginner-friendly sentence」**。
- `term`/`actionSummary` 不動。

### B. 降 rig / cue / state 上限
- `cues` 的 `.count(2...4)` → **`.count(2...3)`**。
- `fixtures` 的 `.count(4...8)` → **`.count(4...6)`**（保留偶數可選,符合對稱偏好）。
- `GeneratedFixture.states` 的 `.count(2...4)` → **`.count(2...3)`**（與 cue 數對齊）。
- 同步更新這三個欄位的 `@Guide` 文案與 `instructions` 內對應數字（「2 to 4 cues」→「2 to 3」、「4 to 8 fixtures」→「4 to 6」）。

### C. 砍掉可推導的 per-state 欄位（最大省 token）
從 `GeneratedFixtureState` **移除三個欄位**,使其只剩 `enabled` / `intensity` / `colorHex`：
- 移除 `beamAngleDegrees`、`gobo`、`movement` 三個 `@Guide` 欄位。
- 移除 `@Generable enum GeneratedMovement` 與 `private extension … GeneratedMovement.lightEffect(slot:)`（移除欄位後**無其他引用**;若編譯器報未使用即一併刪）。`GeneratedGobo` enum 若移除 gobo 後也無引用,一併刪;`GeneratedFixtureType`/`GeneratedZone` **保留**。
- `draftFixture(index:cueIndex:)`：停止傳 `gobo:`、`beamAngleDegrees:`、`effect:`（讓 `LightingLookDraft.Fixture` 吃 nil 預設,即 Ground truth 的 fallback）。`colorHex` 的 self-heal（`FixtureColor.normalizedHex(...) ?? "#FFFFFF"`）、`enabled`/`intensity` **保留不動**。
- `instructions`：刪掉 movement 那段、gobo 與 beam 的敘述,只留「each state: enabled, intensity 0.0–1.0, an RGB hex…」。

### D.（最佳化、非阻擋）context 量測診斷
若 OS 27 SDK 確有 `SystemLanguageModel.contextSize` 與輸入 token 量測 API（請對著 SDK 確認確切簽名,可能在 model 或 session 上）：在 `generateLook` 送出前 `#if DEBUG` 印出 `contextSize` 與 instructions+prompt 的 token 數,方便日後抓預算。**找不到對應 API 就跳過並在 PR/回報註明**——不得為此卡住或臆造 API。不加任何會阻擋生成的 gate（輸入端本就很小,真正風險在輸出）。

## Constraints / 並行
- **只動 `FoundationModelsLightingService.swift`**。不改 `LightingAIService.swift`、`LightingModels.swift`、`LightEffect.swift`、`AppModel.swift`、任何 Foundation-only 型別或 smoke 測試。
- SPEC 01 的 Foundation-only 動態效果管線（`FixtureGroup.effect`、`LightEffectPlan` 授權優先、`LightingLookDraft.Fixture.effect`）**全部保留**——本 spec 只是讓**裝置端 AI** 不再逐 cue 指定 movement,改吃確定性預設;templates/手動/雲端後端不受影響。
- 不動 `includeSchemaInPrompt: false`、取樣設定、可用性/錯誤處理。

## Verification
- 完整 build（Xcode 27,visionOS 27 模擬器目的地）→ **`** BUILD SUCCEEDED **`**。
- 既有 smoke 編譯集照跑 → **`LumaStageCoreSmokeTests passed`**（不得回歸;本檔不在編譯集,確認 draft 側未被牽動）。

## Caveats（需實機驗 / 取捨）
- **SPEC 01 取捨**：裝置端 AI 不再逐 cue 指定 movement/gobo/beam,改吃確定性 fallback——show 仍有動態（`LightEffectPlan.suggested`）與合理 beam,但「只在副歌掃動」這類精細授權在 on-device 路徑消失。若日後想找回,折衷是把 `movement` 移到 **fixture 層（每盞一個,非每 cue）**,1 欄位×6 盞而非×18 states,另開 spec。雲端後端（context 大）可保留完整逐 cue schema。
- 壓縮後是否真的穩定不爆,以及 4–6 盞/2–3 cue 的觀感,需**實機**（模擬器 FM 不可靠,見 `fm-permissive-guardrails` 記憶）。必要時再降到 `fixtures .count(3...6)` / `cues .count(2...2)`。
- token 預算為估算,實機以 work item D 的量測為準。
