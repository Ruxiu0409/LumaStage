# SPEC 13 — 單燈旋轉指令「Light N turn right/left M degrees」（S1 語音控燈延伸）

> Status: done

**Goal**：讓英文自然語言指令**旋轉單一燈具的朝向**（pan 左右／tilt 上下），指令即時生效、持久（rig identity，跨所有 cue）、renderer 讓**燈頭幾何＋光束一起轉**。目前三層皆缺：`LightCommand` 沒有旋轉 case（"Light 6 turn right 60 degrees" 解析回 nil → 掉進整體 FM 重生成，不會轉那盞燈）、資料層沒有可用的朝向偏移欄位、renderer 的 aim 只由 zone 幾何推算、`fineControl.pan/tilt` 從不被讀取。

## Ground truth（沿用，勿重寫）
- **指令解析**：`LightCommand`（`LightingModels.swift:456`，Foundation-only、smoke-tested）。`parse(_:)` 依序：全域(blackout/all on) → role+色 → `guard lightNumber` → 色 → 亮度 → close → open → `nil`。`targetLightNumber` 供 range 檢查。單燈指令在 `AppModel.generate`（`AppModel.swift:903`）於 FM 生成**之前**攔截：`if let command = LightCommand.parse(prompt) { applyLightCommand(command); return }`。
- **rig identity 範式**：`AppModel.moveFixture(id:toX:y:z:)`（`AppModel.swift:468`）對**每個 cue** 找同 `id` 的 fixture 寫 `manualPosition`，走 `stageState.replaceLightingLook`（內含 `validate()`）+ `persistCurrentProjectState()`，失敗 `fail(...)`。**旋轉方法完全照抄這個形狀。**
- **additive 選填欄位範式**：`FixtureGroup.manualPosition: FixturePosition? = nil`（`LightingModels.swift:329`，`Codable`、舊 JSON 缺鍵解 nil、無自訂 decoder）。**新 `aimOffset` 照抄。**
- **旋轉數學已存在，直接呼叫**：`LightEffectSystem.aim(base:panDegrees:tiltDegrees:) -> SIMD3<Float>`（`LightEffectSystem.swift:80`，pan 繞世界 up、tilt 繞 beam right、回傳正規化方向）＋ `LightEffectSystem.lookOrientation(forward:)`（`:91`）。**不要重推 quaternion。** 同 module，`ImmersiveView` 可直接呼叫。
- **renderer aim 現況**：`RigPlacement.resolvedPlacement(fixture:slot:count:layout:)`（`LightingModels.swift:1658`）回傳 zone 推算的 `(position, aim)` 點；`ImmersiveView.addRigFixture`（`:707`）用 `aim - position` 方向 aim 燈頭模型（`makeStageFixture(aim:)`）＋ `addStageSpotLight`（設 `spot.orientation` ＋ `LightEffectComponent.baseAim`）。**兩處都只吃 zone aim，從不讀 pan/tilt。** 每幀 `LightEffectSystem.update` 繞 `baseAim` 加動態偏移再對準。

### 兩個關鍵 footgun（設計即為了避開）
- **① tilt 疊加陷阱**：zone aim **已經朝下打台**，而 `fineControl.tiltDegrees` 預設 −35/−18（死資料，renderer 從沒讀）。**絕不可**改成消費 `fineControl.pan/tilt`——會把死資料復活，讓每個現有 look 的燈多俯 ~35°。**正解：另開 additive `aimOffset`（預設零＝現有 look 零位移）**，把它當「疊在 zone aim 上的偏移」。
- **② syncRig 不因朝向/位置改變而重建**：`syncRig`（`:663`）的重建 signature 只有 `id|renderModel|zone`，**不含 manualPosition/朝向**。所以 `moveFixture` 只在**離開桌面編輯器、舞台空間被重建**時才反映；活的 1:1 舞台下改朝向**不會重新對準**。旋轉指令在活舞台下發，故 signature **必須**納入 `aimOffset`（順帶納入 `manualPosition`，一併修掉 live-move 反映漏洞）。

## Work items（單一 agent 序列做完並編譯通過；三檔互相依賴，不並行）
擁有 `LightingModels.swift`、`AppModel.swift`、`ImmersiveView.swift`、`Tests/LumaStageCoreSmokeTests.swift`。

### 1. `LightingModels.swift`（Foundation-only）
**a. 新 struct**（放在 `FixtureFineControl` 附近）：
```swift
struct FixtureAimOffset: Codable, Equatable {
    var panDegrees: Double = 0     // +右 / −左（資料慣例；視覺左右在 renderer 驗，見 Caveats）
    var tiltDegrees: Double = 0    // +上仰 / −下俯
    static let zero = FixtureAimOffset(panDegrees: 0, tiltDegrees: 0)
    func validate() throws { /* pan −180...180、tilt −90...90，違反擲 invalidFineControlValue */ }
    /// 加上 delta 並夾到合法範圍後回新值。
    func adding(panDelta: Double, tiltDelta: Double) -> FixtureAimOffset
}
```
**b. `FixtureGroup`**：加 `var aimOffset: FixtureAimOffset? = nil`（放在 `manualPosition` 後；`Codable` 預設、確認舊 JSON 缺鍵解 nil）。在 look 的 `validate()`（現有 `if let fineControl … { try fineControl.validate() }` 那處，`LightingModels.swift:965`）加 `if let aimOffset = fixture.aimOffset { try aimOffset.validate() }`。

**c. `LightCommand`**：
- 加 case `case rotate(Int, panDeltaDegrees: Double, tiltDeltaDegrees: Double)`；`targetLightNumber` 的 switch 補這個 case 回傳其 `Int`。
- `parse`：在**亮度檢查之後、close 之前**插入旋轉偵測（因為 "turn right 60 degrees" 不含 %/dim、不含 "turn off"/close 觸發，安全）。規則：需**旋轉動詞** `{turn, pan, tilt, rotate, aim, point, spin}` **且方向詞** `{right, left, up, down}` 同時出現；`right→pan +M`、`left→pan −M`、`up→tilt +M`、`down→tilt −M`；幅度 M = 文字中「跳過燈號後的第一個數字」（沿用 `intensityFraction` 跳燈號手法），**無數字則預設 45**。回 `.rotate(number, panDeltaDegrees:, tiltDeltaDegrees:)`（其中一軸為 0）。
- 抽 `private static func rotationCommand(number:in:words:) -> LightCommand?`（無動詞+方向組合則回 nil，讓流程續往 close/open 掉）。**確保 "turn off light 2" 仍解 `.close(2)`、"turn on light 4" 仍 `.open(4)`（on/off 非方向詞，rotate 不誤吃）。**

**d. smoke（加進 `parsesSingleLightCommands` 或新 `parsesLightRotationCommands`，記得在 `main()` 註冊新函式）**：
```swift
expect(LightCommand.parse("Light 6 turn right 60 degrees") == .rotate(6, panDeltaDegrees: 60, tiltDeltaDegrees: 0), …)
expect(LightCommand.parse("turn light 2 left 45 degrees")   == .rotate(2, panDeltaDegrees: -45, tiltDeltaDegrees: 0), …)
expect(LightCommand.parse("tilt light 3 up 20 degrees")     == .rotate(3, panDeltaDegrees: 0, tiltDeltaDegrees: 20), …)
expect(LightCommand.parse("rotate light 4 down 30")         == .rotate(4, panDeltaDegrees: 0, tiltDeltaDegrees: -30), …)
expect(LightCommand.parse("pan light 1 right")              == .rotate(1, panDeltaDegrees: 45, tiltDeltaDegrees: 0), … /* 預設 45 */)
expect(LightCommand.parse("turn off light 2") == .close(2), "rotate 不可誤吃 turn off")
expect(LightCommand.parse("turn on light 4")  == .open(4),  "rotate 不可誤吃 turn on")
expect(FixtureAimOffset.zero.adding(panDelta: 200, tiltDelta: 0).panDegrees == 180, "pan 夾到 180")
expect(FixtureAimOffset.zero.adding(panDelta: 0, tiltDelta: -200).tiltDegrees == -90, "tilt 夾到 −90")
// 舊 JSON（無 aimOffset 鍵）decode → nil（沿用現有 FixtureGroup Codable 回退測法）
```

### 2. `AppModel.swift`（不在 smoke 集）
- `func rotateFixture(id: String, panDelta: Double, tiltDelta: Double)`：**照抄 `moveFixture`**——對**每個 cue** 找同 `id` fixture，`fixtureGroups[i].aimOffset = (fixtureGroups[i].aimOffset ?? .zero).adding(panDelta:tiltDelta:)`，`replaceLightingLook` + `persistCurrentProjectState`，未找到 `fail("找不到要旋轉的燈具。")`。
- `applyLightCommand` 加 `.rotate(let number, let pan, let tilt)` case（頂端的 1...lightCount range 守衛已涵蓋 number）：以 `selectedCue?.fixtureGroups[number-1].id` 取燈具 id（cue 順序＝燈號），呼 `rotateFixture`；成功後照 `.setColor` 等 case 收尾（`lastError = nil`、`aiUnderstoodCommand = Self.describe(command)`、`conversationState = .explaining`、`narrateIfEnabled`）。
- `Self.describe(_:)`（`:1254` 一帶）加 `.rotate` → 繁中：pan>0「向右轉」、pan<0「向左轉」、tilt>0「向上仰」、tilt<0「向下俯」，附 `\(Int(abs(度)))°`，例「已將 第 6 盞燈 向右轉 60°」（用 `StageLightLabel.displayName(number:)`）。
- **不需另設清除點**：`aimOffset` 進 look、隨 AI 重生成整包被取代（同 `manualPosition`）。

### 3. `ImmersiveView.swift`（`#if os(visionOS)`，不在 smoke 集）
- **syncRig signature**（`:666`）：每盞附加 `aimOffset`（pan/tilt，取整避免浮點抖動）與 `manualPosition`，例：
  `"\($0.id)|\($0.renderModel.rawValue)|\($0.zone.rawValue)|\(Int((($0.aimOffset?.panDegrees ?? 0)).rounded()))|\(Int((($0.aimOffset?.tiltDegrees ?? 0)).rounded()))|\($0.manualPosition.map{"\($0.x),\($0.y),\($0.z)"} ?? "-")"`。這樣旋轉/移動指令會改 signature → 重建 rig → 重新對準（v1 硬切，見 Caveats）。
- **`addRigFixture`（`:707`）算出 resting 方向並套用到燈頭模型＋spotlight＋baseAim**：
  ```swift
  let offset = fixture.aimOffset ?? .zero
  let baseDir = scenePoint(placement.aim) - scenePoint(placement.position)
  let baseUnit = simd_length(baseDir) > 0.0001 ? simd_normalize(baseDir) : SIMD3<Float>(0,0,-1)
  let restingDir = LightEffectSystem.aim(base: baseUnit,
                                         panDegrees: offset.panDegrees, tiltDegrees: offset.tiltDegrees)
  ```
  - 燈頭模型：`makeStageFixture(for:targetHeight:aim: restingDir)`（取代原 `aimVector` 那行）。
  - spotlight：把 `restingDir` 傳進 `addStageSpotLight`（加參數 `restingAimDirection: SIMD3<Float>`），內部以它設 `spot.orientation = lookOrientation(forward: restingDir)`（或現有等效 `orientation(from:.-Z, to:)`）**且** `LightEffectComponent(baseAim: restingDir, …)`——如此每幀動態掃燈繞使用者選定的朝向、steady 效果就停在 restingDir。
- **零位移不改觀感**：`aimOffset ?? .zero` → `LightEffectSystem.aim(base:0:0)` 回 base 本身，現有/AI 生成 look 完全不變（tilt 疊加陷阱已避）。

## Constraints / 並行
- 單一 agent 序列：三檔互相依賴（新型別、新 case、新方法、renderer 契約），**不並行**。
- `LightingModels.swift` 維持 Foundation-only；renderer 改動限 `#if os(visionOS)`。**不重寫** `RigPlacement.placement`、`validate()` 既有規則、既有 cue 編輯、`LightEffectSystem`。
- 解析關鍵字英文（見根 CLAUDE.md）；`describe`/narrate 使用者字串繁體中文。
- Observation footgun：`apply`/renderer 反應的 `@Observable` 狀態已在 `body` eager-read（`lightingLook` 等），旋轉走 `replaceLightingLook` 改的是 `stageState.lightingLook`，已被讀 → update closure 會重跑。無需新增 eager-read。

## Verification
- **smoke**：新旋轉解析 + `adding` 夾值 + 舊 JSON→nil → `LumaStageCoreSmokeTests passed`（`LightingModels.swift` 已在編譯集，無需改指令）。
- **完整 build**：`** BUILD SUCCEEDED **`（Multipeer 既有警告忽略）。
- **實機**：對某盞 moving head 發「Light N turn right 60 degrees」→ 該燈**燈頭＋光束**向（觀眾視角）右轉約 60°；「turn left」反向；「tilt up/down」上下俯仰；**其他燈不動**；**現有 look 開起來與改動前一致（無垂直位移）**；切 cue、關閉重開專案後仍保留（rig identity + 持久）。

## Caveats
- **左右符號需實機驗**：資料慣例定 `right = +panDegrees`；`LightEffectSystem.aim` 繞 +Y，實際視覺左右取決於 base 方向與觀眾 POV。驗收基準＝**觀眾視角**「turn right」光束往觀眾的右邊移。若相反，只在**一處**翻符號（建議 renderer 端 `restingDir` 前對 pan 取負，保持資料 right=+）。
- **旋轉硬切**：signature 觸發 rig 重建 → 幾何一次性重建、光束不 cross-fade 到新朝向。平滑動畫 pan（`move(to:)` 或改走 `apply` 就地重對準 + baseAim 更新）**延後 v2**。
- **雷射（`.laser`）beam 扇旋轉延後**：`addLaserProjector` 目前固定朝向；v1 只有其 `spot_<id>` 錐狀溢光會隨 aim 偏移，可見光束扇不轉。moving head / PAR / strobe / fresnel / blinder 皆涵蓋（使用者案例 Light 6 為 moving head）。
- **AI 重生成取代 `aimOffset`**：換 fixture 集合時手動旋轉隨舊 look 一起被取代（同 `manualPosition`/`lightOverrides`，v1 不合併）。
- **`manualPosition` 納入 signature 為順帶修復**：活舞台下的移動現在也會即時反映（原本只在舞台空間重建時）；需實機確認無重建閃爍/churn。
- **設計備註**：`aimOffset` 是**新** additive 欄位而非復用 `fineControl.pan/tilt`，正是為了不復活 `fineControl.tiltDegrees = −35` 這筆死資料（見 Ground truth footgun ①）。未來若要把「錄製 vs 現場覆蓋」兩層 state 徹底統一，另開 spec。
