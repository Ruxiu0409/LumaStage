# SPEC 14 — 分段裝置端生成（staged generation：讓 on-device FM 生成更大的 rig / 更長的秀而不爆 context window）

**Goal**：SPEC 11 是「在**單次**呼叫內把輸出砍小」到 4–6 fixtures / 2–3 cues 才不爆 4096-token 視窗。本 spec 改用**分段生成**：把「一次生一整套秀」拆成多次 model 呼叫，每次輸出都**有界**（Pass 1 只出 rig 骨架；每個 cue 各一次呼叫、輸出量只隨 fixture 數 N，不隨 cue 數 M 疊加），於是端側可生成**更大的 rig（4–12 盞）與更長的秀（2–6 cues）**而不觸 `contextSizeExceeded`。對應「拿掉 `.count` 硬上限但不撞視窗」的需求——不是移除護欄，而是把單次輸出的天花板換成「每段各自在預算內」。**可判定的組裝/容錯邏輯進 Foundation-only 檔（smoke 測）**，`FoundationModelsLightingService.swift` 只當薄編排層。

## Ground truth（已存在,沿用,勿改）

- **視窗**：on-device FM 固定 ~4096 tokens（輸入+輸出共用、輸出主導）；OS 27 有 `SystemLanguageModel.contextSize` 與 `model.tokenCount(for:)`（visionOS 26.4+，可量 `Prompt`/`Instructions`/schema/transcript）。團隊**已**設 `includeSchemaInPrompt: false`。（見 `fm-context-window-budget` / SPEC 11。）
- **為何分段有效**：目前單次輸出 ≈ 固定開銷 + `fixtures × cues` 組 state（每組 `enabled`+`intensity`+`colorHex`）。`N×M` 是主成本。分段後：Pass 1 輸出 ≈ N 個 `{name,type,zone}`（無 state）；每個 cue 一次呼叫、輸出 ≈ N 組 state。**單次輸出上限 ≈ N，與 M 脫鉤** → M 變大只是多幾次呼叫，不加大任何單次輸出。
- **組裝/驗證閘（沿用,勿改內部）**：`LightingLookDraft.makeValidatedLook(lookName:mood:cues:explanation…)`（`LumaStage/LightingAIService.swift`）吃 `[LightingLookDraft.Cue]`（`Cue = {id,name,fixtures:[Fixture]}`；`Fixture = {id,name,role,zone,enabled,intensity,colorHex,gobo?=nil,model?=nil,beamAngleDegrees?=nil,effect?=nil}`），內部一律跑 `LightingLook.validate()`。本 spec 的新 staged 組裝器**建 draft cues 後就呼叫它**，不重寫驗證。
- **可重用型別/映射**：`@Generable GeneratedFixtureState { enabled; intensity; colorHex }`、`GeneratedFixtureType`（10 型）、`GeneratedZone`（5 區）及其 `.visualModel` / `.stageZone`、`LightingFixtureVisualModel.derivedRole`、`FixtureColor.normalizedHex(_:) ?? "#FFFFFF"` 自癒——**全部沿用**。
- **`validate()` 不設 fixture/cue 數量下限**（見 `dynamic-rig-architecture` 記憶）；`makeValidatedLook` 對 count drift 已容錯。新 `.count` 上限 4–12 / 2–6 對齊 `AppModel.maxRigFixtureCount = 12` 與音樂秀（最多 6 cue）。
- **架構慣例**：可判定邏輯進 Foundation-only 檔 + smoke test；`FoundationModelsLightingService.swift` **不在** smoke 編譯集（import FoundationModels）→ 只能靠完整 build 驗，故新邏輯**不要**埋在該檔。

## Work items（精確契約）

### WI-1 · Foundation-only staged 組裝器（owner：`LumaStage/LightingAIService.swift`，本檔在 smoke 集）

在 `LightingLookDraft` 上新增純值型別與一支靜態組裝器（Foundation-only、無 FoundationModels）：

```swift
extension LightingLookDraft {
    /// Rig 骨架中的一盞燈（無 per-cue state）。id 由組裝器指派、跨所有 cue 共用（rig identity）。
    struct RigFixture: Equatable {
        var id: String
        var name: String
        var role: FixtureRole
        var zone: StageZone
        var model: LightingFixtureVisualModel?   // nil → renderModel 由 role/zone 衍生（沿用既有 fallback）
    }

    /// 一盞燈在單一 cue 的狀態（對應 GeneratedFixtureState，但 Foundation-only）。
    struct StagedState: Equatable {
        var enabled: Bool
        var intensity: Double
        var colorHex: String
    }

    /// 由「定義一次的 rig」+「逐 cue 的 state 列」組出並驗證一個 LightingLook。
    /// - `cueNames[c]`：第 c 個 cue 的顯示名（空/全空白 → "Cue \(c+1)"）。
    /// - `cueStates[c]`：第 c 個 cue 的 state 列，**列索引 j 對應 rig[j]**。
    /// 容錯（比照既有 makeValidatedLook 的 count 容錯）：
    ///   * 某列比 rig 短 → 缺的 fixture **重用該列最後一筆**；列為空 → 該 cue 全部 enabled=false（off）。
    ///   * 某列比 rig 長 → 忽略多出來的。
    ///   * `cueStates` 比 `cueNames` 短 → 缺的 cue 視為空列（全 off）；長 → 忽略多出來的。
    /// cue id 固定 "cue_0"、"cue_1"…；fixture id 取自 rig（rig identity）。colorHex 一律
    /// `FixtureColor.normalizedHex(...) ?? "#FFFFFF"` 自癒。最後呼叫既有
    /// makeValidatedLook(lookName:mood:cues:explanation…)（會跑 validate()）。
    static func makeValidatedStagedLook(
        lookName: String,
        mood: String,
        rig: [RigFixture],
        cueNames: [String],
        cueStates: [[StagedState]],
        explanationTerm: String,
        explanationPlainText: String,
        explanationActionSummary: String,
        explanationRationale: String
    ) throws -> LightingLook
}
```

- 至少要有 **1 個 cue、1 盞燈**才呼叫（`rig` 空或 `cueNames` 空時：`rig` 空丟一個既有 `ValidationError`/或組一盞 off 的 safety fixture 由呼叫端保證非空——實作端**保證產出能過 `validate()`**，degenerate 輸入不得 crash）。
- 每盞 `LightingLookDraft.Fixture` 用 `rig[j]` 的 `id/name/role/zone/model` + 該 cue 該列的 `enabled/intensity/colorHex`（`gobo/beamAngleDegrees/effect` 留 nil，吃既有 fallback，同 SPEC 11）。

### WI-2 · 分段編排（owner：`LumaStage/FoundationModelsLightingService.swift`）

把 `generateLook(from:)` 改為**兩階段**（保留：`.permissiveContentTransformations`、可用性 gate、`emptyPrompt` 守衛、`includeSchemaInPrompt: false`、取樣 `GenerationOptions(samplingMode:.random(probabilityThreshold:0.9),temperature:0.9)`、`describe(generationError:)` 錯誤映射、`source == .foundationModels`）：

**Pass 1 — rig plan（一次呼叫，小輸出）**。新 `@Generable`：
```swift
@Generable struct GeneratedRigPlan {
    @Guide(...) var lookName: String
    @Guide(...) var mood: String
    @Guide("The ordered cue list — 2 to 6 cues telling an arc (Opening → … → Finale)", .count(2...6))
    var cues: [GeneratedCueLabel]
    @Guide("The whole rig: 4 to 12 fixtures, a mix of types/zones suiting the request", .count(4...12))
    var fixtures: [GeneratedRigFixture]
    @Guide(...) var explanation: GeneratedExplanation   // 沿用既有 GeneratedExplanation
    @Generable struct GeneratedCueLabel { @Guide(...) var name: String }
    @Generable struct GeneratedRigFixture {
        @Guide(...) var name: String
        @Guide("Fixture type") var type: GeneratedFixtureType   // 沿用既有 enum
        @Guide("Where it is mounted") var zone: GeneratedZone   // 沿用既有 enum
    }
}
```

**Pass 2..(M+1) — 逐 cue state（每個 cue 一次呼叫，fresh session）**。新 `@Generable`：
```swift
@Generable struct GeneratedCueDesign {
    @Guide("One state per fixture, IN THE LISTED FIXTURE ORDER. Provide exactly one per fixture.", .count(1...12))
    var states: [GeneratedFixtureState]   // 沿用既有 GeneratedFixtureState
}
```
- **每個 cue 開 fresh `LanguageModelSession`**（避免 transcript 累積回到 context 壓力），prompt 由 `Self.cueDesignPrompt(request:rig:cueNames:cueIndex:)` 組出**精簡英文**字串：原始需求 + rig 清單（`1. Front Fresnel L (front of house); 2. Moving Head (upstage truss); …`，用型號/區的可讀名）+ 完整 cue arc（`Cues: 1 Opening, 2 Build, 3 Finale`）+ `Now design cue \(i+1) "\(name)": give one state per fixture, in order.`。**指令**（cue-design instructions，短、英文）：說明「rig 已固定，只為此 cue 設每盞燈的 enabled/intensity/colorHex；暖前光 vs 冷/彩背景形成對比；某些燈在某些 cue 可關」。
- **rig plan instructions**（Pass 1，短、英文）：設計 rig（型號/區的組合）+ cue arc 名稱 + 一句教學 explanation；**不**產顏色/強度。
- 組裝：`plan.fixtures` → `[LightingLookDraft.RigFixture]`（id `"fixture_\(j)"`、`model = type.visualModel`、`role = model.derivedRole`、`zone = zone.stageZone`）；每個 `GeneratedCueDesign.states` → `[LightingLookDraft.StagedState]`；連同 `plan.cues.map(\.name)` 與 `plan.explanation.*` 丟給 **WI-1 的 `makeValidatedStagedLook`** → 回 `LightingGenerationResult(look:, source:.foundationModels)`。
- **順序執行**（sequential）：`1 + M` 次呼叫，逐一 `await`（天生可被 Task 取消）。任一階段丟錯 → 照既有 `catch` 走 `describe(generationError:)`（含 `contextSizeExceeded`）。
- **移除**舊的單體 `@Generable GeneratedLightingLook` + 其 `makeValidatedLook()` / `draftFixture(index:cueIndex:)` **只有在確定無其他引用時**才刪；若 `LightingLookDraft.RenderableCue`/templates/mvpDemo 等未引用它，安全移除。若不確定，保留為 dead code 並在回報註明（優先不破壞編譯）。
- 保留/更新 `#if DEBUG` 的 `contextSize` + `tokenCount` 診斷：Pass 1 送出前印一次即可。

### WI-3 · smoke tests（owner：`Tests/LumaStageCoreSmokeTests.swift`，於 `main()` 註冊）

新增並在 `main()` 註冊（無自動探索）：
- `stagedAssemblyReconcilesStateCounts`：rig N=3、cueStates 含「短列（重用最後一筆）/長列（忽略多的）/空列（全 off）」→ 每個 cue 都產 3 盞、`validate()` 通過、off 列亮度為 0/enabled false。
- `stagedAssemblyPreservesRigIdentityAcrossCues`：同一組 rig、多 cue → 每個 cue 的 fixture `id` 與順序完全一致（`fixture_0…`），cue id 為 `cue_0…`，`selectedCueId` 解析成功。

## Constraints / 並行

- 檔案擁有權：WI-1→`LightingAIService.swift`、WI-2→`FoundationModelsLightingService.swift`、WI-3→`Tests/LumaStageCoreSmokeTests.swift`。三檔可由**單一 agent 依序**完成（WI-2 依賴 WI-1 的簽名，已在上方釘死）。
- **不動**：`LightingModels.swift`、`LightEffect.swift`、`AppModel.swift`、`OpenAILightingService.swift`（雲端保留完整逐 cue schema，本 spec 不碰）、`MusicShowBuilder.swift`。
- **不改** `makeValidatedLook(cues:)` 既有內部、`validate()`、取樣/可用性/錯誤映射、`includeSchemaInPrompt: false`。
- FM system prompt / `@Guide` / instructions 維持**英文**；使用者字串繁中（本 spec 無新使用者字串）。
- 新 Foundation-only 型別已在既有 smoke 檔（`LightingAIService.swift`）內，**不需**改 smoke 編譯指令。

## Verification

- smoke：既有編譯集照跑 → **`LumaStageCoreSmokeTests passed`**（含 2 條新測試，不得回歸）。
- 完整 build（Xcode 27，visionOS 27 模擬器目的地，`DEVELOPER_DIR=/Applications/Xcode-beta.app/...`）→ **`** BUILD SUCCEEDED **`**（FM 檔不在 smoke 集，靠此驗）。

## Caveats（需實機驗 / 取捨）

- **延遲**：`1 + M` 次序列端側生成（M 最多 6 → 最多 7 次），比單次慢。若太慢，逐 cue 呼叫在「已知 rig+arc」下彼此獨立，可改**併發**——但 on-device model 是共享資源，併發可能被序列化或互搶，需實機量測後再決定（先出序列版）。UI 端在多段期間應維持 `.interpreting`/`.applying` 狀態並可取消。
- **每段輸入成本**：逐 cue prompt 會重述 rig（≤12 行）→ 輸入端變大但仍遠小於「累積 transcript」；已刻意選 fresh session 換取每段有界。
- **一致性**：逐 cue 獨立生成，cue 之間的「漸強敘事」靠 prompt 帶入完整 arc + cue 序號引導；若實機發現各 cue 顏色跳動不連貫，折衷是在 cue i 的 prompt 附上 cue i-1 的一行摘要（會小幅增加輸入，另評估）。
- **實機才準**：模擬器 FM 不可靠（見 `fm-permissive-guardrails`）。真正「4–12 盞 × 2–6 cue 不爆且觀感佳」須在實體 Vision Pro 驗；不夠可回收上限或改 WI-1 的 padding 策略。
- **雲端/音樂路徑不受影響**：`OpenAILightingService`（context 大）仍走完整逐 cue schema；`MusicShowBuilder` 確定性、零 token 成本，本來就能產大 rig。
