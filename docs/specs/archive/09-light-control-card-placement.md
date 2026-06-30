# SPEC 09 — 單燈控制卡:就近顯示 + 可移動

**Goal**：選取舞台上的燈時,手動控制卡(`SelectedLightControlView` 的 attachment)目前**寫死在正前方** `(0, 1.2, -1.0)` 且**每幀重設**位置。改成:① 卡片出現在**剛選取的那盞燈附近**(就是使用者正看著的東西旁邊),且夾到**伸手可及**的高度;② 卡片**可抓著移動**,移動後不被每幀彈回。對應「頭顯內就地手動控燈」的完成度,直接服務決賽「評委動手體驗」(strategy §5 Q6)。

> ⚠️ **檔案擁有權**:本 spec **只動 `ImmersiveView.swift`**(可選新增一個 Foundation-only 純函式檔)。`ImmersiveView.swift` 同時是其他 spec(效果/無障礙)會碰的熱點檔 —— **派工前確認沒有別的 agent 正在改它**(README「並行分派守則」:同檔只給一個 agent)。

## Ground truth（呼叫/沿用,勿重寫）
- 控制卡 = RealityView **Attachment**,`ImmersiveView.lightControlCardID = "lightControl"`、`lightControlCardName = "light_control_card"`,parent 為 `root`(在 `make:` ~L55 與 `update:` ~L85 兩處 add/重新 parent)。
- `ImmersiveView.updateLightControlCard(_ card: Entity, selectedLightNumber: Int?)`（~L788）:現為 `card.isEnabled = (selectedLightNumber != nil)`、`card.position = SIMD3<Float>(0, 1.2, -1.0)`（**要改的就是這裡 + 它每幀被呼叫的事實**）。
- 每盞燈的 pick proxy：`addLightPickTarget(number:near:to:)` 建出 `lightpick_<n>`,位於 `scenePoint(position) + SIMD3(0, sceneLength(0.34), 0)`,是 `rig` 的子節點（`rig` 為 `root` 的子）。取它：`root.findEntity(named: "lightpick_\(n)")`;要 root 空間座標用 `proxy.position(relativeTo: root)`。
- `scenePoint(_)` / `sceneLength(_)`：**唯一**合法的 model-公尺↔scene 轉換(`stageScale == 1.0`)。
- `body` 已 `let _ = appModel.selectedLightNumber`（Observation footgun 已處理,**保留**）。
- 既有手勢勿破壞:`.gesture(SpatialTapGesture)` 選燈(~L105)、`.simultaneousGesture(DragGesture)` 捏拉調光(~L120,其 `onChanged` 對非 `lightpick_<n>` 實體會 `guard let n = lightNumber(forPickTarget:) else { return }` early-return)。
- 可抓移動的現成範式:`FixtureObservatoryView` 用 `ManipulationComponent.configureEntity(entity, collisionShapes:)` + `releaseBehavior = .stay`（`configureEntity` 會自動加 InputTarget/Collision/Hover）。

## Work items（單一 owner,可含下列兩檔）

### 1.（建議）`LightControlCardPlacement.swift`（新檔,Foundation-only + smoke）
把「就近 + 夾取」的座標規則抽成純函式,符合專案慣例並可 pin:
```
import Foundation
import simd
enum LightControlCardPlacement {
    // 把卡片放在「燈與使用者之間、伸手可及」處。
    static func position(lightWorld: SIMD3<Float>, viewer: SIMD3<Float>,
                         pullToViewer: Float = 0.4, minY: Float = 0.9, maxY: Float = 1.6,
                         sideOffset: Float = 0.18) -> SIMD3<Float>
}
```
- 規則:水平(x,z)從 `lightWorld` 朝 `viewer` 內插 `pullToViewer`;`y` 夾到 `minY...maxY`(高掛燈不會飄到 5m);`x` 加 `sideOffset` 避免正擋光束。係數為 `static let`/預設參數,**實機調**。
- smoke：高掛燈(y=5)→ 卡片 y 落在 0.9...1.6;水平確實朝 viewer 拉近;低燈不被往上抬過頭。加進 README 的 smoke 編譯指令 + 根 `CLAUDE.md` 測試段。
- 若 owner 不想新增檔,可把同規則寫成 `ImmersiveView` 的 `private static func`(但失去 smoke 覆蓋)。

### 2. `ImmersiveView.swift` — 就近放置(只放一次) + 可移動
- **就近、只放一次**:用 `@State private var cardPlacedForLight: Int?`。在 `update:`（或 `.onChange(of: appModel.selectedLightNumber)`）中,當 `appModel.selectedLightNumber != cardPlacedForLight`：
  - 若為 nil → `card.isEnabled = false`、`cardPlacedForLight = nil`。
  - 否則 → 取 `lightpick_<n>` 的 root-空間座標,經 work item 1 的 `position(lightWorld:viewer:)`(viewer 取原點 `SIMD3(0, 1.2, 0)` 或裝置位置)算出初始位置,`card.position = …`、`card.isEnabled = true`、`cardPlacedForLight = n`。
  - **selection 不變時,不要再覆寫 `card.position`**（這是目前彈回的根因)。
- **可移動**:`ManipulationComponent.configureEntity(card, collisionShapes: [ShapeResource.generateBox(...卡片尺寸...)])` + 取 `card.components[ManipulationComponent.self]?.releaseBehavior = .stay`(平移為主;若 configureEntity 預設含縮放/旋轉,限制成只平移或接受之)。或自加 `DragGesture().targetedToAnyEntity()` 分支:當 dragged entity 是卡片或其後代時更新 `card.position`(clamp 到可及範圍),否則交回既有調光 drag。
  - 不可破壞選燈 tap / 捏拉調光 drag:卡片不是 `lightpick_<n>`,既有調光 drag 會對它 early-return;但若用 ManipulationComponent,確認 attachment 仍收得到自身輸入。
- 換燈或重新選取同一盞 → `cardPlacedForLight` 改變 → 重新就近放置(覆蓋使用者上次拖到的位置,屬預期)。

## Constraints
- 只改 `ImmersiveView.swift`(+ 可選新 Foundation 檔)。**不改** `SelectedLightControlView` 內容、不改 `cue.transition`、不動既有手勢語意。
- 維持 Observation footgun 讀取;visionOS 平台守衛(檔已在 `#if os(visionOS)`)。

## Verification
- 完整 build → `** BUILD SUCCEEDED **`。
- 若做 work item 1：smoke 仍 `LumaStageCoreSmokeTests passed`(把新檔加進編譯集)。

## Caveats（實機調）
- `pullToViewer` / `minY..maxY` / `sideOffset` / ManipulationComponent vs DragGesture 的手感。
- viewer 用固定原點 vs 真實裝置位置(ARKit deviceAnchor)——固定原點較簡單且通常夠用;要更貼「看的方向」可後續用 deviceAnchor。
- `@State` 在 `update:` closure 寫入只在 selection 改變時發生(不會迴圈);若 agent 偏好,改用 `.onChange` 更穩。
