# LumaStage 實作規格集（agent-executable specs）

這個資料夾的每一份 spec 都是**一個可獨立分派給 subagent 的任務**,格式刻意統一,讓 agent 拿了就能做、做完能驗:

- **Goal** — 一句話目標 + 對應 MAIC 戰略書的哪一項。
- **Ground truth** — 已存在、要「呼叫/沿用」而非重寫的 API/型別/檔案(附 `file:符號`),以及關鍵 footgun。
- **Work items** — 每項標明**擁有哪一個檔**(file ownership,避免並行 agent 互相覆蓋),與**精確契約**(型別名、方法簽名、entity 命名)。
- **Constraints** — 不可動的檔、平台守衛、風格。
- **Verification** — 確切的 build / smoke 指令與通過條件。
- **Caveats** — 只能實機驗證、或刻意延後的部分。

## 共用慣例（所有 spec 適用）

- **平台/工具**:visionOS 27,RealityKit/SwiftUI,Swift 6(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)。Build 用 Xcode 27:`/Applications/Xcode-beta.app`,經 `DEVELOPER_DIR`。
- **可判定邏輯進 Foundation-only 檔 + smoke test**;SwiftUI/RealityKit view 當薄消費者(專案核心慣例)。
- **使用者字串繁體中文**;FM system prompt / `@Guide` / 解析關鍵字維持英文(見根 `CLAUDE.md`)。
- **設計 token**:`LumaStageDesign`(`lumaFloatingPanel`/`lumaNativeGlass`/`lumaGazeTarget`/`minGazeTarget=60`/tints)。
- **無障礙**:新互動元件一律 `accessibilityLabel`(必要時 hint/value)、≥60pt 注視目標、動畫 gate 在 `@Environment(\.accessibilityReduceMotion)`、非顏色狀態指示(symbol/粗體/checkmark)。
- **Observation footgun**:`RealityView` 的 `update:` closure 不自成 Observation 依賴——任何它要反應的 `@Observable` 狀態,必須在 `body` 以 `let _ = appModel.x` 先讀(見 `ImmersiveView`)。
- **smoke 編譯集(目前)**:
  ```
  swiftc Tests/LumaStageCoreSmokeTests.swift \
    LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
    LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
    LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift LumaStage/LightingPatchSheet.swift \
    LumaStage/LightEffect.swift \
    -o /tmp/smoke && /tmp/smoke    # 印出 "LumaStageCoreSmokeTests passed" 即過
  ```
  新增 Foundation-only 檔時,把它加進這個指令(並更新根 `CLAUDE.md` 的測試段)。
- **完整 build 驗證**:
  ```
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage \
    -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
  ```
  通過條件 `** BUILD SUCCEEDED **`。Multipeer 的 Sendable 警告、以及 MCSession delegate 簽名裡含 `error:` 字樣的行,是既有非錯誤,忽略。
- **並行分派守則**:一個 agent 只擁有一個檔;跨檔依賴用「spec 釘死介面」解決(agent 各自對著契約寫,最後一起編譯整合)。需要同檔多處改時,該檔只給一個 agent。

## 現況基線（已完成,勿重做）

- **S2 多 cue + GO**、**S1 語音指令/朗讀**(`StageVoiceCommand`/`SpeechNarrator`,zh-TW 辨識)、**A2 配接表匯出**(`DMXPatchPlanner`/`LightingPatchSheet`/`PatchSheetExportView`)、**A1 動態效果引擎**(`LightEffect`/`LightEffectEngine`/`LightEffectPlan` + `LightEffectComponent`/`LightEffectSystem`,目前為「依燈具型號×cue 能量」的確定性效果)、**頭顯內就地手動控燈**(`AppModel` 選取+override 方法、`SelectedLightControlView`、`ImmersiveView` 的 `lightpick_<n>`+選取環+attachment)——**都已實作、編譯通過、smoke 綠**。
- **SPEC 04 連續調光 / 捏拉調暗**(`SelectedLightControlView` 連續亮度 `Slider`(0...1,綁 `setManualIntensity`,顯示 % + a11y)+ `ImmersiveView` 捏拉 `lightpick_<n>` 上下調光(`.simultaneousGesture(DragGesture)`,`dragIntensityPerPoint` 係數待實機調)+ 手動 override 走 0.12s 短過場(`apply` 的 `manualTransition`,不動 cue 2.5s 預設))——已實作、**完整 build 綠**(spec 已封存至 `archive/`)。

## Spec 生命週期

- 每份 spec **完成後(實作 + build 綠 + smoke 過)就移到 `docs/specs/archive/` 或直接刪除**——完成的 spec 不留在待辦清單裡(完成內容反映在「現況基線」與程式碼/git)。
- 範例:本功能集的「頭顯內就地手動控燈」**原始實作 spec 與其收尾打磨 spec(`00-manual-light-control-polish.md`,review 4 條)皆已完成並刪除**——功能反映在「現況基線」與程式碼/git。
- 一份 spec 開工前,可在檔頭加 `> Status: in-progress / done`;done 即封存。

## 優先序

| 序 | Spec | 對應 | 工作量 | 風險 |
|---|---|---|---|---|
| P1 | `08-group-submasters-and-live-control.md` | 編組+現場控制模型 · 創新/商業前景/Q6 demo | L | 中(解析不變式必測;觸控/實機) |
| P1 | `01-ai-authored-effects.md` | A1 延伸 · 創新 | M | 中(@Generable 實機) |
| P1 | `03-ai-lighting-tutor.md` | B2 · 教育/社會價值 | S | 低 |
| P1 | `06-social-value-and-accessibility.md` | S1 完成 · 社會價值 60% 門檻 | M | 低(多為敘事+a11y sweep) |
| P2 | `02-fixture-type-geometry.md` | B4 · demo 沉浸感 | M | 中(實機觀感) |
| P3 | `05-music-sync.md` | B1 · 依賴 A1 | L | 高(分析準度→降級內建曲) |
| P3 | `07-tabletop-place-lights.md` | C2 · 空間 wow | L | 中 |

> 風險高/實機相依者,先在實機把 A1 + 房間溢光驗過再排(見根 `docs/demo-runbook.md`)。
