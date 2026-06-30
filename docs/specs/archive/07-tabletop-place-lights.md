# SPEC 07 — 桌面 diorama「指哪擺燈」（C2）

> Status: done

**Goal**：在桌面舞台編輯器裡,讓使用者**在 diorama 上擺放/移動/對位燈具**(目前只能擺桁架/舞台),純空間運算 wow。ARKit 偵測 + `ManipulationComponent` + `TrussNodeSnap` 都已在,缺的是把「燈具」納入可操作物件 + 把擺位寫回 rig。

## Ground truth
- `TabletopStageEditorView`(`#if os(visionOS)`):mixed passthrough 空間,ARKit 把 diorama 放上真實桌;`TabletopStageScene` 建每物件容器 `stageobj_<id>`,`SpatialTapGesture` 選取、`DragGesture` 拖移(`resolveDrag`/`trussNodeSnap`),控制列 attachment。
- `AppModel.addStageObject`/`moveStageObject`/`removeSelectedStageObject` 操作 `StageLayout`(桁架/舞台幾何)。
- **架構關鍵**:燈具不在 `StageLayout`,而在 look 的 `cue.fixtureGroups`(rig);場上位置由 `RigPlacement.placement(zone:slot:count:layout:)` 從 zone 推算(`LightingModels.swift`)。所以「在桌上擺一盞燈」= 編輯 rig 的 fixture 位置/zone,不是 StageLayout。

## 探勘修正（實際型別,覆蓋下方舊假設）
- `FixtureGroup.fineControl` 是 `FixtureFineControl?`(optional),但其內 `position: FixturePosition`(x/y/z `Double`)**不是 optional**,且 `fineControl` 常被 `FixtureFineControl.default(role:zone:)`/`effectiveFineControl` 自動帶值——所以「`fineControl.position` 有值」**不能**當「使用者手動擺過」的訊號。
- 正解(沿用 SPEC 01 `effect: LightEffect?` additive 模式):在 `FixtureGroup` 加**新 optional 欄位** `manualPosition: FixturePosition?`(`Codable`,舊 JSON 解 `nil`),只有它有值才算「手動擺位」。
- `RigPlacement.placement(zone:slot:count:layout:) -> (position: Vector3Meters, aim: Vector3Meters)` 是現有唯一推算入口;renderer 唯一呼叫點 `ImmersiveView.swift:~599`(syncRig 迴圈)。`TabletopStageScene` 用自己的 `scenePoint`/`sceneToMeters`、**不**呼叫 `RigPlacement`。
- `FixturePosition` 與 `Vector3Meters` 都是 x/y/z;`AppModel.moveStageObject(id:toX:z:)` 慣例**以模型公尺**呼叫、走 `saveStageLayout`→`persistCurrentProjectState`。look 持久化:`StageState.replaceLightingLook(_)`(內含 `validate()`)+ persist。

## Work items（精確契約,對下列簽名寫）

### Phase 1 — 模型 + 狀態 + renderer（單一 agent,序列做完並編譯通過）
擁有 `LightingModels.swift`、`AppModel.swift`、`ImmersiveView.swift`(僅換呼叫點)、`Tests/LumaStageCoreSmokeTests.swift`。

1. **`LightingModels.swift`**
   - `FixtureGroup` 加 `var manualPosition: FixturePosition? = nil`(放在 `effect` 後;`Codable` 預設、確認舊 JSON 缺鍵解 `nil`)。
   - 加純函式:
     ```swift
     extension RigPlacement {
       /// zone 推算的 (position, aim);若 fixture 有 manualPosition,position 改用它(aim 維持 zone 推算)。
       static func resolvedPlacement(fixture: FixtureGroup, slot: Int, count: Int, layout: StageLayout)
           -> (position: Vector3Meters, aim: Vector3Meters)
     }
     ```
     實作:先 `placement(zone: fixture.zone, slot:count:layout:)`,若 `fixture.manualPosition` 非 nil 則把回傳 `.position` 換成它(`Vector3Meters(x:y:z:)`),`aim` 保留。
   - smoke:`fixtureManualPositionOverridesZonePlacement`——無 manualPosition → 等同 `placement(...)`;有 manualPosition → position 用它、aim 不變;另測舊 JSON(無 `manualPosition` 鍵)decode 出 `nil`。
2. **`ImmersiveView.swift`**:把 `syncRig` 那一處 `RigPlacement.placement(zone:slot:count:layout:)` 換成 `RigPlacement.resolvedPlacement(fixture:slot:count:layout:)`(其餘不動)。
3. **`AppModel.swift`**(mirror `moveStageObject`/`removeSelectedStageObject` 模式,全部走 `replaceLightingLook` 驗證 + persist;失敗 `fail(...)`):
   - `var selectedFixtureId: String? = nil`(於 `openProject`/`generate` 清成 nil,沿用 `lightOverrides = [:]` 那兩處)。
   - `func selectFixture(id: String?)`
   - `func moveFixture(id: String, toX x: Double, y: Double, z: Double)`:把**所有 cue** 裡同 `id` 的 fixture 的 `manualPosition` 設成 `FixturePosition(x:y:z:)`(rig identity——各 cue 同 id 同位置),replaceLightingLook + persist。
   - `func addFixtureToRig(model: LightingFixtureVisualModel, zone: StageZone)`:新 id,對**所有 cue** append 一個 `FixtureGroup`(role/color/fineControl 用該 zone+model 的合理預設,enabled=true,初始 `manualPosition = nil`),replaceLightingLook + persist + `selectedFixtureId = 新id`。**先讀 `validate()` 是否有 fixture 數上限(動態 rig 4–12),超限則 `fail` 不加。**
   - `func removeSelectedFixture()`:刪 `selectedFixtureId`,對**所有 cue** 移除該 fixture,replaceLightingLook + persist + 清 selection。**若會跌破 `validate()` 的最少 fixture 數則 `fail` 不刪。**
   - 把新檔(無)/改動納入既有 smoke 編譯集不需動(AppModel 不在 smoke 集);`LightingModels` 的新 smoke 直接加進現有指令。

### Phase 2 — 桌面編輯器（單一 agent,對 Phase 1 真實簽名寫）
擁有 `TabletopStageEditorView.swift`。
- 在 diorama 上為目前 look 每盞 fixture 建可選取/拖移代理,命名 `tabletopfixture_<fixtureId>`(沿用 `stageobj_` 的 `addInteraction`=collision+`InputTargetComponent`、`SpatialTapGesture` 選取、`DragGesture`+`resolveDrag`/`updateSnapIndicator` 模式;walk-up 找容器同 `objectContainer`/`objectId` 寫一組 `fixtureContainer`/`fixtureId`)。初始位置由 `RigPlacement.resolvedPlacement(fixture:slot:count:layout:)` 取模型公尺 → `scenePoint` 轉桌面 scene 單位。
- 選取 → `appModel.selectFixture(id:)`;拖移結束 → `sceneToMeters(container.position)` 取 x/z(y 用該 fixture 現有 resolved y)→ `appModel.moveFixture(id:toX:y:z:)`;可選 node-snap 到桁架(沿用 `trussNodeSnap`,非必須)。
- 控制列(attachment)加:「新增燈具」Menu(選 `LightingFixtureVisualModel` 型號 → `appModel.addFixtureToRig(model:zone:)`,zone 可先固定 `.stageFront` 或給選項)、「刪除所選燈具」(`appModel.removeSelectedFixture()`)。
- 無障礙:新按鈕補 `accessibilityLabel`、≥60pt、Reduce Motion gate 沿用既有。

## Constraints / 並行
- **兩階段序列**,非三路並行:Phase 1 把真實簽名落地並 build 綠後,Phase 2 對真實程式碼寫(此為較大架構件,降整合風險)。
- `#if os(visionOS)`(view/renderer);`LightingModels` 維持 Foundation-only。不重寫 `RigPlacement.placement`/validate/既有 cue 編輯。

## Verification
- Phase 1:smoke(`fixtureManualPositionOverridesZonePlacement` + 舊 JSON 回退 nil)→ `LumaStageCoreSmokeTests passed`;完整 build → `** BUILD SUCCEEDED **`。
- Phase 2:完整 build → `** BUILD SUCCEEDED **`。
- 實機:桌上拖一盞燈 → 回 1:1 舞台該燈在對應位置;新增/刪除燈具反映到 rig。

## Caveats
- **AI 重生成換 fixture 集合 → 手動 `manualPosition` 隨舊 look 一起被取代(同 `lightOverrides` 跨重生成議題),v1 接受,不做合併。**
- 桌面拖移目前 XZ(y 維持 resolved 值);全 3D 擺位、node-snap 手感、新增燈具的 zone 選擇 UI、ARKit 擺位精度需實機驗。
