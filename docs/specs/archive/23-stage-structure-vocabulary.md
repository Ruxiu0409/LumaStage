# SPEC 23 — 擴充舞台結構詞彙（側塔／地面 boom 架／中場第二桁架）＋清理未接線的 deck 資產

> Status: done

**Goal**：兩件事，一份 spec（issue #27）——
(a)**先做、低風險**：清掉 `StageAssetId` 那三個從未能被加入舞台的 deck 資產（死詞彙，會誤導後續開發）。
(b)**後做、L（大）**：把舞台結構詞彙擴充成含**側塔（side tower）／地面 boom 架／中場第二道桁架**的可加結構，讓雷射與搖頭燈能拿到**側掛／中場高掛位**。呼應 MAIC 戰略書 #B1（高度）、#B5（朝向）——伸展台／側塔會放大這兩項的價值。
**關鍵前提（issue 明講、本 spec 沿用）**：連接節點吸附（`StageLayout.trussNodeSnap`）與支撐守則（`RigPlacement.support`）**都已通用**——(b) 是**詞彙擴充，不是新機制**。只要新結構由既有 `.trussSegment` 組成，renderer／node-snap／support policy／footprint 全都自動吃到，**不需新增 render 型別**。

**為什麼 (a) 綁著 (b) 一起設計**：(b) 想加的側塔／boom／中場桁架都是 **truss 家族**（垂直／水平桁架），不是 **平台家族**（deck）。所以「把 deck 補完成伸展台／T 台／thrust」與 (b) 想要的側掛位**無關**——deck 補完會是另一條「平台形狀」功能。因此本 spec 對 (a) 的建議是**刪除**，把 truss-family 的擴充留給 (b)；deck 若日後真要做平台形狀（伸展台/thrust），另開專案。

---

## Part (a) — 清理未接線的 deck 資產

### 現況（已在程式碼核實）：deck 不是「純死碼」，而是「被刻意接成不可加」
`StageAssetId.stageDeck1x1 / stageDeck2x1 / stageDeck2x2`（`StageBuilderModels.swift:15-17`）＋其 `deckSize`（`:49-62` 的三個 deck 分支 `:54-58`）確實**從未能被使用者加入**：

- 控制列「新增桁架」Menu 只給 `.truss1m`/`.truss2m`（`TabletopStageEditorView.swift:278-283`），沒有任何 deck 入口。
- 桌面 `TabletopStageScene.makeAssembly` 對 `.stageDeck` 直接 `break`（`TabletopStageEditorView.swift:1068-1070`，「decks embedded in stage base; not shown separately」）。
- `ImmersiveStageGeometryPlan.make`（`StageBuilderModels.swift:748-761`）只消費 `stageBase` + `trussSegment`，不畫 deck。

**但**它們被**主動接線來「擋掉」deck**，且被 smoke 釘住：

- `StageBuilderDropPlanner.object(...)` 對 `.stageDeck` objectType 明確 `return nil`（`StageBuilderModels.swift:678-679`）——「drop 一塊 deck → 不建立物件」是刻意行為。
- smoke `stageBuilderDropPlannerPlacesDraggedAssets` **釘住** `StageBuilderDropPlanner.object(assetId: .stageDeck2x2, …) == nil`（`Tests/LumaStageCoreSmokeTests.swift:551-554`）。
- smoke `newProjectFactoryCreatesDefaultStageLayout` **釘住** `!layout.objects.contains(where: { $0.type == .stageDeck })`（`Tests/LumaStageCoreSmokeTests.swift:287`，`StageObjectType` 斷言）。

此外 `StageObjectType.stageDeck`（`:9`）連著一整套**目前無人渲染**的 deck 幾何：`StageObject.stageDeck(…)` 工廠（`:942-961`）、`stageDeckAssembly`（`:1064-1131`）、`StageDeckFaceKind`/`StageDeckFace`/`StageDeckSupportLeg`/`StageDeckAssembly` 型別（`:217-251`），以及散落在 `objectType`-driven switch 的 `.stageDeck` 分支：`StageBuilderRenderOrder.lhsRenderDepth`（`:461-462`）、`StageBuilderObjectLayerHitTesting.allowsDirectLayerTap`（`:607-613`）、`StageLayout.validate(_:)`（`:1525-1534`）、`StageLayout.stageSummary()` 的 deck fallback 分支（`:1476-1490`）、`TabletopStageEditorView.selectedObjectTypeName`（`:568-569`）。

### 兩個選項（issue 給的）

#### 選項 (i) —— **刪除（建議）**
移除三個 `StageAssetId` deck case ＋ 它們在各 computed property 的 deck 分支，並更新被釘的 smoke。**分兩級**，本 spec 建議只做 **i-min**（低風險）、把 i-full 當可選後續：

- **i-min（建議實作範圍）**：只刪 `StageAssetId` 層的死詞彙，**保留** `StageObjectType.stageDeck` 與其幾何（它們是 inert、被別的 switch 當窮舉分支引用，刪掉會連鎖擴散）。
  觸及：
  1. `StageBuilderModels.swift`
     - 刪 `StageAssetId.stageDeck1x1/2x1/2x2`（`:15-17`）。
     - `displayName`：刪三個 deck 分支（`:25-30`）。
     - `objectType`：把 `case .stageDeck1x1, .stageDeck2x1, .stageDeck2x2: return .stageDeck`（`:42-43`）移除（`StageObjectType.stageDeck` case 本身**保留**，只是沒有 assetId 再映射到它）。
     - `deckSize`：刪三個 deck 分支（`:54-58`），`stageBase` 分支保留；`.truss1m,.truss2m` 分支的 `case` 標籤把已刪的 deck case 拿掉。
     - `trussLength`：把 `:70` 的 `case .stageBase, .stageDeck1x1, .stageDeck2x1, .stageDeck2x2: return nil` 改成 `case .stageBase: return nil`。
     - `StageBuilderDropPlanner.object` 的 `case .stageDeck: return nil`（`:678-679`）與 `defaultPosition` 的 `.stageDeck` 分支（`:695-697`）：因 `switch assetId.objectType` 仍窮舉 `StageObjectType`（含保留的 `.stageDeck`），這兩個分支**留著**（現在恆不可達，但編譯需要）——加一行註解說明「no `StageAssetId` maps to `.stageDeck` anymore；kept for exhaustiveness」。
     - `StageObject.stageDeck(…)` 工廠（`:942-961`）：現在無合法呼叫端（需要 deck assetId 才能通過 `validate`）。**保留但標註** deprecated/dead（依全域規則「既有 dead code 只提及、不刪」——但因 issue 明確授權清理，若要刪見 i-full）。
  2. `Tests/LumaStageCoreSmokeTests.swift`
     - `stageBuilderDropPlannerPlacesDraggedAssets`（`:551-554`）：`.stageDeck2x2 == nil` 這條斷言引用已刪的 case → **移除該行**（或改成以任一保留 assetId 驗 drop 成功；deck 特定的「擋掉」語義已隨 case 消失）。
     - `newProjectFactoryCreatesDefaultStageLayout`（`:287`）：`!contains(.stageDeck)` 引用的是 `StageObjectType.stageDeck`（**保留**），故**不需改**——它仍是有效不變式（預設 layout 無 deck 物件）。
     - `stageLibraryHidesStandaloneStageDecks`（`:516-518`）：只斷言 `StageBuilderStageLibraryAssets.stageTab == [.stageBase]`，不引用 deck case → **不需改**。
- **i-full（可選、較廣的機械式刪除，本 spec **不建議**在同一 PR 做）**：連 `StageObjectType.stageDeck` case、`StageObject.stageDeck` 工廠、`stageDeckAssembly`、`StageDeck*` 型別、以及上列所有 `.stageDeck` switch 分支全刪。連鎖點多（`lhsRenderDepth`/`allowsDirectLayerTap`/`validate(_:)`/`stageSummary`/`makeAssembly`/`selectedObjectTypeName`），且要重寫 `newProjectFactory` smoke（改用別的方式表達「無 deck」）。**風險/收益比差，延後或不做。**

#### 選項 (ii) —— **補完成真結構（不建議，與 (b) 正交）**
把三個 deck 補成可加的伸展台／T 台／thrust：新增「新增平台」Menu 入口、`StageBuilderDropPlanner` 對 deck 回傳實體、`makeAssembly`/`ImmersiveStageGeometryPlan.make` 增 `.stageDeck` 的渲染分支（消費既有 `stageDeckAssembly` 幾何——這部分已寫好）、AI/擺位無需動。
觸及：`StageBuilderModels.swift`（drop planner deck 分支改回傳物件、可能新增 T 台/thrust 尺寸）、`TabletopStageEditorView.swift`（新增平台 Menu + `makeAssembly` deck 分支 + deckEntity 幾何）、`ImmersiveView.swift`（`makeStageLayoutEntity`/`ImmersiveStageGeometryPlan.make` 增 deck 分支）、smoke（改「擋掉 deck」為「可加 deck」）。
**不建議**：這是「平台形狀」功能，與 (b) 想要的**側掛位**無關；且要動 3 個 renderer。若使用者日後真要伸展台，另開 spec（可沿用已寫好的 `stageDeckAssembly` 幾何）。

### (a) 建議結論
**做選項 (i) 的 i-min**：花最小力氣移除會誤導人的 `StageAssetId` deck 死詞彙，保留 inert 的 `StageObjectType.stageDeck` 幾何（不連鎖、符合「既有 dead code 只提及不刪」），並修 1 條 smoke。i-full 與選項 (ii) 都延後。

---

## Part (b) — 擴充舞台結構詞彙（側塔／地面 boom／中場桁架）

### 設計主張：新結構＝既有 `.trussSegment` 的**組合**，不是新型別
核實過的通用性——只要新結構的每一件都是 `.trussSegment` StageObject：

- **渲染免費**：`ImmersiveStageGeometryPlan.make` 過濾 `type == .trussSegment` 後 `flatMap(\.trussLattice.allMembers)`（`StageBuilderModels.swift:750-752`），`ImmersiveView.makeStageLayoutEntity` 逐 member 建幾何（`:317-321`）。桌面 `TabletopStageScene.trussSegmentEntity`（`:1115-1133`）同理。`StageObject.trussLattice` + `trussBasis`（`:1133-1231`）已處理**垂直**（`rotation.z==90` → 沿 +Y）與水平（沿 +X／+Z）兩種朝向——portal 的腿就是垂直桁架。
- **node-snap 免費**：`StageLayout.trussNodeSnap`（`:1427-1448`）／`snappedObject`（`:1450-1462`）對所有 `.trussSegment` 端點通用——拖曳新結構會自動吸附到既有節點。
- **support/footprint 免費**：`RigPlacement.trussFootprint`（`LightingModels.swift:2053-2060`）取**所有** `trussEndpoints` 的 XZ 包圍盒＋頂高；`support(forPosition:layout:)`（`:2078-2085`）據此判吊掛/落地；雷射 `clampedToTruss`（`:2043-2050`）夾進同一 footprint。新增側塔/中場桁架會**自動擴大** footprint，於是使用者把雷射/搖頭燈**拖近側塔**（`manualPosition`）→ 落在擴大後的 footprint 內且夠高 → `support` 回傳 `.hangFromTruss`（真的掛上去，不浮空）。這就是 issue 說的「側掛位」——經**既有** manual-drag + support 路徑達成。

⇒ **不新增 `StageObjectType`、不新增 render 分支、不動 `ImmersiveStageGeometryPlan.make`**（issue 的「possibly `ImmersiveStageGeometryPlan`」只在引入**非 truss** 新型別時才需要——本 spec 刻意避開）。
⇒ **也不新增 `StageAssetId`**：新結構的每段沿用既有 `.truss2m`/`.truss1m`（`trussPortalPreset` 就是這樣拼 portal 的，`:1332-1377`）。詞彙擴充落在**結構 preset 層**，不在 asset 層。

### Ground truth（沿用，勿重寫）

- **組桁架群的範本**：`StageLayout.trussPortalPreset(_:upstageZ:)`（`StageBuilderModels.swift:1332-1377`）——回傳 `[StageObject]`，用 stacked-2m-封頂-1m 的 while 迴圈鋪垂直腿（`rotation: Vector3Degrees(x:0,y:0,z:90)`）與水平頂桿。**新 preset 抄同一鋪法**。
- **位置一律從 stage base 尺寸推導、不硬編**：見 `defaultStudentOutdoor()`（`:1294-1319`）如何用 `StagePlatformPreset.medium6x3.stageBaseSize` 與 `upstageZ = -(depth/2) - 0.25` 推 portal 位置。新 preset 的 x/z/height 全部從 layout 現有 stage base 推。
- **truss 工廠 + 端點**：`StageObject.trussSegment(id:assetId:position:rotation:)`（`:983-1002`）；`trussEndpoints`（`:1004-1019`）依 rotation 決定沿 X/Y/Z。
- **加入 layout 的既有入口**：`AppModel.addStageObject(assetId:)`（`AppModel.swift:419-439`）——經 `StageBuilderDropPlanner.object` 建**單一**物件 → `layout.addObject`（跑 `snappedObject`＋`validate`＋擲重複 id）→ `recordStageEditingUndoSnapshot()` → `saveStageLayout` → 設 `selectedStageObjectId`。**新的群組加法 mirror 這條，但一次 append 多件**。
- **控制列 Menu 範本**：`TabletopStageEditorView.swift:278-287`（「新增桁架」Menu、`.buttonStyle(.bordered)`、`.lumaGazeTarget()`、`.help(...)`）。繁中字串 + 設計 token 沿用。
- **雷射側掛的既有守則**：`LightingLook.enforcingTrussMountedLasers()`（`LightingModels.swift:2115-2136`）把雷射 zone 正規化為 `.stageBack`；`resolvedPlacement`（`:1989-2004`）對雷射走 `clampedToTruss`。**side tower 擴大 footprint 後，雷射 manualPosition 會被夾到含側塔的更大範圍**——不需改這些函式。

#### 關鍵 footgun（(b)）
- **① footprint 是「單一包圍盒」，多結構會被合併**：`trussFootprint` 取所有 truss 端點的**一個** XZ bounding box。加了左右側塔後，兩塔中間的空檔也落在 footprint 內——一盞被拖到「兩塔之間、上方沒有任何桁架」的燈會被 `support` 判成 `.hangFromTruss`（浮空）。SPEC 15 把「多桁架自動泛化」當**功能**（頂棚桁架下的燈正確吊掛），但這是它的**反面**。→ v1 接受此限制（實務上使用者會把燈拖到塔的正下方）；**per-structure footprint** 列入 Caveats/後續。**不要**為此重寫 support policy。
- **② 位置要落在 grid 上**：`addObject` → `snappedObject` 會 gridSnap（`gridSize` 0.5）並跑 `trussNodeSnap`。preset 產的位置若不在 0.5m grid 上會被位移、破壞塔的堆疊對齊。→ preset 座標一律用 stage 尺寸推導後**對齊 0.5**（或明知 stage base 尺寸為 0.5 的倍數）。堆疊段的相鄰端點重合 → `trussNodeSnap` 對它們是 no-op（snap 目標＝原位）。
- **③ id 唯一**：群組加法要為每段給唯一 id（`addObject` 對重複 id 擲 `duplicateObjectId`）。用 `"\(preset.rawValue)_\(shortUUID)_\(i)"`。
- **④ 別動 zone 自動擺位**：`RigPlacement.placement` 的 `stageLeft/stageRight` 仍給落地 boom 高度（`LightingModels.swift:1972-1982`，`y = topY + 1.2`）。讓 zone 自動把側燈掛上側塔＝**新的擺位邏輯**，非詞彙擴充 → **不在本 spec**（見 Caveats「延後」）。v1 靠 manual-drag 把燈掛上側塔。

### Work items（(b)；單一 agent 序列做，因與 (a) 共用 `StageBuilderModels.swift` + smoke）

> **檔案擁有權**：整份 spec（(a)+(b)）由**一個 agent** 序列完成——`StageBuilderModels.swift`、`AppModel.swift`、`TabletopStageEditorView.swift`、`Tests/LumaStageCoreSmokeTests.swift` 都被 (a)/(b) 觸及且互相依賴（尤其 `StageBuilderModels.swift` 兩部分都改）。**先做 (a) i-min，再做 (b)**。

#### WI-1 `StageBuilderModels.swift`（Foundation-only，已在 smoke 集）— 新結構 preset
新增一個 `StageStructurePreset` enum ＋ 產生 `[StageObject]`（全 `.trussSegment`、沿用 `.truss1m`/`.truss2m`）的純函式。位置全部從傳入 `layout` 的 stage base 推導。契約（示意，常數待實機微調）：

```swift
/// 舞台結構詞彙（issue #27 (b)）：由既有 `.trussSegment` 組成的可加結構——側塔／地面 boom／中場第二桁架。
/// 純幾何，回傳的每件都是 `.trussSegment`，故 renderer / node-snap / support policy / footprint 全自動吃到，
/// 無需新增 render 型別或 StageAssetId。位置一律從 `layout` 的 stage base 尺寸推導、對齊 0.5m grid。
enum StageStructurePreset: String, Codable, CaseIterable {
    case sideTowers          // 左右對稱一對垂直側塔（供側掛雷射/搖頭燈）
    case groundBoomStands    // 左右對稱一對地面 boom（矮垂直桁架）
    case midStageTruss       // 上舞台 portal 之外、往台前的第二道水平桁架 portal

    var displayName: String { … }   // 側塔一對 / 地面 Boom 架一對 / 中場桁架
}

extension StageLayout {
    /// 回傳該結構要加入的桁架段（未加入、未驗證——交給呼叫端逐件 `addObject`）。
    /// 依 stage base 的 width/depth/topY 推位置；側塔立於 x = ±(width/2 + sideMargin)、
    /// midStage 的 Z 落在 upstage portal 與台前之間。id 由呼叫端覆寫成唯一值（見 WI-2）。
    static func structurePresetObjects(_ preset: StageStructurePreset, in layout: StageLayout) -> [StageObject]
}
```

實作要點：
- 抽一個私有 helper `verticalTrussStack(atX:z:height:idPrefix:)`（沿用 `trussPortalPreset` 的 stacked-2m/封頂-1m while 迴圈、`rotation z=90`）給側塔/boom 共用；`midStageTruss` 則呼叫既有 `trussPortalPreset` 或組「兩腿 + 頂桿」。
- **側塔高度**建議 ~4m、x = `±(stageWidth/2 + 0.5)`、z ≈ 上舞台線與台中之間（如 `centerZ`）；**boom** 高度 ~1.5m、同 x、z 往台前；**midStage** 沿用 portal 但 `upstageZ` 換成更靠台前的 Z（如 `-(depth*0.1)`）。這些是初值，實機調。
- 全部座標推完後**四捨五入到 gridSize（0.5）**，避免 `snappedObject` 位移。

#### WI-2 `AppModel.swift` — 群組加法
新增（mirror `addStageObject`，`AppModel.swift:419-439`）：

```swift
/// 加入一個結構 preset 的所有桁架段（issue #27 (b)）。逐件產唯一 id → `layout.addObject`
/// （跑 snap+validate）→ 記 undo → persist → 選取最後一段（讓使用者立刻看到選取）。
func addStageStructure(_ preset: StageStructurePreset) {
    var layout = stageLayout
    let objects = StageLayout.structurePresetObjects(preset, in: layout)
    guard !objects.isEmpty else { return }
    let token = UUID().uuidString.prefix(6).lowercased()
    do {
        var lastId: String?
        for (i, proto) in objects.enumerated() {
            var obj = proto
            obj.id = "\(preset.rawValue)_\(token)_\(i)"
            obj.connectorIds = ["\(obj.id)_a", "\(obj.id)_b"]   // 與 trussSegment 工廠一致
            try layout.addObject(obj)
            lastId = obj.id
        }
        recordStageEditingUndoSnapshot()
        saveStageLayout(layout)
        selectedStageObjectId = lastId
    } catch {
        fail(error.localizedDescription)
    }
}
```
（`StageObject` 的 `id`/`connectorIds` 為 `var`，可覆寫——見 `StageBuilderModels.swift:930-939`。undo 目前是單快照 `StageEditingUndoStack`，一次群組加法記一次快照即可整組復原。）

#### WI-3 `TabletopStageEditorView.swift`（`#if os(visionOS)`，不在 smoke 集）— Menu 入口
在「新增桁架」Menu（`:278-283`）旁新增一個「新增結構」Menu（沿用 `.buttonStyle(.bordered)` / `.lumaGazeTarget()` / `.help(...)`、繁中）：

```swift
Menu {
    ForEach(StageStructurePreset.allCases, id: \.self) { preset in
        Button(preset.displayName, systemImage: "plus") { appModel.addStageStructure(preset) }
    }
} label: {
    Label("新增結構", systemImage: "square.stack.3d.up")
}
.buttonStyle(.bordered).lumaGazeTarget()
.help("加入側塔／地面 boom／中場桁架；拖近既有節點會自動對齊接上，之後把燈拖到結構下方即會吊掛")
```
（新結構是 `.trussSegment`，故 `selectedObjectTypeName`（`:565-572`）已回「桁架段」、`makeAssembly`（`:1062-1071`）已渲染、拖曳 node-snap 已生效——**這些都不需改**。）

#### WI-4 `Tests/LumaStageCoreSmokeTests.swift` — 新 smoke（記得在 `main()` 註冊）
新 `private static func stageStructurePresetsBuildTrussOnlyAndValidate() throws`：
```swift
let base = StageLayout.defaultStudentOutdoor()
for preset in StageStructurePreset.allCases {
    let objs = StageLayout.structurePresetObjects(preset, in: base)
    expect(!objs.isEmpty, "\(preset) 應產生至少一段桁架")
    expect(objs.allSatisfy { $0.type == .trussSegment }, "\(preset) 應全為 trussSegment（免費復用 renderer/snap/support）")
    // 併入 layout 後仍驗證通過（唯一 id 由 addStageStructure 覆寫；此處自行給唯一 id 後 addObject）
    var layout = base
    for (i, proto) in objs.enumerated() {
        var o = proto; o.id = "\(preset.rawValue)_test_\(i)"; o.connectorIds = ["\(o.id)_a", "\(o.id)_b"]
        try layout.addObject(o)
    }
    try layout.validate()
    // 側塔應擴大 footprint：加入後的 footprint 至少和加入前一樣寬（sideTowers 應更寬）
    let before = RigPlacement.trussFootprint(in: base)
    let after  = RigPlacement.trussFootprint(in: layout)
    expect(after != nil && before != nil, "應有桁架 footprint")
}
// 側塔對稱：左右 x 端點應鏡射（|minX| ≈ maxX）
let towers = StageLayout.structurePresetObjects(.sideTowers, in: base)
let xs = towers.flatMap(\.trussEndpoints).map(\.x)
if let mn = xs.min(), let mx = xs.max() {
    expect(abs(abs(mn) - abs(mx)) < 0.6, "側塔應左右對稱")
}
```
（`RigPlacement`/`StageLayout`/`Tests` 都已在 smoke 編譯集——**無需改 README 的 smoke 指令**。若加了新 Foundation-only 檔才要改；本 spec 沒有。）

---

## Constraints / 並行
- **單一 agent 序列**：(a) i-min → (b) WI-1→WI-4。`StageBuilderModels.swift` 兩部分都改、`Tests` 兩部分都改，必須同一 agent。
- **Foundation-only 邊界**：`StageStructurePreset` + `structurePresetObjects` 進 `StageBuilderModels.swift`（純幾何、smoke 覆蓋）；view 改動限 `#if os(visionOS)`。
- **不重寫／不動**：`RigPlacement.support`/`trussFootprint`/`clampedToTruss`/`resolvedPlacement` 的既有數學（(b) 靠它們**已通用**）、`RigPlacement.placement` 的 zone 擺位、`ImmersiveStageGeometryPlan.make`、`ImmersiveView.makeStageLayoutEntity`/`trussMember`、`TabletopStageScene.trussSegmentEntity`/`makeAssembly`、`validate()`、AI/`OpenAILightingService`、`MusicShowBuilder`、cue 編輯。
- **不新增** `StageObjectType`、render 分支、或 (b) 的 `StageAssetId`（新結構＝既有 truss 資產的組合）。
- 使用者字串繁體中文；(b) 新 UI 文案（Menu label/help/displayName）用繁中，設計 token（`.lumaGazeTarget()`/`.bordered`）沿用。
- (a) 遵守「既有 dead code 只提及不刪」——故建議只做 i-min（刪 `StageAssetId` 層死詞彙），i-full 的廣度刪除延後。

## Verification
- **smoke**：新 `stageStructurePresetsBuildTrussOnlyAndValidate` + (a) 修過的 `stageBuilderDropPlannerPlacesDraggedAssets` → `swiftc … -o /tmp/smoke && /tmp/smoke` 印 `LumaStageCoreSmokeTests passed`（用 README「共用 smoke 指令」，清單不變）。
- **完整 build**：`xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build` → `** BUILD SUCCEEDED **`（Multipeer 既有警告忽略）。
- **實機**：開專案 → 進「架設」桌面編輯器 → 「新增結構」選側塔 → diorama 出現左右對稱兩座垂直桁架、可拖曳且 node-snap 吸附；把一盞搖頭燈/雷射**拖到側塔下方** → 放手後該燈**吊掛在側塔**（無落地柱、不浮空）；中場桁架加入後、拖一盞燈到它下方也吊掛；1:1 舞台重開後結構與吊掛一致。(a)：控制列與 drop 都無任何 deck 入口（本就沒有），行為不變。

## Caveats
- **(b) 標為 L**：詞彙擴充本身不難，L 來自——(1) 側塔/boom/midStage 的高度/位置/朝向常數要**實機調**到讀起來像真結構且燈掛得穩；(2) 與**單一包圍盒 footprint** 的互動（footgun ①，兩塔間空檔誤判吊掛）需觀察；(3) node-snap 在小尺度 diorama 上把多段結構接準的手感。
- **側掛位靠 manual-drag，不靠 zone 自動**（footgun ④）：v1 使用者手動把燈拖到側塔下即吊掛。**延後**：讓 `RigPlacement.placement` 的 `stageLeft/stageRight` 在偵測到側塔時自動把側燈掛到塔上（新擺位邏輯，另開）；AI/音樂秀自動利用側塔同理延後。
- **per-structure footprint 延後**：目前所有 truss 端點合成一個 XZ 包圍盒。若實機發現兩塔間浮空明顯，未來把 footprint 改成「每個連通結構一個盒」再讓 `support` 取最近盒——非本 spec。
- **(a) i-full／選項 (ii) 延後**：本 spec 只做 i-min。若日後要徹底移除 `StageObjectType.stageDeck` 幾何（i-full）或把 deck 補成伸展台/thrust（選項 ii，可沿用已寫好的 `stageDeckAssembly`），另開 spec。
- **undo 為單快照**：一次「新增結構」記一次 `StageEditingUndoStack` 快照，可整組復原；連續多次加結構只保留最後一步的復原點（既有行為，不改）。
- **雷射**：雷射被 `enforcingTrussMountedLasers` 正規化到 `.stageBack`、`clampedToTruss` 夾進 footprint；側塔擴大 footprint 後，雷射可被夾/拖到含側塔的範圍。可見光束扇朝向不受本 spec 影響。
