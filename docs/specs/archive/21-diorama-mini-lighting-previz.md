# SPEC 21 — 桌面 diorama 迷你燈光預覽（掌上 previz，issue #24）

> Status: done

**Goal**：桌面舞台編輯器（`TabletopStageEditorView` 的「架設」階段）目前 diorama 上只有結構（桁架／台座）＋燈具型號代理，**看不到目前 cue 打出來的光**——要看打光得離開編輯器回 1:1 舞台。本 spec 讓 diorama 直接顯示目前 cue 的打光：每盞燈畫一支**半透明彩色光束錐**（顏色／亮度／朝向依該 cue 的 fixture 狀態），控制列加 **‹ cue ›** 切換就地預覽整套 cue，並（進階／可選）在音樂秀播放時讓整檯模型跟著節拍跑。呼應「空間運算 previz」與「科技賦能」社會價值——不必進 1:1 沉浸就能在桌上把整套 look 看完。與 **SPEC 02**（型號專屬幾何上台，已 shipped）＋ **issue #25**（桌面 rig 型號幾何，本輪 shipped——`syncFixtures` 已用 `FixtureRealityModel.makeStageFixture` 建代理）成對：#25 讓桌上 rig **可讀**，本 spec 讓它**可預覽**。

> 風險控管：**可判定幾何（光束錐尺寸：由 beam angle＋throw＋intensity 推 length/baseRadius/alpha）下沉到 Foundation-only `LightingModels.swift`（緊鄰 `SpotLightRenderMath`）+ 1 條 smoke**；RealityKit 錐 mesh／材質更新、SwiftUI cue 切換鈕、可選的逐幀節拍訂閱都是薄平台層。**不新增檔案**（幾何 helper 加進既有、已在 smoke 集的 `LightingModels.swift`），故 **smoke 編譯集清單不變**。**不改 `AppModel`**（cue 切換、cue 資料、音樂 clock 全沿用既有 API）。本 spec **視覺調校吃重、規模較大**，多數落點需 **[需實機]** 微調。

## Ground truth（已存在、沿用而非重寫）

- **擁有檔／同步入口**：`TabletopStageScene.syncFixtures(_:look:layout:selectedFixtureId:)`——依 id reconcile 燈具代理，取 selected cue（else first）的 `fixtureGroups`，逐一算 per-zone slot/count → `RigPlacement.resolvedPlacement` → `scenePoint`，並在**每一 pass** 以目前 cue 色重上 `fixture_lens`（#14）、更新 `fixture_stand`（SPEC 15）、更新 `fixture_caption`（#13）。`makeFixtureProxy(named:model:hex:aim:)` 建 `fixture_model`（`FixtureRealityModel.makeStageFixture`，#25）＋ emissive `fixture_lens`（`aimUnit` 方向、位於 `aimUnit * sceneLength(0.22)`）＋ 隱藏 `fixture_selection_highlight` 環。`aimDir` 已在 `syncFixtures` 算好：`baseUnit = normalize(scenePoint(aim) - scenePoint(position))`，再經 `LightEffectSystem.aim(base:panDegrees:tiltDegrees:)` 疊 `fixture.aimOffset`（SPEC 13）——**光束錐要沿用這同一條 `aimDir`**，才與代理模型／1:1 舞台朝向一致 — `TabletopStageEditorView.swift`。
- **scene 座標轉換**：`TabletopStageScene.scenePoint(_:)`／`sceneToMeters(_:)`／`sceneOffset(_:)`／`sceneLength(_:)`（`scale = 0.07`、`origin`）；`material(hex:metallic:)` → `SimpleMaterial`、`lensMaterial(hex:)` → `UnlitMaterial`（低調共用範本）、`hangZoneMaterial()` → `UnlitMaterial(color: UIColor(..., alpha: 0.14))`（**半透明 UnlitMaterial 的既有作法**，光束錐材質照抄）、`orientation(from:to:)`（shortest-arc 對朝向）。這些都是 `TabletopStageScene` 內的 `static`（含 `private`）— `TabletopStageEditorView.swift`。
- **cue 資料 + 切換**：`FixtureGroup{ color: FixtureColor(.value: "#RRGGBB"), intensity: Double(0...1), enabled: Bool, effect: LightEffect?, aimOffset, renderModel, effectiveFineControl }`；`FixtureFineControl.beamAngleDegrees`（驗證於 5...120）；`LightingCue{ id, fixtureGroups, localizedDisplayName }`；`LightingLook.cues`／`.selectedCueId` — `LightingModels.swift`。`AppModel`（**全部已存在、沿用**）：`selectedCue: LightingCue?`、`selectedCueId`、`goToNextCue()`／`goToPreviousCue()`（**皆迴繞、內含 persist＋narrate**，底層即 `stageState.goToNextCue/Previous`）、`selectCue(id:)`（單一 cue 選取 primitive） — `AppModel.swift`。
- **cone 角度／throw 數學（1:1 舞台範本，可判定部分沿用）**：`SpotLightRenderMath.coneAngles(beamAngleDegrees:) -> (inner: Double, outer: Double)`——把 5...120° beam 映到保守的 10°...60° 外錐（inner = outer × 0.7）；`ImmersiveView` 建 spotlight 時即以此設錐（`ImmersiveView.swift:1126`）。throw 方向／距離＝`resolvedPlacement` 回傳的 `aim - position`（1:1 舞台就是這樣打向舞台目標） — `LightingModels.swift` / `ImmersiveView.swift`。
- **音樂節拍 clock（進階／可選沿用）**：`MusicSyncClockSource.shared.snapshot()`（`final class @unchecked Sendable`、render-thread 安全、**process 全域**——音樂秀播放時 `AppModel.playMusicShow` 已 `setActive(...)`；無音樂回 `nil`）；`MusicBeatSync.output(_ effect: LightEffect, clock: MusicBeatClock, at time: Double) -> LightEffectOutput`（`.intensityScale` 0...1、`.panOffsetDegrees`/`.tiltOffsetDegrees`）；`LightEffectPlan.effects(for cue: LightingCue) -> [LightEffect]`（對齊 `cue.fixtureGroups` 順序，AI 指定優先、否則確定性 `suggested`）。**`LightEffectSystem.update` 正是這樣讀 clock**：`let snap = MusicSyncClockSource.shared.snapshot(); MusicBeatSync.output(effect, clock: snap.clock, at: snap.time)`——桌面逐幀節拍就複製這兩行，**不新增任何 clock 管線** — `MusicSyncEngine.swift` / `MusicBeatClock.swift` / `LightEffectSystem.swift` / `LightEffect.swift`。
- **RealityKit mesh 慣例（footgun 來源）**：本 codebase **沒有** `MeshResource.generateCone` 的使用先例；當年缺 `generateTorus` 是改用 `MeshDescriptor` 手搓（`FixtureSpatialScene.swift:640` 的 fixture ring、`ImmersiveView.swift:800` 的選取環）。**不得臆測 API 存在**（見 Footgun）。

**Footgun**：
- **`generateCone` 未經證實**：實作前**先確認** visionOS 26 SDK 是否有 `MeshResource.generateCone(height:radius:)`（快速編譯或查 SDK header）。**有** → 直接用；**無** → 用 `MeshDescriptor` 手搓一個 apex-at-top 的錐（precedent：上述 torus／ring），或以 `generateCylinder` 退化近似（頂細底粗做不到，退而求其次可用細長 cylinder＋lens 光暈；以實機觀感決定）。**禁止**寫一個不存在的 API 名。
- **錐不可攔截手勢**：光束錐是 `tabletopfixture_<id>` 容器的子實體，**絕不掛 `InputTargetComponent`／collision**——否則 `selectTap`／`moveDrag` 會打到錐體而非燈具 body（同 `fixture_caption` 的既定作法）。它也**不能**進 `generateCollisionShapes`。
- **每 cue 色不同、rig identity 不變**：`color`/`intensity`/`enabled`/`effect` 是**逐 cue**；`aimOffset`/`manualPosition`/`renderModel`/`zone` 是 **rig identity（跨 cue 相同）**。錐的顏色＋alpha＋是否顯示要取「**目前 cue**」——`syncFixtures` 已用 selected cue（else first）的 `fixtures`，錐就從那組同一筆 fixture 取，天然正確；朝向沿用該 pass 已算好的 `aimDir`（含 `aimOffset`）。
- **Observation（cue 切換要重跑 update:）**：`syncFixtures` 跑在 `RealityView` 的 `update:` closure，該 closure 不自成 Observation 依賴。`body` 目前 eager-read `stageLayout`/`selectedStageObjectId`/`lightingLook`/`selectedFixtureId`。切換 cue 改的是 `stageState.selectedCueId`（隨 `lightingLook` 一併變動，理論上會觸發），但為求穩妥**明確加一行 `let _ = appModel.selectedCueId`** 到 `body` 的 eager-read 區塊，保證 ‹ cue › 一按就重跑 `syncFixtures` 用新 cue 的色/亮度重畫錐。
- **`enabled == false` 的燈**：該 fixture 的錐要 `isEnabled = false`（不畫）——與 1:1 舞台 gate 一致。`intensity == 0` 亦視同不顯示（alpha → 0）。
- **`fixture_lens` 已是唯一色標**：桌上本來沒有真 spotlight，`fixture_lens` 是既有的 per-fixture 色標；本 spec 的錐是它的延伸（把光「延伸到空中」），兩者**共用同一 cue 色**（`lensMaterial` 已抽出可重用），勿讓兩者色不同步。

## Work items

### WI-1 — Foundation 可判定核心（owner：`LightingModels.swift`，**在 smoke 集**）

在 `SpotLightRenderMath` 旁新增純幾何 helper（model 公尺，平台無關；view 端再用 `sceneLength` 轉 scene 單位）：

```swift
/// 桌面 diorama 半透明預覽光束錐的可判定幾何：由燈具 beam 展角、throw 距離、0...1 亮度算出
/// 錐長／底半徑／alpha。純/確定性 → smoke 釘死「形狀」（單調、夾值），不釘死實際數值（同 LaserScatterMath 慣例，
/// 便於實機重調）。angle 沿用 `SpotLightRenderMath.coneAngles(beamAngleDegrees:).outer` 當半展角近似。
enum PreviewBeamCone {
    /// alpha 上限：夠明顯但仍讀得出後方 diorama（實機微調）。
    static let maxAlpha: Double = 0.35
    /// 最短可見錐長（避免 throw≈0 時退化）。
    static let minLengthMeters: Double = 0.4

    static func dimensions(beamAngleDegrees: Double, throwMeters: Double, intensity: Double)
        -> (length: Double, baseRadius: Double, alpha: Double)
}
```

- `length = max(throwMeters, minLengthMeters)`。
- `baseRadius = length * tan(coneAngles(beamAngleDegrees:).outer° → 弧度)`（`outer` 當半展角；若實機看起來過寬/過窄，改用 `outer/2` 或另設係數——**此係數屬 [需實機] 調校**，smoke 只驗形狀不驗值）。
- `alpha = clamp(intensity, 0, 1) * maxAlpha`（intensity 0 → 0；1 → `maxAlpha`；單調）。
- 全程 clamp beamAngle 到 5...120（`coneAngles` 已 clamp）、intensity 到 0...1、throw ≥ 0。

**新 smoke**（1 條，註冊進 `Tests/LumaStageCoreSmokeTests.swift` 的 `main()`）：`previewBeamConeScalesWithBeamThrowAndIntensity`
- 更寬 beamAngle → 更大 `baseRadius`（單調）。
- 更長 throw → 更長 `length` **且** 更大 `baseRadius`。
- `intensity == 0` → `alpha == 0`；`intensity == 1` → `alpha == maxAlpha`；`intensity == 0.5` 介於兩者之間；`intensity` 超界（<0 / >1）夾到 [0, maxAlpha]。
- `throwMeters` 極小（如 0）→ `length == minLengthMeters`（不退化）。

> `LightingModels.swift` 已在 smoke 編譯集，**無需改 smoke 編譯指令**，只需在 `main()` 加一行 `try previewBeamConeScalesWithBeamThrowAndIntensity()`（與根 `CLAUDE.md` 測試段的「寫一個 `private static func` 並在 `main()` 註冊」慣例一致）。

### WI-2 — 半透明光束錐實體（owner：`TabletopStageScene` in `TabletopStageEditorView.swift`）

在 `makeFixtureProxy` 建一支光束錐子實體、在 `syncFixtures` 每 pass 更新其色/alpha/顯示（緊接既有 `fixture_lens` 重上色那段）：

- **建立**（`makeFixtureProxy`，緊接 `fixture_lens` 之後）：加一個 `ModelEntity` 命名 **`fixture_beam`**，材質為半透明 `UnlitMaterial(color: UIColor(r,g,b, alpha:))`（照 `hangZoneMaterial()` 的作法；顏色＝cue 色、alpha＝WI-1 的 `alpha`）。**不掛 InputTarget、不生 collision。**
  - 錐 mesh：`MeshResource.generateCone(height:radius:)`（**先驗證存在**，見 Footgun；無則 `MeshDescriptor` 手搓）。`height = sceneLength(dim.length)`、`radius = sceneLength(dim.baseRadius)`，`dim = PreviewBeamCone.dimensions(beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees, throwMeters: <throw>, intensity: fixture.intensity)`。`<throw>` = `simd_length(scenePoint(placement.aim) - scenePoint(placement.position)) / scale`（換回公尺）——或直接以 scene 單位算 length 後不再除 scale，擇一即可、保持單位一致。
  - **朝向**：apex（錐尖）貼 `fixture_lens` 位置，錐體沿 `aimDir`（WI-2 由 `syncFixtures` 已算的 `aimDir` 傳入 `makeFixtureProxy`，或在 `makeFixtureProxy` 內用傳入的 `aim` 重算）向舞台目標延伸。用 `orientation(from:to:)` 把 mesh 的預設軸（generateCone 的預設是 +Y）對到 `aimDir`，並把錐平移半個 length 使尖端落在 lens、底面朝舞台。
- **每 pass 更新**（`syncFixtures`，緊接 `fixture_lens` 重上色）：
  - 取 `container.findEntity(named: "fixture_beam") as? ModelEntity`。
  - 重算 `dim`，重上材質色＋alpha（用目前 cue 的 `fixture.color.value` / `fixture.intensity`）。
  - `beam.isEnabled = fixture.enabled && fixture.intensity > 0`。
  - **mesh 只在尺寸簽章（beamAngle＋throw，四捨五入）改變時重建**（避免每 pass 重生 mesh；可比對存名或存一個 rounded signature，仿 `fixture_caption_<want>` 的 name-encode 手法），色/alpha/isEnabled 則每 pass 更新。
- **顯示/隱藏動畫 gate**：錐由隱藏→顯示（切到有光的 cue、或開燈）時，**非 Reduce Motion** 走一段 `OpacityComponent` 淡入（照 `setHangZoneVisible` 的 `FromToByAnimation`/`OpacityComponent` 手法，~0.2s）；**Reduce Motion 硬切**（`isEnabled` 直接切、無淡入）。`reduceMotion` 已是 view 的 `@Environment(\.accessibilityReduceMotion)`，傳進 `syncFixtures`（`body` 讀取後傳入，與 `moveDrag` 傳 `!reduceMotion` 給 `setHangZoneVisible` 同款）。

### WI-3 — 控制列 ‹ cue › 切換（owner：`controlBar` in `TabletopStageEditorView.swift`）

在 `controlBar` 加一組 cue 切換（放在選取狀態 pill 之後、尺寸/桁架 Picker 之前，或另擇顯眼處）：

```
‹        <目前 cue 名>        ›
```

- ‹ 鈕 → `appModel.goToPreviousCue()`；› 鈕 → `appModel.goToNextCue()`（**兩者已迴繞＋persist＋narrate，即 issue 指定的「沿用 `AppModel.selectCue`」的既有包裝**——底層走同一 cue 選取路徑；勿另寫 index 計算）。
- 中間文字：`appModel.selectedCue?.localizedDisplayName ?? ""`（繁中場景名，如 開場／重點／音樂段）。可附「N/總數」（`appModel.selectedCueNumber` / `appModel.lightingLook.cues.count`）。
- 少於 2 個 cue 時 disable 兩鈕（`appModel.lightingLook.cues.count < 2`）。
- 樣式：`.buttonStyle(.bordered)`／`.buttonBorderShape(.circle)`／`.lumaGazeTarget()`／繁中 `.help`（如「預覽上一個場景」「預覽下一個場景」）／文字用 `LumaStageDesign.textPrimary`。
- 切 cue 後靠 WI-2 的每-pass 重上色即時反映（**前提：WI-1 Footgun 的 `let _ = appModel.selectedCueId` eager-read 已加**）。

### WI-4 —（進階／可選，[需實機]）音樂秀播放時整檯跟拍

> **可選**：base 功能（WI-1..3）不依賴它；若時間/實機不足可延後，但介面已備妥（clock 全域、`MusicBeatSync` 純函式）。

- 在 `RealityView` 的 `make` closure 用 `content.subscribe(to: SceneEvents.Update.self)` 註冊一個逐幀回呼（捕捉 `turntable`；訂閱 token 存進 `@State`），每幀：
  - `guard !reduceMotion else { return }`（Reduce Motion 不跑逐幀動態——同 `rotateStage` 的 gate 理由）。
  - `guard let snap = MusicSyncClockSource.shared.snapshot() else { <把所有 fixture_beam alpha 還原成 cue 靜態值> ; return }`（無音樂 → 靜態預覽，不回歸）。
  - 對每個 `tabletopfixture_<id>` 的 `fixture_beam`：取該 fixture 目前 cue 的 `effect`（`fixture.effect ?? LightEffectPlan.effects(for: cue)[index]`，**與 `LightEffectSystem` 同源**），`let out = MusicBeatSync.output(effect, clock: snap.clock, at: snap.time)`，以 `out.intensityScale` 調錐的 `OpacityComponent`（`baseAlpha * intensityScale`），使**整檯迷你 rig 跟著節拍脈動**（strobe/chase 打拍、sweep/circle 可另用 `out.panOffsetDegrees/tiltOffsetDegrees` 疊在 `aimDir` 上微掃——擇最省的先做 opacity 脈動）。
- **不改** `LightEffectSystem.swift`／`MusicSyncEngine.swift`——只**讀** `MusicSyncClockSource.shared` 與呼叫純函式 `MusicBeatSync.output`。

## Constraints

- **平台守衛**：`TabletopStageEditorView.swift` 全檔已在 `#if os(visionOS)`；WI-2..4 皆在其內。WI-1 的 `PreviewBeamCone` 是純 Foundation（無平台守衛、無 RealityKit import）。
- **不可動的檔**：`AppModel.swift`（cue 切換／音樂全用既有方法，**不新增 AppModel 方法**）、`LightEffectSystem.swift`、`MusicBeatClock.swift`、`MusicSyncEngine.swift`、`LightEffect.swift`、`ImmersiveView.swift`（1:1 舞台不動）。既有 `syncFixtures` 的 #13/#14/#15 邏輯、`fixture_lens`/`fixture_caption`/`fixture_stand`/選取環、`moveDrag`/`selectTap` **全部保留**，錐只是**新增**的子實體。
- **不新增檔**：幾何 helper 進既有 `LightingModels.swift`；view 邏輯進既有 `TabletopStageEditorView.swift`。故 **smoke 編譯集清單不變**（僅 `main()` 加一行註冊）。
- **使用者字串繁體中文**（cue 切換 `.help`、a11y label）；code identifier 英文；設計 token 沿用 `LumaStageDesign`＋`.lumaGazeTarget()`。
- **Reduce Motion**：WI-2 的顯示/隱藏淡入、WI-4 的逐幀脈動皆須 gate（`@Environment(\.accessibilityReduceMotion)`，本檔已有 `reduceMotion`）。
- **錐是純視覺**：不掛 `InputTargetComponent`、不 `generateCollisionShapes`、不進選取/拖曳路徑。

## Verification

- **完整 build**（唯一硬性通過條件）：
  ```
  xcodebuild -scheme LumaStage \
    -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
  ```
  通過＝`** BUILD SUCCEEDED **`（忽略既有 Multipeer `Sendable`／MCSession `error:` 字樣噪音）。
- **smoke**（`LightingModels.swift` 已在集內，指令不變）：
  ```
  swiftc Tests/LumaStageCoreSmokeTests.swift \
    LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
    LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
    LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift \
    LumaStage/LightEffect.swift LumaStage/MusicBeatClock.swift LumaStage/FixtureGroups.swift \
    LumaStage/OpenAILightingService.swift LumaStage/OpenAIKeychain.swift \
    LumaStage/SongAnalysis.swift LumaStage/ShowPlan.swift LumaStage/RigConstraint.swift LumaStage/MusicShowBuilder.swift \
    LumaStage/SongLibrary.swift LumaStage/DemoTrackSynth.swift LumaStage/CuePlayback.swift \
    -o /tmp/smoke && /tmp/smoke
  ```
  通過＝印出 `LumaStageCoreSmokeTests passed`、exit 0（含新 `previewBeamConeScalesWithBeamThrowAndIntensity`；既有測試不得回歸）。
- **[需實機]（Vision Pro，本 spec 視覺調校的主戰場）**：
  - 光束錐在 passthrough 桌面上是否**讀得出「有光打出來」**、與灰結構/`fixture_lens` 對比是否清楚、alpha `maxAlpha`（0.35）是否適中（過濃遮住模型／過淡看不見）。
  - `baseRadius` 由 `coneAngles.outer` 當半展角是否合理（過寬/過窄 → 改係數）；錐尖是否貼 lens、底面是否朝舞台、`aimOffset` 旋轉後錐是否跟著轉。
  - `MeshResource.generateCone` 是否存在於 26 SDK；不存在時 `MeshDescriptor` 錐的面數/法線是否正常。
  - ‹ cue › 切換是否即時重畫（驗 `selectedCueId` eager-read 生效）、迴繞行為在桌上是否合預期。
  - **效能**：≤12 支半透明錐（＋型號幾何＋stand＋caption）在 diorama 的 draw/overdraw；WI-4 若啟用，逐幀 `SceneEvents.Update` 遍歷 12 錐＋讀 clock 的開銷。
  - WI-4：整檯跟拍的觀感（opacity 脈動 vs 疊加 aim 微掃）、Reduce Motion 關閉逐幀後是否退回穩定靜態預覽、音樂秀在別的 immersive space 播放時 `MusicSyncClockSource.shared` 是否如預期為非 nil。

## Caveats

- **視覺調校吃重、規模較大**：本 spec 的「對錯」多在實機——WI-1 只把**可判定的形狀**（單調、夾值）釘進 smoke，實際 `maxAlpha`／半展角係數／`minLengthMeters`／淡入時長都是初值，預期實機再調（同 `LaserScatterConfig`/`SpotLightRenderMath` 慣例：smoke 驗形狀、數值可自由重調）。
- **`generateCone` 未證實**：實作者**必須**先確認 API 再落筆，禁止臆造（見 Footgun）；退路是 `MeshDescriptor`（本 repo torus/ring 先例）。
- **AI 重生成換掉 rig**：錐依附 fixture 代理，rig 被 AI 重生成取代後錐隨新代理重建（同 `manualPosition`/`lightOverrides`，v1 不合併），符合現況。
- **雷射**：`.laser` 型號在 1:1 舞台有自己的可見光束扇（`addLaserProjector`）；桌上是否也給雷射一支預覽錐、或維持型號幾何＋lens 即可，屬 [需實機] 觀感取捨（v1 可比照其他型號給錐，簡單一致）。
- **WI-4 可選**：逐幀節拍是 issue 標「進階」的部分；base 預覽（WI-1..3）先落地即滿足「桌上看得到打光＋切 cue 預覽」的主訴求。WI-4 未做不阻礙 spec 收斂——收尾時在「現況基線」註明 WI-4 是否納入。
- **gobo/effect 不投影**：visionOS 26 港版 gobo 為資料層、不投影；桌面錐同樣只表現顏色/亮度/展角/朝向，不畫 gobo 圖案（與 1:1 舞台一致）。
