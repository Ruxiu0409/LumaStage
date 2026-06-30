# SPEC 07 — 桌面 diorama「指哪擺燈」（C2）

**Goal**：在桌面舞台編輯器裡,讓使用者**在 diorama 上擺放/移動/對位燈具**(目前只能擺桁架/舞台),純空間運算 wow。ARKit 偵測 + `ManipulationComponent` + `TrussNodeSnap` 都已在,缺的是把「燈具」納入可操作物件 + 把擺位寫回 rig。

## Ground truth
- `TabletopStageEditorView`(`#if os(visionOS)`):mixed passthrough 空間,ARKit 把 diorama 放上真實桌;`TabletopStageScene` 建每物件容器 `stageobj_<id>`,`SpatialTapGesture` 選取、`DragGesture` 拖移(`resolveDrag`/`trussNodeSnap`),控制列 attachment。
- `AppModel.addStageObject`/`moveStageObject`/`removeSelectedStageObject` 操作 `StageLayout`(桁架/舞台幾何)。
- **架構關鍵**:燈具不在 `StageLayout`,而在 look 的 `cue.fixtureGroups`(rig);場上位置由 `RigPlacement.placement(zone:slot:count:layout:)` 從 zone 推算(`LightingModels.swift`)。所以「在桌上擺一盞燈」= 編輯 rig 的 fixture 位置/zone,不是 StageLayout。

## Work items
### 1. 模型層（owner A,`LightingModels.swift` / `StageBuilderModels.swift`,Foundation + smoke）
決定燈具擺位如何持久化。建議:`FixtureGroup` 已有 `fineControl.position`(可選);讓「桌面擺位」寫入該 fixture 的 `fineControl.position`/`zone`,並讓 `RigPlacement`/renderer 在 fixture 有明確 position 時**優先用它**而非 zone 推算。加純函式 `RigPlacement.resolvedPlacement(fixture:layout:slot:count:)`:`fixture.fineControl?.position` 有值就用,否則回退 zone 推算。smoke 測這個優先順序。

### 2. 桌面編輯器（owner B,`TabletopStageEditorView.swift`）
- 在 diorama 上為每盞 fixture 建可選取/拖移的小代理(沿用 `stageobj_` 的 collision+InputTarget+drag 模式),命名 `tabletopfixture_<fixtureId>`。
- 拖移 → 更新該 fixture 的 `fineControl.position`(經新 AppModel 方法,見 3);可選 node-snap 到桁架。
- 控制列加「新增燈具」(選型號)/「刪除所選燈具」。

### 3. `AppModel.swift`（owner C）
`moveFixture(id:toScenePosition:)` / `addFixtureToRig(model:zone:)` / `removeFixture(id:)`:編輯目前 look 所有 cue 裡該 fixture 的 `fineControl.position`(rig identity——各 cue 同 id 同位置),經 `StageState`/`replaceLightingLook` 驗證 + persist。

## Constraints / 並行
- owner A 先定模型(placement 優先序);B/C 對其寫。**這是較大的架構件**(把空間編輯接到 rig)——建議排在 P1/P2 之後。

## Verification
- smoke(`RigPlacement.resolvedPlacement` 優先序)→ passed。完整 build → SUCCEEDED。
- 實機:桌上拖一盞燈 → 回 1:1 舞台該燈在對應位置。

## Caveats
- rig 由 AI 重生成時會換 fixture 集合,手動擺位如何保留/合併需設計(類似 `lightOverrides` 跨重生成的議題)。實機驗 ARKit 擺位 + node-snap 手感。
