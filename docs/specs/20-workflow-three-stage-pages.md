# SPEC 20 — 工作流程三階段頁面：架設 / 編程 / 播放（issues #8 / #9 / #10）

> Status: proposed

## Goal

把 app 拆成三個明確的工作階段頁面，模仿真實燈光工作流程（先架燈、再編程、最後跑秀），呼應 MAIC「降低專業燈光設計門檻」的社會價值：

1. **架設（rigging）** — 重塑 `StageLayout` 與擺放/移動 rig 燈具（沿用既有 tabletop 編輯器，把「編輯舞台」從一顆按鈕升級成第一個工作階段）。
2. **編程（programming）** — 逐 cue 調整每盞燈的顏色/角度(`aimOffset`)/亮度；**燈具不可再移動位置**。
3. **播放（playback）** — 連續 cue-list 播放（沿用已出貨的 SPEC 16）＋一條播放進度時間軌。

三個 issue 是**同一個耦合功能**，本 spec 一次規劃、按 issue 切 Work items 以便日後分別分派。**依賴：#6 連續播放已由 SPEC 16（`CuePlayback`/`CuePlaybackEngine`）出貨——直接建構於其上，不重新規劃。**

**跨 WI 分派順序（硬性）**：`WI-8` 必須先落地（它建立 `workflowPhase` 來源狀態、`WorkflowPhasePolicy`、composer 分頁 UI 與 space 切換）。`WI-9`／`WI-10` 皆相依於 `WI-8` 已合併；且 `WI-8`／`WI-10` 都會動 `VisionAIComposerBox.swift`、`AppModel.swift`、`project.pbxproj`、smoke 檔——**序列分派、勿並行**（同檔一次一個 agent，見 README 並行守則）。`WI-9` 只動 `SelectedLightControlView.swift` + `LightingModels.swift`，與 `WI-10` 不衝突。

---

## Ground truth（既有、要「沿用/呼叫」而非重寫的 API/型別；附 file:symbol）

### 沉浸 space 切換（架設 ↔ 編程/播放 全靠它，勿另起 open 路徑）
- `AppModel.swift:48` `enum ImmersiveScene { case none, stage, tabletopEditor }`；`AppModel.swift:86` `var desiredImmersiveScene: ImmersiveScene = .none`。
- `AppModel.swift:344` `func enterTabletopEditing()` — 設 `selectedStageObjectId=nil`、`isEditingTabletopStage=true`、`desiredImmersiveScene = .tabletopEditor`。
- `AppModel.swift:352` `func exitTabletopEditing()` — `clearTabletopEditingState()`（`AppModel.swift:359`：清 `isEditingTabletopStage`/`selectedStageObjectId`/`selectedFixtureId`/undo stack）後設 `desiredImmersiveScene = .stage`。
- `ContentView.swift:52` `.task(id: appModel.desiredImmersiveScene) { await reconcileImmersiveScene() }`；`ContentView.swift:74` `private func reconcileImmersiveScene() async` — 等 `.inTransition`→`guard immersiveSpaceState == .closed`→依 scene 映射 `spaceID`（`.stage`→`appModel.immersiveSpaceID`；`.tabletopEditor`→`appModel.tabletopEditorSpaceID`）→ `openImmersiveSpace(id:)`＋`ImmersiveSceneReopenPolicy` backoff，耗盡則 `immersiveSpaceState=.closed`、`desiredImmersiveScene=.none`（退回 composer）。
- **既有兩步交接（勿破壞、要複製）**：`VisionAIComposerBox.swift:658` `openStageEditor()` = `guard !isEditingTabletopStage`→`enterTabletopEditing()`→若 space 開著則 `immersiveSpaceState=.inTransition`、`await dismissImmersiveSpace()`、`openWindow(id: AppModel.mainWindowID)`。`TabletopStageEditorView` 的「完成」(finishEditing) 是鏡像的返回路徑。**驅動 open 一律從主視窗（`ContentView`），dismiss 從離開的 space 的 caller/`onDisappear`（見根 `CLAUDE.md`「Tabletop stage editor」）。**

### 燈光狀態三層（#9 禁止發明第四層）
1. **recorded look**（per-cue `FixtureGroup`）— 走 `CuePatch` + rig-identity fixture 方法。
2. **`AppModel.lightOverrides: [Int: LightOverride]`**（暫態、依 1-based 燈號）。
3. **`AppModel.groupMasters`**（群組推桿）。
- `LightingModels.swift:1436` `enum CuePatch { frontLightDimmer / backgroundWashColor / fixtureIntensity(fixtureId:intensity:) / fixtureColor(fixtureId:hexColor:) / fixtureFineControl(fixtureId:control:) / roleColor(role:hexColor:) }`；`StageState.patchSelectedCue(_:)`（`LightingModels.swift:1475`，只動選取 cue、每次 mutate re-validate）。
- 呼叫 `patchSelectedCue` 的 AppModel 方法（recorded、per-cue、persist）：`setFixtureColor(id:hexColor:)`（`AppModel.swift:1603`）、`setFixtureIntensity(id:value:)`（`AppModel.swift:1588`）、`setFixtureFineControl(id:control:)`（`AppModel.swift:1629`）、`setFrontLightDimmer`、`setBackgroundWashColor`、`resetSelectedCue`（`AppModel.swift:1641`）。
- **注意**：`setManualIntensity(light:_:)`（`AppModel.swift:1446`）/`setManualColor`/`toggleManualOff` 寫的是 **`lightOverrides`（暫態、第 2 層）**，**不是** recorded cue。#9 的編程編輯要走**第 1 層**（`setFixtureColor`/`setFixtureIntensity`）。
- **角度**：`AppModel.rotateFixture(id:panDelta:tiltDelta:)`（SPEC 13）持久為 `FixtureGroup.aimOffset`，**rig identity——同 id 跨所有 cue 一起改**，且 `syncRig` signature 納入 `aimOffset` 才會真的重對準活舞台。`fineControl.pan/tilt` **不可**當角度用（會與 zone tilt 疊加、且不在 `syncRig` signature——不會重對準；見根 `CLAUDE.md`「Renderer footgun」）。

### 單燈控制卡（#9 沿用）
- `SelectedLightControlView.swift:11`（`#if os(visionOS)`）：僅在 `appModel.selectedLightNumber` 有值時顯示 `card`；列 = `header`(X→`selectLight(number: nil)`)、`onOffRow`(`toggleManualOff`)、`dimmerRow`（連續 `Slider(0...1)`→`setManualIntensity` + 5 顆 preset）、`colorRow`（10 色 swatch→`setManualColor`）、`followCueButton`（`clearManualOverride`）。**目前無角度控制**。
- 單例 `Window("燈光控制", id: AppModel.lightControlWindowID)`（`LumaStageApp.swift:75`，`.plain`/`.utilityPanel`）；`ImmersiveView` 以 `.onChange(of: selectedLightNumber, initial: true)` 開關。
- 燈號↔fixture 對應：燈是「`fixtureGroups` 順序 Light 1…N」（見根 `CLAUDE.md`「Shared stage geometry」）。

### 連續播放（SPEC 16，#10 建構於此、勿重做）
- `CuePlayback.swift`：`holdDuration(for: LightingCue) -> Double`（`:27`，nil/非有限→預設 6s，鉗 1.5–600s）、`nextIndex(after:count:) -> Int?`（`:36`，不迴繞）、`canAutoPlay(cueCount:) -> Bool`（`:43`，≥2）。
- `LightingModels.swift:411` `LightingCue.holdDuration: Double?`；`LightingModels.swift:83` `CueTransition.duration`；`LightingModels.swift:413` `LightingCue.localizedDisplayName`（Opening→開場、Highlight→重點）。
- `CuePlaybackEngine.swift:17`（`@MainActor @Observable`，非 smoke）：`onFollow: (() -> Double?)?`、`start(initialHold:)`、`stop()`。**勿改其內部**。
- `AppModel`：`isPlayingCueList`（`:194`）、`isShowRunning { isMusicPlaying || isPlayingCueList }`（`:995`）、`playCueList()`（`:1000`）、`stopCueList()`（`:1028`）、`togglePlayback()`（`:1035`）、`playMusicShow()`/`stopMusicShow()`/`clearMusicShow()`、`goToNextCue()`（`:1331`，播放中呼 `rescheduleCuePlaybackIfPlaying()`）、`selectCue(id:)`（`:1548`）、`selectedCueId`（`:245`）、`selectedCue`（`:249`）。
- 音樂進度：`MusicSyncEngine.swift:73` `private(set) var currentTime: Double`（30 Hz tick，`:95` `tickInterval = 1/30`）、`onSectionBoundary: ((Int) -> Void)?`（`:84`）。段落資料：`SongAnalysis.swift:33` `SongSection { start, end, kind, pace, loudness, keyMode, dominantInstruments; duration { end-start } }`；`SongAnalysis.swift:47` `SongAnalysis.sections: [SongSection]`（依 start 排序、不重疊）。

### iPad 連線（#8 鏡射）
- `LumaSyncProtocol.swift:52` `LumaHostState { conversation, lighting, immersionMode, isPlayingCueList=false }`（選取 cue 在 `lighting.selectedCueId`，`LumaHostState` 無獨立欄位）。
- `LumaSyncProtocol.swift:101` `enum LumaControlCommand`（含 `selectCue(id:)`、`goToNextCue`、`playCueList`、`stopCueList`…，1:1 對應 `AppModel`）。
- `LumaSyncCoordinator.swift`（visionOS）：`withObservationTracking` 觀察 `AppModel`、任一變更 republish 全量 `LumaHostState`；inbound command 呼 `AppModel`。
- `iPadPanel/PanelRootView.swift:10` `enum PanelTab { chat, lighting }`（TabView，開在 lighting）；`iPadPanel/LumaPanelModel.swift`：`host: LumaHostState?`、`send(_ command: LumaControlCommand)`（`:75`）。
- **新增共用檔要進 iPad target membership 例外清單**（見根 `CLAUDE.md`「iPad control panel」），否則 panel build 壞。

### Composer 頂部（#8 動、#10 嵌時間軌）
- `VisionAIComposerBox.swift:73` `topBar`（HStack）：`Button("編輯舞台", …, action: openStageEditor)`（`:75`）、`Button("音樂")`（`:80`）、`Spacer`、`燈光除錯`（`:91`）。播放/停止＋GO 在 `cueStrip`（`:106`）：`Button(isShowRunning ? "停止":"播放") { togglePlayback() }`（`:130`）、`Button("GO") { goToNextCue() }`（`:142`）。`toggleStageImmersion` 在 `controlRow`（`:269`）。
- 設計 token：`LumaStageDesign`（`lumaGazeTarget`、`minGazeTarget=60`、`lumaFloatingPanel`、tints）。Reduce Motion gate、Dynamic Type 見 README 共用慣例。

### smoke 骨架
- `Tests/LumaStageCoreSmokeTests.swift`：`@main`，`static func main() async throws` 內**逐行呼叫** `private static func` 測試（無自動發現，新測試要在 `main()` 註冊）。helper：`expect(_ condition: @autoclosure () -> Bool, _ message: String)`（`:3111`）、`expectThrows`（`:3117`）、`expectUnwrapped`（`:3128`）。已存在可擴充：`lumaSyncProtocolRoundTrips()`。

---

## Work items

### WI-8 — 三階段骨架 + 階段 policy（issue #8）

**擁有檔**：`LumaStage/WorkflowPhase.swift`（新，Foundation-only）、`LumaStage/AppModel.swift`、`LumaStage/VisionAIComposerBox.swift`、`LumaStage/TabletopStageEditorView.swift`、`LumaStage/LumaSyncProtocol.swift`、`LumaStage/LumaSyncCoordinator.swift`、`LumaStage/iPadPanel/PanelRootView.swift`（+ 必要時 `LumaPanelModel.swift`）、`Tests/LumaStageCoreSmokeTests.swift`、`LumaStage.xcodeproj/project.pbxproj`、`docs/specs/README.md` + 根 `CLAUDE.md`（smoke 清單）。

**8a. Foundation-only 階段 + policy（`WorkflowPhase.swift`，進 smoke 集）**
```swift
import Foundation

enum WorkflowPhase: String, Codable, CaseIterable, Equatable {
    case rigging       // 架設
    case programming   // 編程
    case playback      // 播放
    var localizedDisplayName: String { switch self {
        case .rigging: "架設"; case .programming: "編程"; case .playback: "播放" } }
    var systemImageName: String { switch self {   // SF Symbols，供分頁 UI
        case .rigging: "square.stack.3d.up"; case .programming: "slider.horizontal.3"; case .playback: "play.rectangle.on.rectangle" } }
}

enum WorkflowPhasePolicy {
    static func allowsFixtureMove(in phase: WorkflowPhase) -> Bool { phase == .rigging }
    static func allowsStageLayoutEdit(in phase: WorkflowPhase) -> Bool { phase == .rigging }
    static func allowsTabletopPlacement(in phase: WorkflowPhase) -> Bool { phase == .rigging }
    static func allowsCueEditing(in phase: WorkflowPhase) -> Bool { phase == .programming }   // 顏色/角度/亮度
    static func allowsCueJump(in phase: WorkflowPhase) -> Bool { phase == .programming || phase == .playback }
    static func showsPlaybackTimeline(in phase: WorkflowPhase) -> Bool { phase == .playback }
    static func usesTabletopEditorSpace(in phase: WorkflowPhase) -> Bool { phase == .rigging }  // AppModel 用它決定映射到哪個 ImmersiveScene
}
```
`WorkflowPhase` 是純資料，**不**引用 `AppModel.ImmersiveScene`（保持 Foundation-only、可 headless 測）；由 AppModel 把 `usesTabletopEditorSpace` 映射到 `.tabletopEditor`/`.stage`。

**8b. AppModel 來源狀態 + 切換（`AppModel.swift`）**
- 新 `var workflowPhase: WorkflowPhase = .programming`（開專案落在 1:1 舞台＝編程；預設不設 rigging，理由見 Caveats）。
- 新 `func setWorkflowPhase(_ phase: WorkflowPhase)`（**只更新 model 與 `desiredImmersiveScene`，實際 space swap 的 dismiss 由 view 做——見 8c**）：
  ```swift
  func setWorkflowPhase(_ phase: WorkflowPhase) {
      guard phase != workflowPhase else { return }
      if workflowPhase == .playback, isPlayingCueList { stopCueList() }  // 離開播放頁停自動走場
      switch phase {
      case .rigging:
          if isEditingTabletopStage { workflowPhase = .rigging }
          else { enterTabletopEditing() }        // 設 desired=.tabletopEditor（見 8b 修改）
      case .programming, .playback:
          if isEditingTabletopStage { exitTabletopEditing() }  // 設 desired=.stage
          workflowPhase = phase
      }
  }
  ```
- **修改** `enterTabletopEditing()`：末尾加 `workflowPhase = .rigging`。
- **修改** `exitTabletopEditing()`：加 `if workflowPhase == .rigging { workflowPhase = .programming }`（讓「用系統 chrome 關掉編輯 space→`TabletopStageEditorView.onDisappear` 再呼 `exitTabletopEditing()`」也把階段拉回編程）。
- **修改** `openProject(id:)`：加 `workflowPhase = .programming`（與既有 `desiredImmersiveScene = .stage` 同處）。
- **修改** `closeProject()`：加 `workflowPhase = .programming`（reset）。
- **guard（belt-and-suspenders，強制「編程/播放禁止移動」）**：在 `moveFixture`、`addFixtureToRig`、`duplicateSelectedFixture`、`mirrorSelectedFixture`、`removeSelectedFixture` 開頭加 `guard WorkflowPhasePolicy.allowsFixtureMove(in: workflowPhase) else { return }`；在 `addStageObject`、`moveStageObject`、`removeSelectedStageObject`、`rotateSelectedStageObject` 開頭加 `guard WorkflowPhasePolicy.allowsStageLayoutEdit(in: workflowPhase) else { return }`。（tabletop 編輯期間 `workflowPhase==.rigging`，guard 放行；UI 本就只在架設頁露出這些操作，guard 擋的是 iPad/語音等程式路徑。）

**8c. Composer 分頁 UI（`VisionAIComposerBox.swift`）**
- 在 box 最上方（`topBar` 之上或取代其中的「編輯舞台」）加三段式階段切換 `workflowPicker`：三顆 `lumaGazeTarget`（≥60pt）或 `Picker(.segmented)`，顯示 `WorkflowPhase.allCases` 的 `localizedDisplayName`＋`systemImageName`，選取態綁 `appModel.workflowPhase`。
- **移除**獨立的「編輯舞台」按鈕（`:75`）——功能併入「架設」段。
- 新 async `switchPhase(to target:)`（複製 `openStageEditor` 交接模式；`dismissImmersiveSpace`/`openWindow` 是 view 的 `@Environment` action，必須在 view 做）：
  ```swift
  @MainActor func switchPhase(to target: WorkflowPhase) async {
      let needsSpaceSwap = WorkflowPhasePolicy.usesTabletopEditorSpace(in: appModel.workflowPhase)
                        != WorkflowPhasePolicy.usesTabletopEditorSpace(in: target)
      appModel.setWorkflowPhase(target)   // 更新 model + desiredImmersiveScene
      if needsSpaceSwap {
          appModel.immersiveSpaceState = .inTransition
          await dismissImmersiveSpace()
          openWindow(id: AppModel.mainWindowID)   // 冪等重開（同 openStageEditor 第二道防線）
      }
  }
  ```
  程式↔播放 `needsSpaceSwap==false`→僅 model 更新、即時無 swap；架設→`needsSpaceSwap==true`→複製既有 `openStageEditor` 行為（reconcile 之後開 tabletop space）。
- Composer body 是一般 SwiftUI view（非 `RealityView update:` closure），讀 `appModel.workflowPhase` 於 body 內即成 Observation 依賴，無 footgun。

**8d. Tabletop 控制列分頁 UI（`TabletopStageEditorView.swift`）**
- 架設頁時 composer 視窗被關（見根 `CLAUDE.md`：composer 於 `ImmersiveView.onAppear/onDisappear` 開關，架設是另一個 space），因此**返回編程/播放的入口必須也在 tabletop**。在 tabletop 控制列 attachment 加同一個三段式 `workflowPicker`（架設段為 active）；選「編程/播放」呼叫本 view 自己的 `switchPhase(to:)`（同 8c 模式，複製既有 `finishEditing` 的 dismiss→`openWindow(mainWindowID)`）。既有「完成」按鈕維持（也走 `exitTabletopEditing`→編程）。

**8e. iPad 鏡射（`LumaSyncProtocol.swift` / `LumaSyncCoordinator.swift` / `iPadPanel/`）**
- `LumaHostState` 加 `var workflowPhase: String = WorkflowPhase.programming.rawValue`（additive；wire 型別對端同版本，無需自訂 decoder）。
- `LumaControlCommand` 加 `case setWorkflowPhase(String)`（rawValue）。
- `LumaSyncCoordinator`：republish 帶 `workflowPhase: appModel.workflowPhase.rawValue`；inbound `.setWorkflowPhase(raw)` → `if let p = WorkflowPhase(rawValue: raw), p != .rigging { appModel.setWorkflowPhase(p) }`（**v1 忽略 iPad→架設**：進 tabletop space 的 swap 需 host 端 view action，coordinator 無法觸發；見 Caveats）。
- iPad panel（`PanelRootView`/`PanelLightingView` 頂部或 toolbar）：顯示目前階段（`model.host?.workflowPhase`），提供「編程/播放」兩段切換（送 `.setWorkflowPhase`），「架設」段顯示但 disable。`WorkflowPhase.swift` **加入 iPad target membership 例外清單**。

**8f. smoke（`Tests/…`）**
- 新 `workflowPhasePolicyGatesByPhase()`：rigging 允許 move/layout/tabletop、禁 cue 編輯/時間軌；programming 允許 cue 編輯、禁 move、允許 jump；playback 顯示時間軌、允許 jump、禁 move/cue 編輯；`usesTabletopEditorSpace` 僅 rigging。
- 擴充 `lumaSyncProtocolRoundTrips()`：`LumaHostState.workflowPhase` 與 `LumaControlCommand.setWorkflowPhase` round-trip。
- 兩者在 `main()` 註冊。`WorkflowPhase.swift` 加進 smoke swiftc 清單（見 Verification）。

---

### WI-9 — 編程頁：逐 cue 調色/角度/亮度，鎖定燈具位置（issue #9）

**相依**：`WI-8`（`workflowPhase`、`WorkflowPhasePolicy`、`SelectedLightControlView` 已是選燈編輯面）。
**擁有檔**：`LumaStage/SelectedLightControlView.swift`、`LumaStage/LightingModels.swift`（一個純函式）、`Tests/LumaStageCoreSmokeTests.swift`（一條新測試 + 註冊）。**不動 `AppModel.swift`**（沿用既有 `setFixtureColor`/`setFixtureIntensity`/`rotateFixture`）。

設計原則：編程頁**沿用**「點燈選取→`SelectedLightControlView` 卡」互動，但在 `.programming` 階段把編輯**寫進 recorded cue（第 1 層）**而非暫態 `lightOverrides`——因為 recorded per-fixture 編輯目前只在 iPad 露出（見根 `CLAUDE.md`：dimmer/color 控制曾只在 iPad），編程頁正是把它搬進頭顯。**不發明第四層**：色/亮走 `CuePatch`（`setFixtureColor`/`setFixtureIntensity`），角度走 rig-identity `rotateFixture`。

**9a. 燈號→fixtureId 純函式（`LightingModels.swift`，已在 smoke 集）**
```swift
extension LightingCue {
    /// 1-based 場上燈號（fixtureGroups 順序，Light 1…N）→ fixture id
    func fixtureId(forLightNumber number: Int) -> String? {
        guard number >= 1, number <= fixtureGroups.count else { return nil }
        return fixtureGroups[number - 1].id
    }
}
```

**9b. `SelectedLightControlView` 編程路由 + 角度**
- 讀 `appModel.workflowPhase`。當 `WorkflowPhasePolicy.allowsCueEditing(in:)`（＝programming）時，色/亮控制改寫 recorded cue：
  ```swift
  if let cue = appModel.selectedCue, let fid = cue.fixtureId(forLightNumber: number) {
      appModel.setFixtureColor(id: fid, hexColor: hex)      // Slider/swatch → CuePatch，per-cue、persist
      appModel.setFixtureIntensity(id: fid, value: v)
  }
  ```
  swatch/Slider 的目前值改讀 `cue.fixtureGroups[number-1]` 的 color/intensity（非 `selectedLightResolved`），使卡反映**選取 cue**的實際錄製值。
- 新增**角度列 `angleRow`**：pan/tilt 各一組 −/＋ 步進（建議 ±5°／±15° 兩檔），呼 `appModel.rotateFixture(id: fid, panDelta:, tiltDelta:)`；顯示目前 `aimOffset`（`cue.fixtureGroups[number-1].aimOffset`，nil→0）。繁中 label（例「向左／向右」「上仰／下俯」）、`lumaGazeTarget`、a11y。**角度是 rig-identity（跨所有 cue），非 per-cue**——UI 以一句 hint 說明（見 Caveats）。
- `.playback` 階段：卡的編輯控制 `.disabled`（唯讀）——點燈可看不可改（移動禁止已由 8b policy 保證）。`.programming` 以外不寫 recorded（維持既有暫態 `lightOverrides` 給語音/快速微調，不回歸）。
- cue 選取沿用 composer 既有 `cueStrip`（不新增 UI）。

**9c. smoke**
- 新 `lightingCueMapsLightNumberToFixtureId()`：越界→nil；1→第一盞 id；N→第 N 盞 id。在 `main()` 註冊。

---

### WI-10 — 播放頁：cue list 時間軌與播放進度（issue #10）

**相依**：`WI-8`（`workflowPhase`、`WorkflowPhasePolicy.showsPlaybackTimeline`）；SPEC 16（`CuePlayback`/`CuePlaybackEngine`/`isPlayingCueList`/`togglePlayback`）。
**擁有檔**：`LumaStage/CueTimeline.swift`（新，Foundation-only）、`LumaStage/PlaybackTimelineView.swift`（新，`#if os(visionOS)` view）、`LumaStage/VisionAIComposerBox.swift`（一處嵌入）、`LumaStage/AppModel.swift`（一個 passthrough 計算屬性）、`Tests/…`、`project.pbxproj`、README/CLAUDE smoke 清單。

**10a. 時間軌純邏輯（`CueTimeline.swift`，進 smoke 集）**
```swift
import Foundation

struct CueTimelineBlock: Equatable, Identifiable {
    let id: String            // = cueId
    let index: Int            // 0-based，對應 cues 順序
    let cueId: String
    let displayName: String
    let start: Double         // 自時間軌原點的秒
    let duration: Double
    var end: Double { start + duration }
}

enum CueTimeline {
    /// 一般 look：每格寬 = holdDuration（SPEC16 鉗值）＋ transition.duration；start 累加。
    static func blocks(for cues: [LightingCue]) -> [CueTimelineBlock]
    /// 音樂秀：每格起訖直接取 SongSection.start / duration（cueIds/displayNames 依 section index 對齊，cue_music_<i>）。
    static func musicBlocks(sections: [SongSection], cueIds: [String], displayNames: [String]) -> [CueTimelineBlock]
    static func totalDuration(of blocks: [CueTimelineBlock]) -> Double          // 末格 end；空→0
    static func cursorFraction(elapsed: Double, total: Double) -> Double         // clamp 0...1；total<=0→0
    static func currentIndex(atElapsed elapsed: Double, blocks: [CueTimelineBlock]) -> Int?  // [start,end) 命中；超過末格→末格 index
    static func index(atFraction fraction: Double, blocks: [CueTimelineBlock]) -> Int?       // 點擊位置 fraction(0...1)→cue index
}
```
一般 look 每格 `duration = CuePlayback.holdDuration(for: cue) + cue.transition.duration`（沿用 SPEC 16 的鉗值，勿另訂）。

**10b. 播放頁 view（`PlaybackTimelineView.swift`，`#if os(visionOS)`）**
- 一條水平時間軌：每個 `CueTimelineBlock` 一段（寬 ∝ `duration/total`），顯示 `displayName`（開場/重點…），目前 cue（`appModel.selectedCueId`）高亮。
- **進度游標**：
  - 音樂秀（`appModel.isMusicShowActive`）：`elapsed = appModel.musicElapsedSeconds`（見 10d），blocks 走 `musicBlocks(sections:…)`。
  - 一般 look：blocks 走 `blocks(for: cues)`；游標用 `TimelineView(.animation)` 或 `.periodic(0.033)` 重繪，`elapsed = currentBlock.start + now − cueStartWallClock`（`cueStartWallClock` 為 view `@State`，在 `.onChange(of: appModel.selectedCueId)` 捕捉 `Date()`；`!appModel.isShowRunning` 時凍結在 block.start）。游標位置 `= cursorFraction(elapsed:total:) × 軌寬`。
- **transport**：播放/停止複用 `appModel.togglePlayback()`＋`appModel.isShowRunning`（**暫停/續播 v1 延後**，見 Caveats）。
- **點軌跳 cue**：tap 某 block → `appModel.selectCue(id: block.cueId)`；播放中須重排 follow 倒數——若 `selectCue` 未如 `goToNextCue` 呼 `rescheduleCuePlaybackIfPlaying()`，本 WI 於 tap handler 後補一次重排（一行；勿改 `CuePlaybackEngine` 內部）。
- 設計 token、Reduce Motion（游標動畫 gate `@Environment(\.accessibilityReduceMotion)`→改離散跳格）、Dynamic Type、繁中 a11y（軌/格/游標）。

**10c. Composer 嵌入（`VisionAIComposerBox.swift`）**
- 在 `cueStrip` 區域，`WorkflowPhasePolicy.showsPlaybackTimeline(in: appModel.workflowPhase)`（＝playback）時渲染 `PlaybackTimelineView()`（一行嵌入）。非播放階段維持既有 `cueStrip`。（此檔亦被 WI-8 動→序列分派。）

**10d. AppModel passthrough（`AppModel.swift`，一處）**
- 新 `var musicElapsedSeconds: Double { musicSyncEngine.currentTime }`（view 讀音樂游標；`musicSyncEngine` 為 private，需此 passthrough）。

**10e. smoke**
- `cueTimelineComputesBlockBoundaries()`：多 cue（各給不同 hold + transition）→ start 累加正確、`end==start+duration`、`totalDuration` 為末格 end。
- `cueTimelineMapsFractionAndElapsedToIndex()`：`index(atFraction:)` 邊界（0→首、1→末、中段命中對格）；`currentIndex(atElapsed:)` 命中 [start,end)、超末格→末格。
- `cueTimelineBuildsFromMusicSections()`：`SongSection.start/end` → blocks 的 start/duration 對齊、cueIds/displayNames 對位。
- 三者在 `main()` 註冊。`CueTimeline.swift` 加進 smoke swiftc 清單。

---

## Constraints

- **可判定邏輯進 Foundation-only 檔 + smoke**：`WorkflowPhase.swift`（policy）、`CueTimeline.swift`（時間軌數學）、`LightingCue.fixtureId(forLightNumber:)`；view 當薄消費者。
- **沿用既有 space swap**（`ContentView.reconcileImmersiveScene` + `enter/exitTabletopEditing` + `desiredImmersiveScene`）；**勿**新增 `openImmersiveSpace` 路徑。dismiss 一律從離開 space 的 view 做、open 從主視窗 reconcile。
- **不發明第四層燈光狀態**（#9）：色/亮走 `CuePatch`、角度走 rig-identity `rotateFixture`；`lightOverrides`/`groupMasters` 語義不變。
- **不重做連續播放**（#6=SPEC 16）：沿用 `CuePlayback`/`CuePlaybackEngine`/`holdDuration`/`isPlayingCueList`/`togglePlayback`；**勿改** `CuePlaybackEngine.swift`、`MusicSyncEngine.swift` 內部（只讀 `currentTime`/`sections`）。
- **平台守衛**：view 檔 `#if os(visionOS)`；iPad panel `#if os(iOS)`。新增共用檔（`WorkflowPhase.swift`）進 iPad target membership 例外清單；`CueTimeline.swift`/`PlaybackTimelineView.swift` 只在 visionOS target。
- **使用者字串繁體中文**；`WorkflowPhase.rawValue`（`rigging`/`programming`/`playback`）為 wire/程式值維持英文。
- **Observation footgun**：本 spec 的 UI 讀取都在一般 SwiftUI view body（Observation 正常）；若日後把階段狀態接進 `RealityView update:` closure，須於 `ImmersiveView.body` eager-read `appModel.workflowPhase`。
- **新檔要加進 Xcode target**（`project.pbxproj`：`WorkflowPhase.swift` → LumaStage + LumaStageControl；`CueTimeline.swift`/`PlaybackTimelineView.swift` → LumaStage），並**同步更新 smoke swiftc 清單**（README 共用慣例 + 根 `CLAUDE.md` 測試段）。
- **只改必要**：AppModel 的 fixture/stage-object mutation guard 是強制「編程/播放禁移動」契約的最小落點；勿順手重構其他方法。

---

## Verification

**smoke（headless，新增兩個 Foundation-only 檔到編譯集）**
```bash
swiftc \
  Tests/LumaStageCoreSmokeTests.swift \
  LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
  LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
  LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift \
  LumaStage/LightEffect.swift LumaStage/MusicBeatClock.swift LumaStage/StageLightAccessibility.swift \
  LumaStage/FixtureGroups.swift \
  LumaStage/OpenAILightingService.swift LumaStage/OpenAIKeychain.swift \
  LumaStage/SongAnalysis.swift LumaStage/ShowPlan.swift LumaStage/RigConstraint.swift LumaStage/MusicShowBuilder.swift \
  LumaStage/SongLibrary.swift LumaStage/DemoTrackSynth.swift \
  LumaStage/CuePlayback.swift \
  LumaStage/WorkflowPhase.swift LumaStage/CueTimeline.swift \
  -o /tmp/smoke && /tmp/smoke
# 通過條件：印出 "LumaStageCoreSmokeTests passed"、exit 0
```
必過的新測試：`workflowPhasePolicyGatesByPhase`、`lightingCueMapsLightNumberToFixtureId`、`cueTimelineComputesBlockBoundaries`、`cueTimelineMapsFractionAndElapsedToIndex`、`cueTimelineBuildsFromMusicSections`，以及擴充後的 `lumaSyncProtocolRoundTrips`。

**完整 build**
```bash
xcodebuild -scheme LumaStage \
  -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
```
通過條件 `** BUILD SUCCEEDED **`。iPad 面板另驗 `LumaStageControl` scheme build 綠（`WorkflowPhase.swift` 已進 membership）。忽略既有 Multipeer `Sendable`／MCSession delegate 含 `error:` 字樣的非錯誤噪音。

**手動流程 sanity（模擬器可跑的部分）**
- 開專案落在「編程」；composer 頂部三段切換可見。
- 編程→架設：swap 到 tabletop 編輯 space（模擬器無桌面→浮空 fallback，符合既有行為）；tabletop 控制列可切回「編程/播放」。
- 編程頁：點燈開卡→改色/亮寫進選取 cue（切 cue 再回來值保留）、角度步進即時轉燈頭＋光束。
- 播放頁：時間軌顯示各 cue 區塊、播放游標前進、目前 cue 高亮、點某格跳 cue、播放/停止可用。

---

## Caveats（只能實機驗、或刻意延後）

- **預設落地階段＝編程（非架設）**：保留既有 `openProject`→`.stage` 行為、且架設是需偵測真實桌面的 mixed passthrough（模擬器只浮空）。若決賽敘事要「一開場先架燈」，改 `workflowPhase` 預設為 `.rigging` 並讓 `openProject` 設 `desiredImmersiveScene=.tabletopEditor`——**這是刻意的設計取捨，非技術限制**，落地前請與需求方確認。
- **角度是 rig-identity（跨所有 cue），非 per-cue**：`rotateFixture`/`aimOffset` 依 SPEC 13 對同 id 每個 cue 一起改；`fineControl.pan/tilt` 不能當角度（會 tilt 疊加、且不在 `syncRig` signature→不重對準）。issue #9 文案的「各 cue 的角度」在現有模型上只能是 rig-identity；per-cue 角度需新資料欄位，**本 spec 不做**（UI 以一句 hint 說明角度套用到全部 cue）。
- **iPad→架設 v1 不支援**：切到架設要進 tabletop space，其 `dismissImmersiveSpace`/`openWindow` 是 host 端 view action，coordinator 無法觸發；iPad 只鏡射顯示 + 驅動編程↔播放。完整 iPad 三階段平價（含遠端觸發架設）延後。
- **一般 look 播放游標平滑度**靠 view 端 `cueStartWallClock` 時間戳插值（非引擎連續 tick），跨 cue 邊界可能有 <1 幀誤差；音樂秀走 `MusicSyncEngine.currentTime`（30 Hz）較準。Reduce Motion 下改離散跳格。
- **暫停/續播、循環播放延後**（SPEC 16 已列延後項）：播放頁 v1 只有 播放/停止 + tap 跳 cue。
- **space swap 耗盡→stranded 階段**：`reconcileImmersiveScene` 放棄時清 `desiredImmersiveScene=.none` 退回 composer，但 `workflowPhase` 可能仍為 `.rigging`。建議在 reconcile 的放棄分支順手 `appModel.workflowPhase = .programming`（`ContentView` 一行硬化，未列入 WI-8 擁有檔，實作時可加）。
- **實機驗**：三段切換與 space swap 的 races（已由 `ImmersiveSceneReopenPolicy` 硬化）、時間軌注視/觸控命中精度與可讀性、架設頁桌面偵測、編程頁角度步進手感、播放中 tap 跳 cue 重排 follow 的時序、iPad 分頁鏡射延遲。
