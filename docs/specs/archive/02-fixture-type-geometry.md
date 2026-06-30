# SPEC 02 — 燈具型號專屬幾何上台（B4）

> Status: done

**Goal**：場上的燈看起來就是它的型號——搖頭光束燈、LED PAR、頻閃燈條、觀眾爆閃、雷射各有外形,而非目前的通用 stand/moving-head 形狀。大幅提升沉浸感與專業感。

## Ground truth
- `FixtureRealityModel.makeEntity(for: LightingFixtureVisualModel) -> Entity` — `LumaStage/FixtureSpatialScene.swift`(`#if os(visionOS)`),為「燈具觀星窗」建 RealityKit 模型;每型號建一次、快取、`clone(recursive:)` 發出,並 recenter 到視覺 bounds、等比縮放填滿體積。
- `ImmersiveView.addRigFixture(_:lightNumber:at:to:)` 目前依 zone/型號建**通用**幾何:`addFrontLightStand`(FOH 三腳架 par-can)、`addMovingHeadFixture`(吊掛搖頭)、`addLaserProjector`(雷射有可見光束扇,**保留**)。每盞另有 `spot_<id>`、`light_label_<n>`、`lightpick_<n>`、`LightEffectComponent`。
- `scenePoint`/`sceneLength`/`orientation(from:to:)`、`stageScale = 1.0`、`markShadowCaster`。

## Work items
### 1. `FixtureSpatialScene.swift`（owner A）— 提供「上台版」工廠
觀星窗的模型是「填滿 0.7m 體積」尺寸,上台需要真實燈具尺寸(約 0.3–0.5m)。新增:
```swift
/// A stage-scale clone of the fixture-type model, sized to ~`targetHeight` metres (scene units) and
/// aimed so its front points along `aim`. Reuses the cached observatory geometry.
static func makeStageFixture(for model: LightingFixtureVisualModel, targetHeight: Float, aim: SIMD3<Float>) -> Entity
```
細節:`makeEntity(for:)` clone → 量 `visualBounds` → 等比縮放到 `targetHeight` → 朝向 `aim`(模型「正面」軸對到 aim;若模型正面是 +Z,用 `orientation`-style 對齊;在此檔內補一個 from→to 四元數 helper,或讓呼叫端傳朝向)。回傳一個容器,呼叫端設位置。

### 2. `ImmersiveView.swift`（owner B）— 用型號幾何取代通用形狀
`addRigFixture` 內:`.laser` 維持 `addLaserProjector`(可見光束扇);其餘型號改用 `FixtureRealityModel.makeStageFixture(for: fixture.renderModel, targetHeight: sceneLength(0.4), aim: simd_normalize(scenePoint(placement.aim) - scenePoint(placement.position)))`,放到 `placement.position`,加 `markShadowCaster`(遞迴 mark 子 ModelEntity)。`spot_<id>`/label/`lightpick_<n>`/`LightEffectComponent` 與選取環**全部維持不變**(它們是獨立實體)。移除/取代 `addFrontLightStand`/`addMovingHeadFixture` 的呼叫(函式可留作 fallback 或刪)。
- 維持:FOH 型號(frontFresnel/ledFresnel/spotBarrel/audienceBlinder)仍應「站在」觀眾區(有腳架感)——若型號模型本身不含支架,可在容器下加一根簡單立柱(沿用 `strut`),或接受懸浮、實機再調。

## Constraints / 並行
- owner A 先提供 `makeStageFixture`;owner B 對簽名寫。不動模型層/AppModel。`#if os(visionOS)`。

## Verification
- 完整 build → SUCCEEDED(此為純 RealityKit,smoke 不覆蓋)。

## Caveats
- 縮放比例、朝向、是否需腳架、軟陰影開銷(型號幾何面數比通用形狀高,× 4–12 盞)**需實機驗**。若效能吃緊:對非 key light 降 shadow 或限制有型號幾何的燈數。
