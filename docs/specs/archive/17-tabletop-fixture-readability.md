# SPEC 17 — 舞台編輯器可讀性小包（issue #13 / #14 / #15 / #18）

> Status: done（實作完成、smoke 綠、完整 visionOS build `** BUILD SUCCEEDED **`；已封存）

**Goal**：把桌面舞台編輯器（「架設」階段 `TabletopStageEditorView`）的燈具代理從「五種型號都是同一個灰錐、選了也不知是哪盞、切 cue／改色不更新、拖進桁架不即時長柱」升級成可辨識、可操作、與 1:1 舞台一致。合併 #28 追蹤的**第一波「可讀性小包」**：#13（編號＋型號標籤 + 選取狀態顯示具體那盞）、#14（**bug**：代理鏡片顏色隨 cue／改色更新）、#15（拖曳中即時重算吊掛↔落地柱）、#18（一鍵複製所選燈具）。四項幾乎同檔（`TabletopStageEditorView.swift`），加 `AppModel` 一個新方法（#18）與 `LightingModels` 兩個可判定純函式（納入 smoke）。

> 風險控管：**可判定邏輯（標籤字串組法、複製燈具的欄位拷貝＋位移）下沉到 Foundation-only `LightingModels.swift` + smoke**；RealityKit 幾何／材質更新與 SwiftUI 按鈕是薄平台層。不新增檔案（全加進既有檔），故 **smoke 編譯集清單不變**。

## Ground truth（已存在、沿用而非重寫）

- **燈具代理 + 同步**：`TabletopStageScene.syncFixtures(_:look:layout:selectedFixtureId:)`（依 id reconcile：刪除消失的、新增新的、重定位存活的；取 selected cue else first 的 `fixtureGroups`）、`makeFixtureProxy(named:hex:)`（建錐體 body + emissive 鏡片 + 隱藏選取環，**鏡片目前無名、只在建立時上色一次**——即 #14 bug 根因）、`syncFixtureStand(in:position:layout:)`（`private static`，依 `RigPlacement.support` 增/減 `fixture_stand` 子圓柱，**目前只在 `syncFixtures` 呼叫**——即 #15 缺口）、`scenePoint`/`sceneToMeters`/`sceneLength`/`fixtureContainer(of:)`/`fixtureId(of:)`/`material(hex:)` — `TabletopStageEditorView.swift`。
- **拖曳**：`moveDrag`（`DragGesture().targetedToAnyEntity()`）——fixture 分支在 `.updating` 只更新 `fixtureContainer.position`（XZ free、Y 保留），`.onEnded` 呼 `appModel.moveFixture(id:toX:y:z:)`。`.updating` 已呼叫 `TabletopStageScene.updateSnapIndicator(...)`（同 `static` 呼叫慣例，#15 就照這個模式加一行 stand 重算）— `TabletopStageEditorView.swift`。
- **控制列**：`controlBar` HStack —— 已有「新增燈具」Menu（`appModel.addFixtureToRig(model:zone:.stageFront)`）、「刪除所選燈具」（`removeSelectedFixture()`，`.disabled(selectedFixtureId == nil)`），全用 `.buttonStyle(.bordered)`/`.buttonBorderShape(.circle)`/`.lumaGazeTarget()`/`.help`/繁中 a11y。`selectionStatus`（可見膠囊，**目前只反映 `selectedObjectTypeName`（桁架/deck），選到燈具時顯示「未選取物件」**）、`selectedFixtureAccessibilityValue`（**目前寫死「已選取一盞燈具」**）、`rigIsFull`、`addableFixtureModels`、`fixtureModelName(_:)`（`LightingFixtureCatalog.item(for:)?.displayName ?? model.rawValue`） — `TabletopStageEditorView.swift`。
- **AppModel fixture 方法（rig identity 範本，全走 `replaceLightingLook`→validate→`persistCurrentProjectState`）**：`addFixtureToRig(model:zone:)`（cap `maxRigFixtureCount=12`、laser 走 `mountsOnTrussOnly` 強制 `.stageBack`、新 id `fixture_<6hex>`、append 到**每個** cue、選取新燈）、`moveFixture(id:toX:y:z:)`（laser 用 `RigPlacement.clampedToTruss(_:layout:)` 夾回桁架）、`removeSelectedFixture()`、`selectFixture(id:)`、`selectedFixtureId`（於 `openProject`/`generate` 清空） — `AppModel.swift`。
- **模型**：`FixtureGroup`（**所有欄位皆 `var`**，含 `id`；含 `color: FixtureColor`、`intensity`、`model: LightingFixtureVisualModel?`、`role`、`zone`、`enabled`、`fineControl`、`effect: LightEffect?`、`manualPosition: FixturePosition?`、`aimOffset: FixtureAimOffset?`、`renderModel`）、`FixturePosition{x,y,z: Double}`、`StageLightLabel.displayName(number:) -> "Light \(number)"`（燈號＝fixture 在 cue `fixtureGroups` 的 **index+1**，見 `RelightDebugSnapshot.make` 的 `number = index + 1`） — `LightingModels.swift`。
- **catalog API**：`LightingFixtureCatalog.item(for: LightingFixtureVisualModel) -> LightingFixtureCatalogItem?`，`LightingFixtureCatalogItem.displayName: String` — `LightingFixtureCatalog.swift`。
- **1:1 舞台標籤作法（參考，不共用私有符號）**：`ImmersiveView.makeLabelEntity(_:)`（RealityKit `MeshResource.generateText` + `UnlitMaterial(.white)` + 深色 backing plane，recenter 於 bounds.center）、`addLightLabel(number:near:mountedAbove:to:)`（吊掛燈標籤下移避桁架）。**注意**：那是 1:1 世界（font 0.12m），桌面 diorama 是 `scale 0.07` 的微縮，字級要小很多（見 WI）。
- **支撐守則（SPEC 15，已 smoke）**：`RigPlacement.support(forPosition:layout:) -> FixtureSupport{ .hangFromTruss, .floorStand(topY:) }`，`FixtureSupport.isFloorStand`。

**Footgun**：
- **每 cue 顏色不同**：`FixtureGroup.color`/`intensity` 是**逐 cue**，`manualPosition`/`aimOffset`/`model`/`role`/`zone` 是 **rig identity（跨 cue 相同）**。#14 要顯示「**目前 cue**」的色——`syncFixtures` 已用 selected cue（else first）取 `fixtures`，鏡片色就從那組取，天然正確。#18 複製要**逐 cue 各自複製該 cue 的色/亮度**（保留每 cue 差異），而非把某一 cue 的狀態灌到所有 cue。
- **標籤編號同源**：桌面標籤與選取狀態的編號＝該 fixture 在 `syncFixtures` 逐一走訪 `fixtures` 的 **index+1**（＝ 1:1 舞台 `Light N`、語音 `LightCommand` 的同一號），三邊才對得起來。**不要**用 `fixtureGroups.count` 或 UUID。
- **Observation**：`syncFixtures` 跑在 `RealityView` 的 `update:` closure；`body` 已 eager-read `lightingLook`+`selectedFixtureId`，故 #13 標籤／#14 鏡片色在 look 變動時會重跑——**不需**再加 eager-read。#15 在手勢 closure（非 update:），無此問題。
- **不改 catalog displayName**：#13 例子「LED PAR 染色燈」只是示意；`.ledPar` 目前 catalog 名是「LED PAR 燈」。**維持現名**（改共用 catalog 超出本 spec）——標籤顯示 `item(for:)?.displayName` 回什麼就用什麼。
- **`private` → `static`**：#15 需在手勢 closure 呼叫 `syncFixtureStand`，把它的 `private static` 改成 `static`（同檔 `TabletopStageScene` enum，其餘 `static` 方法皆 internal）。

## Work items

### WI-1 — Foundation 可判定核心（owner：`LightingModels.swift`，**在 smoke 集**）

1. `StageLightLabel` 加標籤字串組法：
   ```swift
   enum StageLightLabel {
       static func displayName(number: Int) -> String { "Light \(number)" }
       /// 桌面代理／選取狀態用的標籤：可定址編號 + 燈具繁中型號名，例如 "3 · 搖頭光束燈"。
       /// 與 1:1 舞台的 `Light N` 同一編號（cue 順序 index+1）。型號名由呼叫端從 catalog 取後傳入。
       static func tabletopLabel(number: Int, modelName: String) -> String { "\(number) · \(modelName)" }
   }
   ```

2. `FixtureGroup` 加純複製方法（供 #18）：
   ```swift
   extension FixtureGroup {
       /// 「複製此燈具」用的拷貝：換上新 `id`，其餘視覺/朝向狀態（color/intensity/model/role/zone/enabled/
       /// fineControl/gobo/dmx/target/effect/aimOffset）全數保留；若來源有明確 `manualPosition`，把該位置
       /// 沿 X/Z 位移 (dx,dz) 模型公尺，避免複製體與原件完全重疊。來源 `manualPosition == nil`（zone 推算）
       /// 則維持 nil——靠 zone slot 分散兩者。`name` 維持與來源相同（呼叫端可另行覆寫編號）。
       func duplicated(newId: String, nudgeX dx: Double, nudgeZ dz: Double) -> FixtureGroup {
           var copy = self
           copy.id = newId
           if let pos = manualPosition {
               copy.manualPosition = FixturePosition(x: pos.x + dx, y: pos.y, z: pos.z + dz)
           }
           return copy
       }
   }
   ```

- smoke（2 條，皆註冊進 `Tests/LumaStageCoreSmokeTests.swift` 的 `main()`）：
  1. `tabletopLabelFormatsNumberAndModel` — `StageLightLabel.tabletopLabel(number: 3, modelName: "搖頭光束燈") == "3 · 搖頭光束燈"`；`displayName(number: 3) == "Light 3"`（回歸）。
  2. `duplicatedFixtureCopiesStateAndOffsetsManualPosition` —
     - 建一個帶 `manualPosition`（如 x=1,y=4,z=-2）、`aimOffset`、`effect`、非白 `color`、`intensity=0.42`、`model=.movingHeadBeam` 的 `FixtureGroup`；`let dup = src.duplicated(newId: "fixture_dup", nudgeX: 0.5, nudgeZ: 0)`。
     - 驗：`dup.id == "fixture_dup"`、`dup.id != src.id`；`dup.color == src.color`、`dup.intensity == src.intensity`、`dup.model == src.model`、`dup.role == src.role`、`dup.zone == src.zone`、`dup.aimOffset == src.aimOffset`、`dup.effect == src.effect`；`dup.manualPosition == FixturePosition(x: 1.5, y: 4, z: -2)`。
     - 第二例：`manualPosition == nil` 的來源 → `dup.manualPosition == nil`。

### WI-2 — AppModel：複製所選燈具（owner：`AppModel.swift`）（#18）

- 新 `func duplicateSelectedFixture()`，鏡射 `addFixtureToRig` 的 rig-identity 寫法（append 到**每個** cue、`replaceLightingLook`→persist、選取新燈）：
  ```swift
  /// 複製目前選取的燈具：新 id、逐 cue 保留該 cue 的色/亮度、位置沿 X 位移一小段（雷射夾回桁架），
  /// 寫回每個 cue、re-validate + persist，並選取新燈。滿 `maxRigFixtureCount` 時拒絕。
  func duplicateSelectedFixture() {
      guard let sourceId = selectedFixtureId else { return }
      var look = stageState.lightingLook
      guard let largest = look.cues.map(\.fixtureGroups.count).max(),
            largest < Self.maxRigFixtureCount else {
          fail("燈具數量已達上限（\(Self.maxRigFixtureCount) 盞），無法再複製。")
          return
      }
      let newId = "fixture_\(UUID().uuidString.prefix(6).lowercased())"
      let newName = "燈具 \(largest + 1)"
      var duplicatedAny = false
      for cueIndex in look.cues.indices {
          guard let src = look.cues[cueIndex].fixtureGroups.first(where: { $0.id == sourceId }) else { continue }
          var dup = src.duplicated(newId: newId, nudgeX: 0.5, nudgeZ: 0.0)
          dup.name = newName
          // 雷射只能掛桁架：位移後夾回 footprint（與 moveFixture 同一套規則）。
          if RigPlacement.mountsOnTrussOnly(dup.renderModel), let pos = dup.manualPosition {
              let clamped = RigPlacement.clampedToTruss(Vector3Meters(x: pos.x, y: pos.y, z: pos.z), layout: stageLayout)
              dup.manualPosition = FixturePosition(x: clamped.x, y: clamped.y, z: clamped.z)
          }
          look.cues[cueIndex].fixtureGroups.append(dup)
          duplicatedAny = true
      }
      guard duplicatedAny else { fail("找不到要複製的燈具。"); return }
      do {
          try stageState.replaceLightingLook(look)
          persistCurrentProjectState()
          selectedFixtureId = newId
      } catch {
          fail(error.localizedDescription)
      }
  }
  ```
- **不動** 其他 AppModel 方法。`fail`/`Self.maxRigFixtureCount`/`RigPlacement`/`Vector3Meters`/`FixturePosition` 皆既有。

### WI-3 — 桌面編輯器：標籤 + 選取狀態 + 鏡片色 + 拖曳長柱 + 複製鈕（owner：`TabletopStageEditorView.swift`）

**（A）#14 鏡片色隨 cue／改色更新**
- `makeFixtureProxy` 建立的 emissive 鏡片 `ModelEntity` 目前**無名**——給它固定名字 `"fixture_lens"`。
- `syncFixtures` 每次更新（重用既有 container 的那段）除了位置/選取環外，另取該 fixture **目前 cue** 的色（就是迴圈用的 `fixture.color.value`），重設鏡片 `UnlitMaterial`：`(container.findEntity(named: "fixture_lens") as? ModelEntity)?.model?.materials = [ 以 fixture.color.value 建的 UnlitMaterial(.opaque) ]`（沿用 `makeFixtureProxy` 內既有的 `RGBComponents(hex:)`→`UIColor` 作法；可抽一個 `private static func lensMaterial(hex:) -> UnlitMaterial` 供建立與更新共用）。

**（B）#13 浮動編號＋型號標籤**
- 每個 fixture proxy 下掛一張浮動標籤（RealityKit `generateText`，比照 `ImmersiveView.makeLabelEntity` 的白字＋深色 backing，但字級縮到 diorama 尺度）。字串 = `StageLightLabel.tabletopLabel(number: slotIndexInFixturesArray + 1, modelName: LightingFixtureCatalog.item(for: fixture.renderModel)?.displayName ?? fixture.renderModel.rawValue)`。
  - **編號**＝該 fixture 在 `syncFixtures` 走訪 `fixtures` 的 index+1（在既有 `for fixture in fixtures` 迴圈裡改用 `for (index, fixture) in fixtures.enumerated()` 取得），與 1:1 舞台 `Light N` 同源。
  - **字級/位置**：字級約 `0.018`–`0.03`（label 於未縮放的 assembly 空間，非 1:1 世界；起始值，實機微調記 Caveat）；標籤置於 body 上方約 `sceneLength(0.4)`。
  - **面向使用者**：turntable 會轉，固定 +Z 會轉走——給標籤容器加 RealityKit `BillboardComponent()` 使其恆面向相機（若該 API 在專案 SDK 不可用，退回固定 +Z 並記 Caveat）。
  - **reconcile**：標籤字串會隨編號（增刪燈導致 index 位移）或型號改變。實作為 `syncFixtures` 每次把標籤字更新到目前 want 值，且**僅在字串變動時**重建 text mesh（避免每次 update 重建 12 個 text mesh）——建議把 want 字串編進標籤子實體名字（如 `"fixture_caption_<want>"`），存在即最新、不存在則移除舊 `fixture_caption_*` 並重建；容器名固定 `"fixture_label"` 供 `findEntity` 定位。
- 標籤不需 `InputTargetComponent`/collision（不可選、不擋燈具 hit-test）。

**（C）#13 選取狀態顯示具體那盞**
- 新增 `private var selectedFixtureLabel: String?`：當 `appModel.selectedFixtureId != nil` 時，於目前 cue（selected else first）的 `fixtureGroups` 找 index → 回 `StageLightLabel.tabletopLabel(number: index+1, modelName: <catalog displayName>)`；否則 nil。
- `selectionStatus`（可見膠囊）：**燈具與物件互斥**，優先顯示燈具——`selectedFixtureLabel` 非 nil → 顯示「已選取：燈具 N（型號）」（可沿用 `tabletopLabel` 結果組成，如 `"已選取：\(label)"`）；否則回退既有 `selectedObjectTypeName` 邏輯；兩者皆無 → 「未選取」。symbol：有選取（任一）用 `checkmark.circle.fill`（`coolBlue`），無用 `hand.tap`（`textSecondary`）。`.accessibilityElement(.combine)` label 同步。
- `selectedFixtureAccessibilityValue`：由「已選取一盞燈具」改為 `selectedFixtureLabel.map { "已選取 \($0)" } ?? "尚未選取燈具"`。

**（D）#15 拖曳中即時重算吊掛↔落地柱**
- 把 `TabletopStageScene.syncFixtureStand` 的 `private static` 改 `static`（供手勢 closure 呼叫）。
- `moveDrag` 的 `.updating` fixture 分支，設好 `fixtureContainer.position` 後加一行：以當前位置換算模型公尺呼叫 stand 重算——
  ```swift
  fixtureContainer.position = SIMD3<Float>(target.x, fixtureContainer.position.y, target.z)
  TabletopStageScene.syncFixtureStand(in: fixtureContainer,
                                      position: TabletopStageScene.sceneToMeters(fixtureContainer.position),
                                      layout: appModel.stageLayout)
  return
  ```
  （拖曳中 Y 保留，故柱高不變、變的是 `.hangFromTruss`↔`.floorStand` 的柱子出現/消失，與放手後 `syncFixtures` 一致。）

**（E）#18 複製鈕**
- `controlBar` 於「刪除所選燈具」旁加一顆「複製所選燈具」（`systemImage: "plus.square.on.square"`，`.labelStyle(.iconOnly)`、`.buttonStyle(.bordered)`、`.buttonBorderShape(.circle)`、`.lumaGazeTarget()`）：
  - action `appModel.duplicateSelectedFixture()`；`.disabled(appModel.selectedFixtureId == nil || rigIsFull)`；`.help` / `.accessibilityLabel("複製所選燈具")` / `.accessibilityHint`（未選取或已達上限時說明不可用）/ `.accessibilityValue(selectedFixtureAccessibilityValue)`。

## Constraints / 並行
- **一份 spec、單一 agent、依序改四檔**（`LightingModels.swift` → `AppModel.swift` → `TabletopStageEditorView.swift` → `Tests/…`）；跨檔契約以本 spec 釘死（`tabletopLabel`、`FixtureGroup.duplicated`、`duplicateSelectedFixture`）。四檔耦合緊、量不大，不拆平行以免整合風險。
- **不動** 1:1 `ImmersiveView`（標籤作法只參考、桌面自建微縮版）、AI 生成路徑、`LightingFixtureCatalog` 的 `displayName` 資料、smoke 編譯集清單（無新檔）。
- 使用者字串繁中；設計 token `LumaStageDesign`（`textPrimary`/`textSecondary`/`coolBlue`）；新按鈕補繁中 `accessibilityLabel`/hint/value、`lumaGazeTarget()`（≥60pt）。Reduce Motion 不涉（無新動畫；BillboardComponent 是持續朝向、非入場動畫）。
- `#if os(visionOS)` 守衛照舊（整個 `TabletopStageEditorView.swift` 已在其中）。

## Verification
- smoke（repo root，指令同 README「smoke 編譯集」——**清單不變**）→ `LumaStageCoreSmokeTests passed`（含 WI-1 兩條新測試、既有全綠不回歸）。
- 完整 build：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build` → `** BUILD SUCCEEDED **`（Multipeer `Sendable`、MCSession 簽名含 `error:` 字樣為既有非錯誤，忽略）。
- 磁碟：本機資料卷常近滿，build ENOSPC 時清 `~/Library/Caches` 釋放空間（約 900MB，足一次乾淨 build）。

## Caveats（實機/刻意延後）
- 標籤字級（0.018–0.03）、上方偏移（`sceneLength(0.4)`）、`BillboardComponent` 在此 SDK 是否可用/朝向是否正確、深色 backing 在 passthrough 下對比，皆需在實機／模擬器 diorama 上微調。
- #18 複製位移固定 X+0.5m：來源無 `manualPosition`（純 zone）時複製體亦無 manualPosition，靠 zone slot 分散（整個 zone 會重新分佈，原件可能微幅位移，可接受）；雷射複製體位移後夾回桁架，可能與原件貼很近（桁架寬度有限），實機看是否需加大位移或改夾另一端。
- #15 拖曳中僅切換 hang↔stand（Y 不變故柱高不變）；跨「離地高度」門檻的即時反饋不在本波（屬 #19 高度控制）。
- 標籤 reconcile 以「字串變動才重建 text mesh」為準；`update:` 由 Observation 驅動（非每幀），成本可接受。
- AI 重生成會換掉整個 rig（同 `manualPosition`/`lightOverrides`），故複製/標籤/手動位置不跨生成保留——v1 一致行為，非本 spec 範疇。
