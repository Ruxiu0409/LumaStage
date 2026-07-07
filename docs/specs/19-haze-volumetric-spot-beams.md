# SPEC 19 — 煙幕（haze）：讓聚光燈的光束路徑在空氣中可見（issue #2）

> Status: proposed

**Goal**：讓一般 `SpotLight` 的光錐在空氣中「看得到」——目前只有 `.laser` 有可見的空中光束（core+sheath 圓柱扇），一般聚光燈的光錐在空氣中是隱形的，只看得到打在表面的光斑。作法：**把雷射的幾何式 core+sheath 分層做法推廣到聚光燈光錐**——每盞 `spot_<id>` 加一組半透明體積光錐（cone mesh），顏色/透明度/半徑由 cue 的 hex + intensity + beam angle 推導，數學放 Foundation-only 檔並補 smoke test（比照 `LaserScatterMath`/`LaserScatterConfig`/`SpotLightRenderMath` 的分層慣例）。**明確不走粒子路線**（`ParticleEmitterComponent` 已試過並移除：不受場景光照，1:1 尺度下呈離軸噪點）。呼應 `docs/demo-runbook.md` 的展演視覺震撼與 1:1 數位孿生的沉浸擬真度——延續雷射 show-stopper 的「空中可見光」語彙，讓整組 rig 都有真實舞台的煙幕光束觀感。

**現況缺口**：`ImmersiveView.addRigFixture`（`ImmersiveView.swift:624`）為 non-laser 型號建 `model_<id>` 幾何 + `spot_<id>` 真 `SpotLight`（`addStageSpotLight`，`:1112`），但**沒有任何空中可見幾何**——`SpotLight` 只照亮它打到的表面。只有 laser 分支（`:648`）呼 `addLaserProjector`（`:1288`）建 core+sheath 圓柱扇並由 `updateLaserProjector`（`:1370`）逐 cue 重上色/開關。本 spec 把同一「幾何式空中光」概念泛化成聚光燈的**體積光錐**。

## Ground truth（沿用 / 比照，勿重寫）

- **雷射分層的 look 數學（要比照的樣板）**：`LaserScatterConfig`（`LightingModels.swift:1765`）+ `LaserScatterMath`（`:1792`），含 `beamsVisible(_:)`（`:1803`，gate = `intensity > 0.03`）、`coreRGBA(hex:intensity:config:)`（`:1811`，hue 朝白 lerp）、`sheathRGBA(...)`（`:1824`，飽和 hue、低 alpha、alpha 隨 intensity）、`sheathRadius(coreRadiusMeters:config:)`（`:1832`）。**新的 `SpotBeamScatterMath` 緊鄰它放，沿用同一 `RGBA` 純結構與慣例**（不是 UIKit/RealityKit 依賴）。
- **聚光燈光錐角度單一入口**：`SpotLightRenderMath.coneAngles(beamAngleDegrees:)`（`LightingModels.swift:1739`）回傳 `(inner, outer)`（外錐 10°…60°，內錐 = 外錐 × 0.7）。**體積光錐的兩層直接吃這組角度**：`sheath` 錐用 `outer`、`core` 錐用 `inner`——如此可見光錐與實際 `SpotLight` 的錐角一致（`updateSpotLight`/`addStageSpotLight` 也用同一 `coneAngles`，見 `:1126`、`:1475`）。**不重寫** `coneAngles`。
- **雷射 entity 建置樣板**：`addLaserProjector`（`ImmersiveView.swift:1288`）——core（`_beam_<i>`）+ sheath（`_sheath_<i>`）兩層 `ModelEntity`、`UnlitMaterial`、共用 beam 朝向。顏色 helper `laserCoreUIColor`/`laserSheathUIColor`（`:1356`/`:1362`）把 `LaserScatterMath` 的 `RGBA` 轉 `UIColor`。`updateLaserProjector`（`:1370`）逐 cue 遍歷子實體、換 `UnlitMaterial`、依 `beamsVisible` 開關 `isEnabled`。**新的 beam-cone 建置/更新兩函式照抄此形狀**。
- **聚光燈 entity 與朝向**：`addStageSpotLight`（`ImmersiveView.swift:1112`）建 `spot_<id>`；`spot.orientation = LightEffectSystem.lookOrientation(forward: aim)`（`:1146`），`aim` = `addRigFixture` 算好的 `restingDir`（zone 方向 × `aimOffset`，`:644`）。**體積光錐用同一 `restingDir` 定向、apex 置於 `scenePoint(placement.position)`**，故光錐與 `spot_<id>`、`model_<id>` 完全同源同向。
- **缺失原生 primitive 的既有做法**：RealityKit 無 `generateTorus`，repo 以 `MeshDescriptor` 手建（`FixtureSpatialScene.swift:611` `torusMesh`、`ImmersiveView.swift:800` selection_ring）。**光錐 mesh 亦以 `MeshDescriptor` 手建**（apex 頂點 → base ring 三角扇），比照該樣板；`MeshResource.generate(from:)` 失敗回退 `.generateCylinder`。（若實測 visionOS 26 SDK 有 `MeshResource.generateCone(height:radius:)`，agent 可先一行 compile 驗證後改用；但預設走 `MeshDescriptor`，因 repo 對 RealityKit 缺的 primitive 一貫手建，勿臆測 API 存在。）
- **逐 cue relight 入口**：`apply(_:overrides:groupMasters:to:manualLightNumber:)`（`ImmersiveView.swift:1398`）逐 fixture 呼 `updateSpotLight`（`:1414`），laser 另呼 `updateLaserProjector`（`:1438`）。**新的 `updateSpotBeam` 掛在同一迴圈**（non-laser fixture）。
- **cross-fade 機制**：`updateSpotLight`（`:1460`）在 `withAnimation(Self.animation(for: transition))`（`:1477`）內改 `SpotLightComponent`（`_ImplicitlyAnimatableBuiltinComponent` → 會 cross-fade）。**`UnlitMaterial` 不是隱式可動畫元件**（雷射即 hard-cut），故體積光錐的**換色/開關比照雷射走 hard-cut**（見下方取捨）。
- **重建 signature（SPEC 13）**：`syncRig`（`:568`）的 rebuild signature（`:576`）已含 `aimOffset`（pan/tilt 整數化）+ `manualPosition`。**光錐在 `addRigFixture` 內建置，故旋轉/拖移觸發 rig rebuild 時光錐自動重建、重定向、重定位——無需新增 signature 欄位**。

### 關鍵 footgun
- **① 只 non-laser 才加光錐**：laser 已有可見 beam 扇（`addLaserProjector`），再疊光錐會雙重光束。`addRigFixture` 的 `if fixture.renderModel == .laser` 分支（`:648`）**不加**光錐；`else` 分支（`:665`）才加。laser 的 `spot_<id>` 錐溢光維持現狀。
- **② `UnlitMaterial` 不可隱式動畫**：不要把 `updateSpotBeam` 的換色/`isEnabled` 塞進 `withAnimation`（無效）。光錐 hard-cut，`spot_<id>` 的表面溢光仍 cross-fade——與雷射完全相同的取捨，勿試圖讓 `UnlitMaterial` 跟著 fade。
- **③ 光錐是靜態朝向**：光錐用 `restingDir`，**不跟隨** `LightEffectSystem` 的逐幀 sweep/circle（那些寫進 `SpotLight` 的 orientation，不動光錐幾何）——與雷射 beam 扇同限制（若光錐跟掃、cone 甩而錐溢光甩、但這是 v1 可接受的取捨；見 Caveats）。勿為此改 `LightEffectSystem`。
- **④ alpha 要隨錐寬衰減**：雷射是鉛筆光束（極窄、高 alpha 讀感佳）；聚光燈是寬錐，同 alpha 會像一坨霧。**寬錐 → 較低 alpha**（`SpotBeamScatterMath` 內建 beam-angle 衰減），且整體 alpha 明顯低於雷射 sheath。實機微調（見 Caveats）。
- **⑤ Observation**：純幾何 + 走既有 `apply`/`syncRig` 路徑，無新 `@Observable` 依賴，不需新增 `body` eager-read。

## Work items（單一 agent 序列做完並編譯通過；math 契約先落地，renderer 對著它寫）
擁有 `LightingModels.swift`、`ImmersiveView.swift`、`Tests/LumaStageCoreSmokeTests.swift`。

### 1. `LightingModels.swift`（Foundation-only，已在 smoke 集）— 新 `SpotBeamScatterMath`
放在 `LaserScatterMath`（`:1792`）**之後**、`// MARK: - Dynamic rig`（`:1837`）**之前**（同檔、同區塊慣例）。比照 `LaserScatterConfig`/`LaserScatterMath`：

```swift
// MARK: - Volumetric spotlight beam (haze)

/// 可調「look」常數——聚光燈體積光錐的兩層（core + sheath），比照 `LaserScatterConfig`。
/// smoke 只釘 mapping 的形狀（gate/排序/單調性/範圍），不釘這些值，故實機微調安全。
struct SpotBeamScatterConfig: Equatable {
    /// 滿強度、窄錐時的 sheath 峰值 alpha（明顯低於雷射，因錐寬得多）。
    var sheathAlpha: Double
    /// core alpha（略高於 sheath，讓中心讀得出來，但仍遠低於雷射 core）。
    var coreAlpha: Double
    /// core hue 朝白 lerp 的量（0 = 純 hue，1 = 白）。
    var coreWhiteness: Double
    /// beam-angle alpha 衰減：alpha ×= (1 - widthAlphaFalloff · normalizedWidth)，
    /// normalizedWidth = (outer-10)/50 ∈ 0…1；寬錐 → 較淡，避免整坨霧。
    var widthAlphaFalloff: Double
    /// 光束幾何長度（model 公尺）——固定投射距離，實機依「錐尖到甲板」微調。
    var beamLengthMeters: Double

    static let `default` = SpotBeamScatterConfig(
        sheathAlpha: 0.06,
        coreAlpha: 0.10,
        coreWhiteness: 0.40,
        widthAlphaFalloff: 0.6,
        beamLengthMeters: 9.0
    )
}

/// 純映射：聚光燈 cue 的 `#RRGGBB` + 0…1 intensity + beam angle → 體積光錐兩層所需的數值
/// （core 錐色/alpha、sheath 錐色/alpha、以及兩層錐的底半徑）。Foundation-only，`ImmersiveView`
/// 為唯一消費者。分層理由同雷射：core 較白較亮、sheath 寬而淡把飽和 hue 暈散、消掉硬邊，讓光錐讀
/// 成空氣中的光而非實心錐。**不用粒子**（見根 CLAUDE.md「haze particles removed」）。
enum SpotBeamScatterMath {
    struct RGBA: Equatable { var red, green, blue, alpha: Double }

    /// 光錐全隱藏的 gate（core/sheath 一起消失），比照雷射 `beamsVisible`。
    static func beamVisible(_ intensity: Double) -> Bool { intensity > 0.03 }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func components(hex: String) -> RGBComponents { RGBComponents(hex: hex) ?? .white }

    /// normalizedWidth ∈ 0…1，由外錐角（10°…60°）線性映射，用於 alpha 衰減與比較。
    static func normalizedWidth(beamAngleDegrees: Double) -> Double {
        clamp01((SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).outer - 10) / 50)
    }

    private static func widthScaledAlpha(_ base: Double, beamAngleDegrees: Double, intensity: Double,
                                         config: SpotBeamScatterConfig) -> Double {
        let w = normalizedWidth(beamAngleDegrees: beamAngleDegrees)
        return base * clamp01(intensity) * (1 - clamp01(config.widthAlphaFalloff) * w)
    }

    /// core 錐色：cue hue 依 intensity 調暗、再朝白 lerp；alpha 隨 intensity 與錐寬衰減。
    static func coreRGBA(hex: String, intensity: Double, beamAngleDegrees: Double,
                         config: SpotBeamScatterConfig = .default) -> RGBA {
        let d = components(hex: hex).dimmed(by: clamp01(intensity))
        let w = clamp01(config.coreWhiteness)
        return RGBA(red: d.red + (1 - d.red) * w, green: d.green + (1 - d.green) * w,
                    blue: d.blue + (1 - d.blue) * w,
                    alpha: widthScaledAlpha(config.coreAlpha, beamAngleDegrees: beamAngleDegrees,
                                            intensity: intensity, config: config))
    }

    /// sheath 錐色：飽和 cue hue、低 alpha（隨 intensity 與錐寬衰減）。
    static func sheathRGBA(hex: String, intensity: Double, beamAngleDegrees: Double,
                           config: SpotBeamScatterConfig = .default) -> RGBA {
        let c = components(hex: hex)
        return RGBA(red: c.red, green: c.green, blue: c.blue,
                    alpha: widthScaledAlpha(config.sheathAlpha, beamAngleDegrees: beamAngleDegrees,
                                            intensity: intensity, config: config))
    }

    /// 光錐底半徑（model 公尺）= length · tan(半錐角)。半錐角用 `coneAngles` 的 inner（core）/outer（sheath），
    /// 使可見光錐與實際 `SpotLight` 錐一致。（外錐角視為半錐角以求視覺對齊——實機微調，見 Caveats。）
    static func baseRadius(lengthMeters: Double, halfAngleDegrees: Double) -> Double {
        lengthMeters * tan(min(max(halfAngleDegrees, 1), 89) * .pi / 180)
    }
    static func coreBaseRadius(lengthMeters: Double, beamAngleDegrees: Double) -> Double {
        baseRadius(lengthMeters: lengthMeters,
                   halfAngleDegrees: SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).inner)
    }
    static func sheathBaseRadius(lengthMeters: Double, beamAngleDegrees: Double) -> Double {
        baseRadius(lengthMeters: lengthMeters,
                   halfAngleDegrees: SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees).outer)
    }
}
```

（`RGBComponents`/`.dimmed(by:)` 為雷射同款既有 helper，同 module 直接用。`RGBA` 刻意複製一份而非共用 `LaserScatterMath.RGBA`，讓兩組 look 數學各自獨立可調——與 spec 慣例「一檔一 owner、契約釘死」一致。）

### 2. `ImmersiveView.swift`（`#if os(visionOS)`，不在 smoke 集）— 體積光錐 entity + 逐 cue 更新

**a) 建置**：新 `addSpotBeamCone(name:to:source:aim:beamAngleDegrees:colorHex:)`，緊鄰 `addLaserProjector`（`:1288`）放，照抄其兩層結構：
- container 名 `name`（= `"spotbeam_\(fixture.id)"`）。
- 用 `SpotBeamScatterConfig.default`，`length = sceneLength(config.beamLengthMeters)`。
- 兩層 `ModelEntity`：`sheath`（外錐，radius = `sceneLength(SpotBeamScatterMath.sheathBaseRadius(lengthMeters:beamAngleDegrees:))`，名 `"\(name)_sheath"`）與 `core`（內錐，radius = `coreBaseRadius`，名 `"\(name)_core"`），mesh 皆為手建光錐（見 c）。**先加 sheath 再加 core**（core 疊在上）。
- 定向：光錐 mesh 的 apex 在本地原點、軸沿 +Y、往 +Y 開口 → 用 `orientation(from: SIMD3<Float>(0,1,0), to: simd_normalize(aim))`（既有 helper `:1502`），apex `position = scenePoint(source)`。（若 mesh 建成沿 -Y/±Z，對應調整；以「錐尖貼燈、開口朝 aim」為準。）
- 材質 `UnlitMaterial(color:)`，色用新 helper `spotBeamCoreUIColor`/`spotBeamSheathUIColor`（比照 `laserCoreUIColor`/`laserSheathUIColor` `:1356`/`:1362`，把 `SpotBeamScatterMath` 的 `RGBA` 轉 `UIColor(red:green:blue:alpha:)`；建置時 `intensity: 1`）。
- 光錐**不標陰影**（`markShadowCaster` 勿呼）、**不加** `InputTargetComponent/Collision`（純視覺、不可選、不擋 `lightpick_<n>` 命中）。
- `rig.addChild(container)`。

**b) 呼叫點**：`addRigFixture` 的 **`else`（non-laser）分支**（`:665`），在 `addStageSpotLight(...)`（`:693`）之後呼一次：
```swift
addSpotBeamCone(name: "spotbeam_\(fixture.id)", to: rig,
                source: placement.position, aim: restingDir,
                beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees,
                colorHex: fixture.color.value)
```
laser 分支（`:648`）**不呼**（footgun ①）。

**c) 光錐 mesh helper**：新 `beamConeMesh(length:baseRadius:segments:)`，比照 `torusMesh`（`FixtureSpatialScene.swift:611`）/ selection_ring（`ImmersiveView.swift:800`）的 `MeshDescriptor` 手建：apex 頂點 (0,0,0) + base ring（半徑 `baseRadius`、y = `length`、`segments`（≈24）個點）→ 側面三角扇（apex→ring[i]→ring[i+1]）。回 `(try? MeshResource.generate(from: [descriptor])) ?? .generateCylinder(height: length, radius: baseRadius)`。（底面可省——側錐面已足夠讀出光束；若破面明顯再補底扇。）

**d) 逐 cue 更新**：新 `updateSpotBeam(named:in:colorHex:intensity:beamAngleDegrees:)`，照抄 `updateLaserProjector`（`:1370`）形狀（**不在 `withAnimation` 內** — footgun ②）：
```swift
let visible = SpotBeamScatterMath.beamVisible(intensity)
// 遍歷 container 子實體：名含 "_core" → UnlitMaterial(coreColor)；"_sheath" → sheath；isEnabled = visible
```
core/sheath 色用 `spotBeam*UIColor(hex:colorHex, intensity:intensity, beamAngleDegrees:...)`。beamAngle 傳 `fixture.effectiveFineControl.beamAngleDegrees`。

**e) 掛進 apply**：`apply`（`:1398`）逐 fixture 迴圈內，於 `updateSpotLight`（`:1414`）之後、laser 分支（`:1438`）之外，對 **non-laser** fixture 呼：
```swift
if fixture.renderModel != .laser {
    updateSpotBeam(named: "spotbeam_\(fixture.id)", in: root,
                   colorHex: resolved.color, intensity: resolved.intensity,
                   beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees)
}
```
（`resolved` = 既有 override/groupMaster 解析結果 `:1409`，故光錐正確反映關燈/override/群組 master——與 `spot_<id>` 同源。）

### 3. `Tests/LumaStageCoreSmokeTests.swift` — 新 smoke（記得在 `main()` 註冊）
新 `private static func spotBeamScatterMathDerivesConeLayers()`，比照 `laserBeamMathDerivesCoreAndSheathLayers`（`Tests:182`），釘：
```swift
// gate（與雷射一致）
expect(!SpotBeamScatterMath.beamVisible(0.03), "近黑光錐必須關閉")
expect(SpotBeamScatterMath.beamVisible(0.5), "點亮的燈光錐必須可見")
// 分層：sheath 錐比 core 錐寬（外錐 > 內錐）
let L = 9.0
expect(SpotBeamScatterMath.sheathBaseRadius(lengthMeters: L, beamAngleDegrees: 40)
       > SpotBeamScatterMath.coreBaseRadius(lengthMeters: L, beamAngleDegrees: 40),
       "sheath（外錐）必須比 core（內錐）寬")
// core 較白、sheath 保飽和
let core = SpotBeamScatterMath.coreRGBA(hex: "#FF0000", intensity: 1, beamAngleDegrees: 40)
expect(core.green > 0 && core.blue > 0, "白熱 core 必須把非 hue 通道抬向白")
let sheath = SpotBeamScatterMath.sheathRGBA(hex: "#FF0000", intensity: 1, beamAngleDegrees: 40)
expect(sheath.green < 0.0001 && sheath.blue < 0.0001, "sheath 必須保留飽和 hue")
// alpha 低、隨 intensity 遞增
expect(sheath.alpha < 0.15, "sheath alpha 需低，讀成暈光不是實心錐")
expect(SpotBeamScatterMath.sheathRGBA(hex: "#FF0000", intensity: 0.5, beamAngleDegrees: 40).alpha < sheath.alpha,
       "較暗 cue → 較淡光錐")
// alpha 隨錐寬衰減：同 intensity 下寬錐 alpha < 窄錐 alpha
expect(SpotBeamScatterMath.sheathRGBA(hex: "#FF0000", intensity: 1, beamAngleDegrees: 120).alpha
       < SpotBeamScatterMath.sheathRGBA(hex: "#FF0000", intensity: 1, beamAngleDegrees: 5).alpha,
       "寬錐必須比窄錐更淡")
// 半徑隨 beam angle 與長度遞增
expect(SpotBeamScatterMath.sheathBaseRadius(lengthMeters: L, beamAngleDegrees: 120)
       > SpotBeamScatterMath.sheathBaseRadius(lengthMeters: L, beamAngleDegrees: 5),
       "寬 beam → 大底半徑")
expect(SpotBeamScatterMath.sheathBaseRadius(lengthMeters: 18, beamAngleDegrees: 40)
       > SpotBeamScatterMath.sheathBaseRadius(lengthMeters: 9, beamAngleDegrees: 40),
       "長光束 → 大底半徑")
// determinism + 無效 hex 回退白
expect(SpotBeamScatterMath.coreRGBA(hex: "#3366FF", intensity: 0.7, beamAngleDegrees: 30)
       == SpotBeamScatterMath.coreRGBA(hex: "#3366FF", intensity: 0.7, beamAngleDegrees: 30),
       "相同輸入需確定性")
let bogus = SpotBeamScatterMath.sheathRGBA(hex: "not-a-hex", intensity: 1, beamAngleDegrees: 40)
let white = SpotBeamScatterMath.sheathRGBA(hex: "#FFFFFF", intensity: 1, beamAngleDegrees: 40)
expect(bogus == white, "無效 hex 需回退白")
```
在 `main()`（`Tests:9-10` 附近，緊接 `laserBeamMathDerivesCoreAndSheathLayers()`）加 `spotBeamScatterMathDerivesConeLayers()`。**無新檔**（math 在已納入 smoke 集的 `LightingModels.swift`），故 README 的 smoke 編譯指令清單不變。

## Constraints / 並行
- 單一 agent 序列：三檔共用新 `SpotBeamScatterMath` 契約，math（WI-1）必須先落地，renderer/test 對著它寫。
- **禁用 `ParticleEmitterComponent`**（全場 haze 粒子與逐束粒子皆已試過並移除——不受場景光照、1:1 尺度呈離軸噪點；根 CLAUDE.md 明列「Don't re-add per-beam haze particles without an ask」）。
- **禁用 visionOS 27-only API**：`SpotLightComponent.SurroundingsLight`、`Shadow.lightSize`/`quality`、`SpotLightComponent.ProjectiveTexture` 皆不存在於 visionOS 26，勿觸碰。光錐純 `UnlitMaterial` 幾何。
- **不重寫**：`LaserScatterMath`/`LaserScatterConfig`、`SpotLightRenderMath.coneAngles`/`lumens`、`updateSpotLight` 的 `SpotLight` cross-fade（`:1477`）、`addStageSpotLight` 的 `SpotLight`/`LightEffectComponent`、`syncRig` signature、`validate()`、cue 編輯、`LightEffectSystem`、`OpenAILightingService`/`MusicShowBuilder`（生成不 author 光錐、光錐純由 renderer 依 cue 值推導）。
- **可見光束必須跟隨**：(1) cue 切換 → `updateSpotBeam` 換色/開關（hard-cut，見取捨）；(2) `aimOffset` 旋轉（SPEC 13）與 (3) `manualPosition` → 兩者已在 `syncRig` rebuild signature，光錐於 `addRigFixture` 重建即自動重定向/重定位——**不需新增 signature 欄位或新 eager-read**。
- **cross-fade vs hard-cut（已決定）**：光錐材質 hard-cut（`UnlitMaterial` 非隱式可動畫、比照雷射）；`spot_<id>` 的表面錐溢光仍走 cue cross-fade。此不一致與雷射現狀相同、可接受（v1）。
- `LightingModels.swift` 維持 Foundation-only；renderer 改動限 `#if os(visionOS)`。本 spec 無新 UI 文案（純幾何）。

## Verification
- **smoke**：新 `spotBeamScatterMathDerivesConeLayers` → 跑 README「smoke 編譯集」指令（清單不變），印 `LumaStageCoreSmokeTests passed`、exit 0。
- **完整 build**：
  ```
  xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' \
    -derivedDataPath /tmp/lumastage-dd build
  ```
  → `** BUILD SUCCEEDED **`（Multipeer `Sendable`、MCSession 含 `error:` 字樣行為既有非錯誤，忽略）。
- **實機**（Vision Pro，見下方 Caveats 全屬 [需實機]）：
  - fullStage 模式下，每盞**開啟**的 non-laser 聚光燈都有可見的半透明空中光錐（core 亮 + sheath 暈），**關燈時光錐消失**（`beamVisible` gate）。
  - 光錐顏色/亮度隨 cue 切換更新；`aimOffset` 旋轉（「Light N turn right 60」）與桌面編輯器拖移（`manualPosition`）後，光錐**重定向/重定位**與 `model_<id>`/`spot_<id>` 一致。
  - laser 仍只有其 beam 扇（**無**額外雙重光錐）。
  - 12 盞滿編制的觀感與 FPS 可接受（見 Caveats 效能）。

## Caveats
- **全部視覺數值 [需實機]**：`SpotBeamScatterConfig` 的 `sheathAlpha`(0.06)/`coreAlpha`(0.10)/`coreWhiteness`(0.40)/`widthAlphaFalloff`(0.6)/`beamLengthMeters`(9.0) 與「外錐角視為半錐角」皆為初值。以「fullStage 下光束讀得出路徑、不糊成一坨霧、寬洗光不刺眼」為基準微調；smoke 只釘 mapping 形狀，微調安全。
- **12 盞效能 [需實機]**：core+sheath = 每盞 **2 個額外錐 mesh**，12 盞滿編 → 24 個半透明 overdraw 面。若實機 FPS 吃緊：(a) 降到**單層錐**（只留 sheath）；(b) 只對 key light（`LightingFixtureVisualModel.isKeyLight`，`LightingModels.swift:1885`）加光錐；(c) 降 `segments`。三者皆不動 math 契約。
- **roomSpill/passthrough 行為（已決定 v1）**：光錐在 **fullStage 與 roomSpill 都顯示**（比照雷射 beam 扇——不受 `SurroundingsLightPolicy.includesOpaqueVenue`（`ImmersiveView.swift:85`）閘控）。理由：光錐是燈具自身的空中發光幾何，非不透明場館的一部分。**但** passthrough 下真實房間沒有煙幕介質、且甲板/backdrop 被隱藏，浮在真房間裡的光錐是否突兀 → [需實機] 判斷；若要改成 room-spill 淡出/隱藏，**正規做法是擴充 Foundation-only `SurroundingsLightPolicy`**（新增如 `includesVolumetricBeams(in:)` + smoke），renderer 依它 gate `spotbeam_*`.isEnabled，勿把模式判斷寫進 view（沿用 README「dual immersion modes」慣例）。此擴充**不在**本 spec 範圍，除非實機判定需要。
- **光錐 hard-cut**：cue 換色時光錐材質瞬切、`spot_<id>` 表面溢光 cross-fade，兩者微不同步（同雷射現狀，可接受）。若要光錐也 fade 需自建逐幀 material 動畫系統——延後。
- **靜態朝向、不跟隨動態效果**：光錐用 resting aim，`LightEffectSystem` 的 panSweep/circle 逐幀 sweep 只動 `SpotLight` orientation，**不動光錐**（同雷射 beam 扇 v1 限制）。移動頭在高能 cue 掃動時，錐溢光掃而可見光錐不掃——v2 若要光錐跟掃，需把 effect 輸出也寫進光錐 orientation（另開）。
- **AI 重生成取代 rig**：換 fixture 集合時光錐隨 `syncRig` 依新 cue 重建（同 `model_<id>`/`spot_<id>`），無殘留。
- **`generateCone` 可用性未證實**：本 spec 走 `MeshDescriptor` 手建光錐（repo 對 RealityKit 缺的 primitive 一貫做法）。若 agent 實測 visionOS 26 SDK 有 `MeshResource.generateCone(height:radius:)` 且編譯通過，可改用以簡化——但預設不臆測其存在。
