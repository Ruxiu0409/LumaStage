# SPEC 22 — 表演者人偶進編輯迴圈（可拖位、燈光瞄準）（issue #26）

> Status: done

**Goal**：把 1:1 舞台上既有的表演者人偶（`ImmersiveView.addPerformerStandIn`）變成**可控物件**——位置存進 `StageLayout`、在桌面編輯器裡可拖，並讓**前光／spot** 的 aim 朝人偶位置**微調**，把工作流升級成「圍繞表演者設計燈光」。對應 MAIC 社會價值「以人為本、教育賦能」。**影響面較大（動到共用 aim 推導），屬 M–L，需獨立評估。**

## Ground truth（沿用/呼叫,勿重寫）

- **人偶現況**：`ImmersiveView.addPerformerStandIn(to:layout:)`（`ImmersiveView.swift:~972`，`#if os(visionOS)`）是 `HumanoidFigurePlan`（`StageBuilderModels.swift:~822`，Foundation-only，smoke `humanoidFigurePlanIsAnatomicallyOrdered`）的唯一消費者。**目前站位是硬推**：`standX = stageBase.position.x`、`standZ = stageBase.position.z + stageSize.depth * 0.12`、feet.y = 甲板頂（`deckTopY`），使用者不可控、不在桌面編輯器。它是舞台幾何（不屬 opaque venue），故 build 時加一次（`ImmersiveView.swift:~197`），不在 `update:` 裡。
- **共用 aim 推導（本 spec 的高風險點）**：`RigPlacement`（**在 `LightingModels.swift`**，Foundation-only，smoke 集）。
  - `placement(zone:slot:count:layout:) -> (position, aim)`：zone 推算的位置＋**瞄準點**。`.stageFront` FOH aim ≈ 甲板前緣、`.stageLeft/.stageRight` 側 boom aim = `(centerX, topY+0.4, centerZ)`（表演者軀幹高）、`.stageBack/.fullStage` aim 朝**上舞台/背景**（洗背板）。
  - `resolvedPlacement(fixture:slot:count:layout:)`：**renderer（`ImmersiveView.syncRig`）與桌面編輯器共用的唯一入口**（SPEC 07）；回傳 zone aim，position 於 `manualPosition` 非 nil 時改用它（aim 維持 zone 推算），雷射先被 `mountsOnTrussOnly` 夾回 `.stageBack`。
  - `mountsOnTrussOnly(_:)`＝雷射（truss-only）；`deckTopY(in:)`＝甲板頂高；`stageCenterTarget(layout:)`＝「瞄準舞台中心」按鈕的目標點（本 spec **不動**它）。
  - `addRigFixture`（`ImmersiveView.swift:~641`）：`baseDir = scenePoint(placement.aim) - scenePoint(placement.position)`，再疊 `fixture.aimOffset`（SPEC 13）算 `restingDir`，同時驅動燈頭模型＋spotlight＋`LightEffectComponent.baseAim`。
- **`StageLayout`**（`StageBuilderModels.swift:1251`）：`Codable/Equatable`，**無自訂 `init(from:)`**（synthesized Codable，optional 屬性自動以「缺鍵→nil」解舊 JSON）。`validate()`（`:~1493`）只驗 `objects`，不會擋新增的 optional 欄位。`Vector3Meters`（`:143`）為 `Codable/Equatable`。
- **AppModel 擺位慣例**：`moveStageObject(id:toX:z:)`（`AppModel.swift:377`）走 `saveStageLayout(layout)`（內含 `layout.validate()`＋寫回 project）＋ `recordStageEditingUndoSnapshot()`；rig 側 `moveFixture`（`:479`）走 `stageState.replaceLightingLook`＋`persistCurrentProjectState`。
- **桌面編輯器**（`TabletopStageEditorView.swift`，`#if os(visionOS)`）：`TabletopStageScene` 建 `stageobj_<id>`（桁架/舞台）與 `tabletopfixture_<id>`（rig 燈）代理，parented 到同一 `assembly`；`selectTap`/`moveDrag` 依 entity 名前綴分流（`stageobj_`/`tabletopfixture_` 互斥），`scenePoint`/`sceneToMeters` 轉換。fixture 拖移為 XZ free（Y 保留）→ `moveFixture`；`sync(_:layout:selectedId:)` 走 layout、`syncFixtures(_:look:layout:selectedFixtureId:)` 走 look。body 需 eager-read `appModel.stageLayout`（已有）避 Observation footgun。

## Work items（精確契約,按檔案擁有權）

> 這是**一個 feature、一位 agent 序列執行**（非並行）。下列五個檔一路做完再一起編譯。逐項落地契約如下。

### WI-1 — `StageBuilderModels.swift`（模型：新增表演者位置欄位）
- 在 `StageLayout` 加 **additive optional** 欄位（放在 `metadata` 後）：
  ```swift
  /// 使用者在桌面編輯器擺的表演者站位（model 公尺；只用 x/z，y 由 renderer 釘到甲板頂）。
  /// additive：舊 JSON 缺鍵→nil（synthesized Codable 對 optional 自動 decodeIfPresent）。
  /// nil = 沿用預設站位（甲板中心，見 addPerformerStandIn）＝ aim 不微調（見 WI-2）。
  var performerPosition: Vector3Meters? = nil
  ```
- **不需自訂 `init(from:)`**（confirmed 無既有自訂 decoder）。若日後有人替 `StageLayout` 加了自訂 decoder，需在其中對本欄位用 `decodeIfPresent`。
- **勿改** `HumanoidFigurePlan`、`defaultStudentOutdoor()`（維持 `performerPosition = nil`，向後相容）。

### WI-2 — `LightingModels.swift`（共用 aim 推導：只「微調」不接管，本 spec 核心風險件）
在 `extension RigPlacement` 加**純函式 + 可調常數**：
```swift
/// 前光/spot aim 朝表演者微調的比例（0＝純 zone aim，1＝完全對準人偶）。初值 0.5，實機微調（見 Caveats）。
static let performerAimNudgeFraction = 0.5

/// 哪些 zone 的 aim 會追蹤表演者：只有「前打/側打的 key/spot」。背景洗（.stageBack/.fullStage）與
/// 雷射（truss-only）維持 zone aim，確保既有生成／音樂秀「洗背板」的打光方向完全不變。
static func aimTracksPerformer(zone: StageZone, model: LightingFixtureVisualModel) -> Bool {
    guard !mountsOnTrussOnly(model) else { return false }   // 雷射不受影響
    switch zone {
    case .stageFront, .stageLeft, .stageRight: return true
    case .stageBack, .fullStage:               return false
    }
}

/// 把 zone 推算的 aim 朝 layout 的 performerPosition **部分 blend**（lerp fraction），
/// 且只對 aimTracksPerformer 為真的 fixture。performerPosition 為 nil 或非追蹤 zone → 原樣回傳。
/// 這是「微調而非接管」：blend 分量固定 < 1，且 opt-in（沒放人偶就是 no-op），既有打光方向不被破壞。
static func performerNudgedAim(zoneAim: Vector3Meters, zone: StageZone,
                               model: LightingFixtureVisualModel, layout: StageLayout) -> Vector3Meters {
    guard let target = layout.performerPosition,
          aimTracksPerformer(zone: zone, model: model) else { return zoneAim }
    let f = performerAimNudgeFraction
    return Vector3Meters(
        x: zoneAim.x + (target.x - zoneAim.x) * f,
        y: zoneAim.y + (target.y - zoneAim.y) * f,
        z: zoneAim.z + (target.z - zoneAim.z) * f
    )
}
```
在 `resolvedPlacement(fixture:slot:count:layout:)` 內，於算完 `zonePlacement` 後、**回傳前**，把 aim 換成 nudged 版（用解析後的 `zone`＋`fixture.renderModel`），position 分支（manual/非 manual）**不動**：
```swift
let zonePlacement = placement(zone: zone, slot: slot, count: count, layout: layout)
let aim = performerNudgedAim(zoneAim: zonePlacement.aim, zone: zone,
                             model: fixture.renderModel, layout: layout)
guard let manual = fixture.manualPosition else {
    return (zonePlacement.position, aim)
}
var position = Vector3Meters(x: manual.x, y: manual.y, z: manual.z)
if trussOnly { position = clampedToTruss(position, layout: layout) }
return (position, aim)
```
- **不動** `placement(...)`（保留為 zone 基準；`fixtureAimMathInvertsRestingAimRotation` 直接呼 `placement` 與 `stageCenterTarget`，故不受本改動影響、不回歸）、`stageCenterTarget`、`enforcingTrussMountedLasers`。

### WI-3 — `AppModel.swift`（狀態：move setter，鏡射 moveStageObject）
```swift
/// 桌面編輯器把表演者拖到某 XZ 時提交（model 公尺）。表演者是 layout 資料（隨 project 持久化、跨 AI 重生成
/// 存活——不同於 manualPosition/lightOverrides）；Y 釘到甲板頂讓腳踩甲板。走 saveStageLayout（含 validate）。
func moveStagePerformer(toX x: Double, z: Double) {
    var layout = stageLayout
    layout.performerPosition = Vector3Meters(x: x, y: RigPlacement.deckTopY(in: layout), z: z)
    recordStageEditingUndoSnapshot()
    saveStageLayout(layout)
}
```
- **不清空**：`performerPosition` 屬 `StageLayout`（像桁架物件），故 `openProject`/`generate`/reset 皆**不**清它（勿加到 `lightOverrides = [:]` 那些清除點）。

### WI-4 — `ImmersiveView.swift`（人偶讀新位置）
- `addPerformerStandIn(to:layout:)`：feet 的 X/Z 改讀 `layout.performerPosition`（存在時用其 `.x`/`.z`），**Y 一律用 `deckTopY`**（腳踩甲板）；`performerPosition == nil` 時 fallback 現行預設（`standX/standZ`）。其餘幾何建構（`HumanoidFigurePlan.make` / material / blobs）**不動**。
- 前光/spot 對人偶的實際瞄準**已由 WI-2 的 `resolvedPlacement` 自動生效**（`syncRig`→`addRigFixture` 既走 `resolvedPlacement(...).aim`），本檔**不需**改 syncRig。
- **不需**把 `performerPosition` 放進 `syncRig` 的 rebuild signature：編輯只發生在**被替換的桌面 mixed 空間**，回到 1:1 舞台時整個 immersive space 已重建，故 `layout.performerPosition` 於重建時讀到最新值（見 Caveats）。

### WI-5 — `TabletopStageEditorView.swift`（可拖代理）
- 建**單一**表演者代理，命名 `tabletopperformer`（非 per-id），parented 到與 `stageobj_`/`tabletopfixture_` 同一 `assembly`（共用 `scenePoint`/`sceneToMeters` 與座位偏移）。代理外觀：一個可辨識的直立標記（簡單 capsule／縮小版人偶皆可），色調與灰桁架可辨，掛 `BillboardComponent` 浮動標籤「表演者」。位置＝`layout.performerPosition ?? 預設站位`（與 `addPerformerStandIn` fallback 同源）→ `scenePoint`。
- `selectTap`/`moveDrag` 前綴分流加 `tabletopperformer` 分支：拖移為 **XZ free（Y 保留、無 node-snap）**，放手 → `sceneToMeters(container.position)` 取 x/z → `appModel.moveStagePerformer(toX:z:)`。與 `stageobj_`/`tabletopfixture_` 選取互斥。
- 在對應 sync（走 layout 那條，`sync(_:layout:selectedId:)`）建/更新此代理（body 已 eager-read `stageLayout`）。控制列可補一顆「重置表演者位置」（可選，非必須）。
- 無障礙：代理／新按鈕補繁中 `accessibilityLabel`、≥60pt 注視目標、Reduce Motion gate 沿用既有；設計 token 用 `LumaStageDesign`。

### WI-6 — `Tests/LumaStageCoreSmokeTests.swift`（新增 smoke，兩檔皆在 smoke 集）
在 `main()` 註冊呼叫：
1. `stageLayoutPerformerPositionCodableDefaultsNil`：`StageLayout` JSON **缺** `performerPosition` 鍵 → decode 出 `nil`；設值後 encode→decode round-trip 相等。
2. `performerNudgeMovesFrontAimNotBacklight`（**釘死風險緩解**）：
   - `layout.performerPosition = nil` → `.stageFront`／`.stageBack`／雷射 fixture 的 `resolvedPlacement(...).aim` **全等於** `placement(...).aim`（無回歸）。
   - 設一個明顯偏離中心的 `performerPosition` → `.stageFront` fixture 的 aim **朝人偶方向移動**（介於 zone aim 與 performer 之間、恰為 `performerAimNudgeFraction` 比例，且**不等於**任一端點）；`.stageBack`（背景洗）aim **不變**；雷射 aim **不變**。
- 無新 Foundation 檔 → smoke 編譯集清單**不變**（`StageBuilderModels.swift`、`LightingModels.swift`、`Tests/...` 皆已在集內）。

## Constraints / 並行

- 平台守衛：`ImmersiveView`/`TabletopStageEditorView` 為 `#if os(visionOS)`；`StageBuilderModels.swift`／`LightingModels.swift` 維持 **Foundation-only**（可判定邏輯進此二檔＋smoke）。
- **不重寫** `RigPlacement.placement`／`stageCenterTarget`／`enforcingTrussMountedLasers`／`validate()`／`HumanoidFigurePlan`；不動既有 cue 編輯、生成鏈、音樂秀路徑。
- aim **只微調不接管**：blend 分量固定 `< 1`、且僅前打/側打 zone、且僅在 `performerPosition` 非 nil 時生效 → 沒放人偶＝完全 no-op。
- 檔案擁有權（避免並行覆寫，若日後拆分）：模型 `StageBuilderModels.swift`＋`LightingModels.swift`；狀態 `AppModel.swift`；renderer `ImmersiveView.swift`；view `TabletopStageEditorView.swift`；測試 `Tests/LumaStageCoreSmokeTests.swift`。

## Verification

- **smoke**（Foundation-only，README 指令；兩新測試已註冊進 `main()`）：
  ```
  swiftc Tests/LumaStageCoreSmokeTests.swift LumaStage/LightingModels.swift LumaStage/StageBuilderModels.swift … \
    -o /tmp/smoke && /tmp/smoke
  ```
  通過 = 印出 `LumaStageCoreSmokeTests passed`（含新 2 條）。
- **完整 build**：
  ```
  xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
  ```
  通過 = `** BUILD SUCCEEDED **`（Multipeer Sendable 警告／MCSession `error:` 字樣行為既有噪音,忽略）。
- **實機（Vision Pro）**：桌面編輯器拖表演者 → 回 1:1 舞台，人偶站到對應位置，且**前光/spot 明顯朝人偶偏**、**背景洗/雷射方向不變**；不放人偶時打光與現況一致。

## Caveats

- **〔核心風險——aim 推導緩解，需獨立評估＋[需實機]〕** 本 spec 動到 renderer 與桌面編輯器**共用**的 `RigPlacement.resolvedPlacement` aim。緩解設計：(1) 只**部分 blend**（`performerAimNudgeFraction` 初值 0.5，`< 1` 永不完全接管）；(2) 只對前打/側打 zone（`.stageFront/.stageLeft/.stageRight`），**背景洗（`.stageBack/.fullStage`）與雷射（truss-only）維持 zone aim**；(3) **opt-in**——`performerPosition == nil`（含所有現有 project／`defaultStudentOutdoor`）時完全 no-op。`performerNudgeMovesFrontAimNotBacklight` smoke 釘住「nil→無回歸」「背光/雷射不變」「前光按比例朝人偶」。**blend 比例 0.5 是否觀感恰當、會不會把 FOH 打歪、側 boom 追蹤是否過頭、對 AI 生成/音樂秀既有打光的實際衝擊，需實機驗、必要時調 `performerAimNudgeFraction` 或縮小追蹤 zone 集合。**
- **人偶位置於「舞台重建」時生效，非活舞台即時**：編輯在被替換的桌面空間進行，回程整個 stage immersive space 重建 → `addPerformerStandIn` 與 `syncRig`(讀 layout) 讀到新 `performerPosition`。同一 stage session 內 layout 不變，故不需把 `performerPosition` 併入 `syncRig` signature。[需實機] 確認回程無閃爍、人偶與 aim 同步更新。
- **`performerPosition` 是 layout 資料、跨 AI 重生成存活**（不同於 `manualPosition`/`lightOverrides`——後者於 `generate` 被清）：這是刻意的，人偶站位屬舞台佈局。
- 桌面拖移為 **XZ free（Y 釘甲板頂）**；代理外觀/尺寸/抓握手感、標籤在 passthrough 的對比、ARKit 擺位精度需實機驗。
- **刻意延後**：「瞄準舞台中心」按鈕改成「瞄準表演者」（現維持 `stageCenterTarget`＝舞台中心）；per-fixture 個別 blend 比例；#C1 迷你預覽合看（預覽＋人偶＝桌上完整迷你場景）。
