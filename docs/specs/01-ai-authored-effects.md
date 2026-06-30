# SPEC 01 — AI 指定動態效果（A1 延伸）

**Goal**：讓「副歌時讓藍色光束掃動」這類話**直接生效**——AI 在生成時可為每盞燈每個 cue 指定動態效果(掃動/畫圓/頻閃/chase/無),取代目前「依燈具型號×cue 能量」的確定性預設。命中 MAIC 創新軸。引擎與 system 都已備好,本 spec 只接「資料來源」。

## Ground truth（已存在,沿用）
- `LightEffect`(kind/speedHz/sizeDegrees/phase)、`LightEffectEngine.output`、`LightEffectPlan`(`isHighEnergy`/`effects(for:)`/`suggested(for:highEnergy:slot:)`) — `LumaStage/LightEffect.swift`。
- `LightEffectComponent` + `LightEffectSystem`(每幀渲染) — `LumaStage/LightEffectSystem.swift`。**不需改**。
- `ImmersiveView.apply(_:overrides:to:)` 目前用 `LightEffect.suggested(...)` 設每盞燈的 `LightEffectComponent.effect`;`RelightDebugSnapshot.make` 用 `LightEffectPlan.effects(for:)`。
- `@Generable GeneratedLightingLook`(cues `.count(2...5)`、fixtures `.count(4...12)`、每 fixture `states: [GeneratedFixtureState] .count(2...5)`) — `LumaStage/FoundationModelsLightingService.swift`。每個 `GeneratedFixtureState` 有 enabled/intensity/colorHex/beamAngleDegrees/gobo。
- AI→domain:`GeneratedFixture.draftFixture(index:cueIndex:)` → `LightingLookDraft.Fixture` → `LightingLookDraft.fixtureGroup(from:)` → `FixtureGroup`(`LumaStage/LightingAIService.swift`)。

## Work items（精確契約 + 檔案歸屬）

### 1. `LightingModels.swift`（owner A）— `FixtureGroup` 加可選 effect
`var effect: LightEffect? = nil`(additive、Codable、back-compat:舊資料解 nil)。`LightEffect` 已是 `Codable`。

### 2. `LightEffect.swift`（owner A）— 授權優先於預設
`LightEffectPlan.effects(for cue:)` 改為:每盞燈 `fixture.effect ?? LightEffect.suggested(for: fixture.renderModel, highEnergy: isHighEnergy(cue), slot: index)`。(AI 指定 > 型號預設;沒指定就回退到現有確定性行為,**不回歸**。)

### 3. `LightingAIService.swift`（owner A）— draft 帶上 effect
`LightingLookDraft.Fixture` 加 `var effect: LightEffect? = nil`;`fixtureGroup(from:)` 設 `effect: fixture.effect`。

### 4. `FoundationModelsLightingService.swift`（owner B）— @Generable + 映射 + prompt
- 在 `GeneratedFixtureState` 加一個 `@Generable enum GeneratedMovement { case none, sweep, circle, strobe, chase }` 欄位 `movement`(per-cue,讓「只在副歌動」成立)。
- `draftFixture(index:cueIndex:)` 把 `state.movement` 映射成 `LightEffect?`(none→nil;其餘用合理預設速度/幅度,可借 `LightEffect.suggested` 的數值或固定:sweep speed 0.5/size 26、circle 0.4/22、strobe 8、chase 0.7;phase 用 `Double(index)*0.2`)。塞進 `LightingLookDraft.Fixture.effect`。
- `instructions` 補一句:fixtures MAY specify a `movement` per cue for energetic moments (sweep/circle for moving beams, strobe for accents, chase for colour washes); keep most cues still and reserve movement for peaks。

### 5. `ImmersiveView.swift`（owner C）— apply 用共用 Plan
`apply` 內設 `LightEffectComponent.effect` 時,改用 `LightEffectPlan.effects(for: cue)[index]`(與 debug 讀數同源),而非 inline 的 `LightEffect.suggested(...)`。其餘不動。

### 6. `Tests/LumaStageCoreSmokeTests.swift`（owner A）
- 新 test:`LightingLookDraft.makeValidatedLook(cues:)` 帶 `effect` 的 fixture → 組裝後 `FixtureGroup.effect` 保留;Codable round-trip 保 `effect`;舊 JSON(無 effect 欄位)解為 nil。
- 新 test:`LightEffectPlan.effects(for:)` 在 fixture 有 `effect` 時回傳該 effect、無時回退 `suggested`。註冊進 `main()`。

## Constraints / 並行
- **依賴序**:1(FixtureGroup.effect)是 3/4 的前置;owner A(LightingModels+LightEffect+LightingAIService+Tests)先成立型別,owner B(FM)、owner C(ImmersiveView)對著契約寫,最後一起編譯。若單一 agent 做,順序 1→2→3→4→5→6。
- 不動 `LightEffectSystem.swift`、`AppModel.swift`。

## Verification
- smoke(LightEffect.swift 已在編譯集)→ passed,含新 test。
- 完整 build → `** BUILD SUCCEEDED **`。

## Caveats
- 實際 AI 是否在對的時刻指定 movement、以及多盞同時動態的效能,需實機。on-device 生成更長巢狀結構(states + movement)的穩定度也要實機驗,必要時在 `draftFixture` 容錯(未知/缺值→none)。
