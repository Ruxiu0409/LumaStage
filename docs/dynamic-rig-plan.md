# 動態燈具系統實作計畫（Dynamic Rig）

> 狀態：**計畫，尚未實作**。這份文件描述把 LumaStage 從「寫死 2 角色 / 4 盞燈」改成「動態可變燈具、AI 生成整場景」的設計與分階段做法。

## 1. 目標

1. **AI 生成整個場景**：高階 prompt（例：「熱舞社成發」）→ AI 設計**整套 rig**（8–12 盞、各種燈具類型、放哪）+ 每個 cue 每盞燈的狀態。
2. **可隨意增減燈具**：使用者能手動 / 語音「在上舞台加兩盞 moving head」「刪掉 Light 5」。
3. 沿用既有的**單燈指令 + 覆寫層**（`LightCommand` / `LightOverride`），從「Light 1–4 固定」自然變成「Light 1…N 動態」。
4. 接上現有並行工作：燈具目錄 9 種 `LightingFixtureVisualModel`、`FixtureSpatialScene` 的 RealityKit 模型、之後的 sync 真實輸出。

### 已定案的決策
- **擺位**：區域化自動擺位（AI 只選 zone + 類型 + 數量，座標由程式依舞台幾何算）。
- **每盞燈屬性（這階段）**：顏色 + 亮度 + 光束角 + gobo（靜態）。pan/tilt 掃動、strobe 閃爍等**動態**留到後續獨立一期。

## 2. 目標資料模型

把「rig（物理配置，跨 cue 一致）」與「cue 狀態（每個 cue 每盞燈做什麼）」分離。

```swift
struct LightingLook {
    var schemaVersion: String
    var intent: LightingIntent
    var lookName: String
    var mood: String
    var ambient: AmbientState
    var selectedCueId: String
    var rig: [FixtureDefinition]      // 新增：這場景有哪些燈（共用）
    var cues: [LightingCue]
    var explanation: LightingExplanation
}

/// 一盞實體燈：類型 + 擺在哪個區域。座標由 RigPlacement 從舞台幾何算，不存死座標。
struct FixtureDefinition: Codable, Equatable, Identifiable {
    var id: String
    var name: String                       // "Moving Head 1"（也用於標籤）
    var model: LightingFixtureVisualModel  // 類型 → 幾何（用你的 FixtureSpatialScene）
    var zone: FixtureZone
    var slot: Int                          // 同一 zone 內的序位（0-based），給均分擺位用
}

enum FixtureZone: String, Codable, CaseIterable {
    case frontOfHouse   // 台前面光架（瞄表演者）
    case upstageTruss   // 上舞台桁架（往舞台/背幕打）
    case sideStageLeft  // 側台（左）
    case sideStageRight // 側台（右）
    case floor          // 地面 uplight / blinder
}

struct LightingCue {
    var id: String
    var name: String
    var transition: CueTransition
    var states: [String: FixtureState]   // 以 FixtureDefinition.id 為 key；缺 key = 該燈此 cue 關
}

struct FixtureState: Codable, Equatable {
    var enabled: Bool
    var intensity: Double          // 0...1
    var colorHex: String           // #RRGGBB
    var beamAngleDegrees: Double
    var gobo: GoboPattern?
}
```

### validate 規則（取代現有寫死角色的檢查）
- `schemaVersion == "1.0"`、`ambient.preset == .standardNight`（暫時保留）。
- `rig` 非空；每個 `FixtureDefinition.id` 唯一。
- cue 仍維持 **Opening + Highlight 兩個**（先不動 cue 數量；之後可放寬）；`selectedCueId` 要解析得到。
- 每個 cue 的 `states` 的 key 都必須是 rig 內存在的 fixture id；intensity 0...1、color 為合法 hex。
- gobo 僅保留在「會渲染 gobo」的燈具類型上（沿用 `rendersProjectedGobo` 概念，改成依 `LightingFixtureVisualModel`）。

### 遷移
- `mvpDemo()` 重寫成一個小的動態 rig：2 盞 `frontFresnel`(frontOfHouse) + 2 盞 `movingHeadBeam`(upstageTruss)，等價於現在的畫面。
- `LumaStageProject` 預設 / 範本 look 一併遷移。
- `LightingLookDraft` 改成組裝 rig + 兩個 cue 的 states。

## 3. 區域擺位（RigPlacement，Foundation 可測）

```swift
enum RigPlacement {
    /// 某 zone 內第 slot 盞（共 count 盞）的模型座標 + 朝向目標，依舞台幾何均分。
    static func placement(zone: FixtureZone, slot: Int, count: Int, layout: StageLayout)
        -> (position: Vector3Meters, aim: Vector3Meters)
}
```
- `frontOfHouse`：沿台前一條線、跨舞台寬度均分，FOH 高度，瞄表演區（沿用目前面光架的擺法 + 燈架幾何）。
- `upstageTruss`：沿桁架頂均分、懸掛，往舞台/背幕打。
- `sideStageLeft/Right`：側台 boom，往中間打。
- `floor`：台前地面均分，往上打。
- 用 smoke test pin：同 zone N 盞要均分、不重疊、落在合理範圍。

## 4. AI 生成（動態 @Generable schema）

每盞燈把「定義 + 兩個 cue 的狀態」**內嵌在一起**，避免 rig 與 states 對不齊的問題：

```swift
@Generable struct GeneratedLightingLook {
    @Guide(...) var lookName: String
    @Guide(...) var mood: String
    @Guide(description: "4–12 fixtures forming the whole rig", .count(4...12))
    var fixtures: [GeneratedFixture]
    @Guide(...) var explanation: GeneratedExplanation
}

@Generable struct GeneratedFixture {
    var name: String
    var type: GeneratedFixtureType   // 對映 LightingFixtureVisualModel 子集
    var zone: GeneratedZone
    var opening: GeneratedFixtureState
    var highlight: GeneratedFixtureState
}

@Generable struct GeneratedFixtureState {
    @Guide(.range(0.0...1.0)) var intensity: Double
    var colorHex: String
    var beamAngleDegrees: Double
    var gobo: GeneratedGobo
    var enabled: Bool
}
```
- `draft` 把 `fixtures` 拆成 `rig: [FixtureDefinition]`（含自動分配的 `slot`：同 zone 依出現順序編號）+ 兩個 cue 的 `states`。
- instructions 改成：描述這是一個戶外學生活動舞台，可用的 zone 與燈具類型，請依使用者描述（「熱舞社成發」→ 偏多彩、moving head、strobe）設計整套 rig 與 Opening/Highlight。
- 風險：on-device 模型對「可變長陣列 + 巢狀」較吃力 → `.count(4...12)` 約束 + 低溫；mapping 端對缺漏/超界做修補。

## 5. Renderer（動態化 ImmersiveView）

- `addDynamicRig(rig, layout, to:)`：對每盞 `FixtureDefinition`
  - 用 `FixtureRealityModel.makeEntity(for: fixture.model)`（你的 `FixtureSpatialScene`）生成可見燈具幾何；
  - 用 `RigPlacement` 算位置/朝向；
  - 加一個 `SpotLight`（命名 `spot_<fixtureId>`）對準 aim。
- `apply(cue, overrides:)`：對每盞燈 → `cue.states[id]`（或關）疊 `LightOverride` → 解析出 color/intensity/beam/gobo → 線性轉場套用（沿用現有 `animation(for:)`）。
- **動態標籤**：每盞燈旁標 `fixture.name` 或 `Light N`（用 RealityKit 文字或 attachment）。
- **單燈指令**：`StageLightID` 改成由 rig 動態產生（Light 1…N 對映 rig 順序）；`LightCommand` / `LightOverride` 不變。
- 移除寫死的 `addLightingPreview` / `addFrontLightStand` 的固定 2+2，改由 rig 驅動（燈架仍針對 `frontOfHouse` 類型生成）。

## 6. 既有單燈控制如何沿用

- `LightCommand.parse`（已完成、已測）不變；數字上限改成依 rig 數量檢查。
- `LightOverride` / `applyLightCommand`（已完成）不變。
- `StageLightID.all` 從寫死 4 盞 → `StageLightID.from(rig:)` 動態產生。

## 7. 測試遷移（會大改，這也是先出計畫的原因）

| 既有測試 | 處理 |
|---|---|
| `validatesDemoLookDefaults` | 改成驗證遷移後的 rig 形態 |
| `lightingLookDraftBuildsValidatedLook` / `…RejectsInvalidValues` / `goboFlowsThroughDraft…` / `aiDraftGuaranteesRenderable…` | 改成 rig + per-cue states 版 |
| `patchesOnlySelectedCue` / `fineControl…` / `resetsOnlySelectedCue` / `rejectsInvalidPatchValues` | `CuePatch` 改成以 fixtureId 定址，全部重寫 |
| `relightDebugSnapshotMapsCueFixtures` | snapshot 改讀 rig + states |
| `parsesSingleLightCommands` / `resolvesLightOverridesOntoCueValues` | 大致保留 |
| `spotLightRenderMath…` / 桁架幾何 / carousel / surroundings / sync | 不受影響 |
| 新增 | `FixtureDefinition`/rig validate、`RigPlacement` 均分、draft→rig 對映、`StageLightID.from(rig:)` |

## 8. 分階段

- **Phase 1 — 動態 model + renderer（用遷移後的靜態 rig）**：跑通整條動態管線（model→renderer），畫面等同現狀，測試全綠。先不接 AI。
- **Phase 2 — AI 動態生成**：動態 @Generable schema → rig + 兩 cue states，從高階 prompt 生成整場景。
- **Phase 3 — 手動增減 + 動態標籤/單燈指令收尾**：語音/手動加減燈，Light 1…N 標籤與指令完整化。
- **Phase 4 —（之後）real-world 輸出**：接 sync（OSC/Art-Net/sACN 或你的 iPad 面板）。

每個 Phase 結束都跑 smoke tests + Xcode 27 build 驗證。

## 9. 風險 / 待確認
- on-device 模型生成可變長巢狀結構的**穩定度**（需實機驗證 + mapping 修補）。
- 8–12 盞 spotlight + 軟陰影的**效能**（visionOS）；可能要限制投影陰影的燈數。
- 與你並行工作的**碰撞**：Phase 1 會大改 `LightingModels` / `LightingAIService` / `AppModel` / `ImmersiveView`；開工時需協調（你暫停核心檔，或我在 worktree 做）。
- cue 是否維持「恰兩個 Opening/Highlight」或放寬到任意數量（目前計畫：先維持兩個）。

## 10. 開工前 checklist
1. 你確認此設計方向。
2. 決定協作方式（暫停核心檔編輯 / worktree 隔離）。
3. 從 Phase 1 開始。
