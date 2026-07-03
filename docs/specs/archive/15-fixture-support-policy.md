# SPEC 15 — 燈具支撐守則「沒有燈可以浮空：truss 下吊掛、離開 truss 就落地燈架」

> Status: done

**Goal**：把「燈具的物理支撐」升級成一條 Foundation-only、可判定、renderer 與桌面編輯器共用的守則——**任何燈具的解析位置若水平落在 truss footprint 下方且夠高 → 吊掛在 truss（無柱）；否則 → 從地板長出落地燈架柱到燈下**。呼應使用者需求「燈只能在 truss 上，其他地方就要有燈架，不能隨意生成（浮空）」。

**現況缺口**：`ImmersiveView.addRigFixture`（`ImmersiveView.swift:615`）只用一個 `isFrontOfHouse` 布林分岔——**只有 FOH zone 會長出立柱**（`ImmersiveView.swift:658-667`）。側台 boom（`stageLeft`/`stageRight`，`RigPlacement.placement` 於 `LightingModels.swift:1942-1951` 給 `y = topY + 1.2`）與任何被拖到非 truss 位置的 `manualPosition` 燈具**懸空、無任何支撐**。支撐判斷不是一個純函式，也沒 smoke 覆蓋。

**AI 決策（已與使用者確認）**：**維持 AI 只選 zone**（`GeneratedZone` 五種不動），靠本 spec 的支撐 policy 在 renderer 保證不浮空——**不動** `FoundationModelsLightingService.swift`。

## Ground truth（沿用，勿重寫）

- **擺位單一入口**：`RigPlacement.resolvedPlacement(fixture:slot:count:layout:)`（`LightingModels.swift:1959`，Foundation-only、smoke-tested）回傳 model 公尺的 `(position, aim)`；renderer（`ImmersiveView.syncRig`，`ImmersiveView.swift:600`）與桌面編輯器（`TabletopStageScene.syncFixtures`，`TabletopStageEditorView.swift:655`）都經此入口。**本 spec 的 policy 吃的是它回傳的 `position`**，故 zone 燈與手動拖曳燈一體適用。
- **truss 幾何來源**：`StageObject.trussEndpoints: [Vector3Meters]`（`StageBuilderModels.swift:943`）回傳每段 truss 的 `[起點, 終點]`。portal 的腿在寬度兩端、頂桿橫跨寬度、Z 都約在 upstage 線。`RigPlacement.placement` 已用 `layout.objects.flatMap(\.trussEndpoints)` 取 `upstageZ = …z.min()`、`maxTrussY = …y.max()`（`LightingModels.swift:1911-1912`）——**沿用同一來源**推 footprint 包圍盒。
- **舞台頂面**：`RigPlacement.placement` 內 `topY = (stageBase.position.y) + size.height/2`（`LightingModels.swift:1910`）——policy 需要同樣的 `topY` 當「離地高度」基準；用同一 `stageBase` 推法。
- **立柱 helper 已存在，直接呼叫**：`ImmersiveView.strut(named:from:to:radius:hex:intensity:) -> ModelEntity?`（`ImmersiveView.swift:954`）。現有 FOH 柱即用它：`from: (x, 0, z)`、`to: (x, columnTopY, z)`、`radius: 0.035`、`hex: "#3A3D42"`、`intensity: 0.72`（`ImmersiveView.swift:660-663`）。**新的通用燈架沿用同參數**。
- **標籤方向**：`addLightLabel(number:near:mountedAbove:to:)`（`ImmersiveView.swift:679`）——`mountedAbove: true` 標籤浮在燈上（適合站地燈），`false` 標籤下沉避開 truss（適合吊掛）。現以 `isFrontOfHouse` 決定；**改由 policy 的 `isFloorStand` 決定**（更正確：側台 boom 現在也算站地）。
- **桌面 proxy**：`TabletopStageScene.makeFixtureProxy(named:hex:)`（`TabletopStageEditorView.swift:782`）建錐狀代理容器，`fixtureEntityName(_:) = "tabletopfixture_<id>"`（`:585`）。`syncFixtures` 每次把 `container.position = scenePoint(placement.position)`（`:661,671`）。**燈架在編輯器做成 container 的子實體**，隨拖曳自動跟著（見 WI-3）。

### 關鍵 footgun
- **① 別用 zone 當支撐判準**：`manualPosition` 可把 `stageBack`（原本吊掛）的燈拖到台前浮空，也可把 `stageFront` 拖到 truss 下。所以支撐**必須看解析後的 `position` vs truss footprint**，不能看 `fixture.zone`。
- **② footprint 的 XZ margin 要小**：truss 頂桿很薄，側台 boom 的 X（`±width*0.55`）只略超出 portal 腿的 X（`±width*0.5`），Z 也只 downstage 於 upstage 線約 0.45m。margin 過大（>0.4）會把側台 boom 誤判成吊掛。用 **小 margin（~0.35m）且同時要求 X-in-band ∧ Z-in-band ∧ 夠高**，三者皆過才吊掛。實機微調（見 Caveats）。
- **③ Observation**：本改動走 `syncRig`/`syncFixtures`，位置變動已在既有 signature/rebuild 路徑（SPEC 13 已把 `manualPosition` 納入 syncRig signature）。policy 是純函式、無新 `@Observable` 依賴，不需新增 eager-read。

## Work items（單一 agent 序列做完並編譯通過；四檔共用新 policy 契約，policy 須先落地）
擁有 `LightingModels.swift`、`ImmersiveView.swift`、`TabletopStageEditorView.swift`、`Tests/LumaStageCoreSmokeTests.swift`。

### 1. `LightingModels.swift`（Foundation-only，已在 smoke 集）— 新支撐 policy
放在 `RigPlacement` enum **之後**（緊鄰，同檔）：

```swift
/// Foundation-only：一盞燈在解析位置上如何被物理支撐，讓場上沒有燈浮空。
/// 位置（model 公尺）水平落在 truss footprint 內、且離地夠高 → 吊掛在 truss；否則 → 從地板長出落地燈架。
enum FixtureSupport: Equatable {
    case hangFromTruss
    /// 從 y = 0 到 `topY`（model 公尺）在燈具的 XZ 立一根落地燈架柱。
    case floorStand(topY: Double)

    var isFloorStand: Bool { if case .floorStand = self { return true }; return false }
}

extension RigPlacement {
    /// 可調常數（實機微調，見 spec Caveats）
    static let trussHangMarginMeters = 0.35   // footprint XZ 外擴；小值避免側台 boom 誤判吊掛
    static let hangMinAboveDeckMeters = 1.0    // 低於此高度即使在 footprint 下也算落地（避免地面燈被判吊掛）
    static let standTopGapMeters = 0.18        // 柱頂距燈底留隙（沿用 FOH columnTopY 的 0.18）

    /// 所有 truss 端點的 XZ 包圍盒 + 頂高（model 公尺），無 truss 則 nil。
    static func trussFootprint(in layout: StageLayout)
        -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double, topY: Double)? {
        let pts = layout.objects.flatMap(\.trussEndpoints)
        guard !pts.isEmpty else { return nil }
        return (pts.map(\.x).min()!, pts.map(\.x).max()!,
                pts.map(\.z).min()!, pts.map(\.z).max()!,
                pts.map(\.y).max()!)
    }

    /// 一盞燈在解析位置的支撐方式。吊掛需同時：XZ 在 footprint±margin 內、且離甲板 >= hangMinAboveDeck。
    static func support(forPosition position: Vector3Meters, layout: StageLayout) -> FixtureSupport {
        // topY 用與 placement 相同的 stageBase 推法。
        let stageBase = layout.objects.first { $0.type == .stageBase }
        let size = stageBase?.size ?? StageObjectSize(width: 6, depth: 3, height: 0.8)
        let topY = (stageBase?.position.y ?? size.height / 2) + size.height / 2

        let m = trussHangMarginMeters
        if let f = trussFootprint(in: layout),
           position.x >= f.minX - m, position.x <= f.maxX + m,
           position.z >= f.minZ - m, position.z <= f.maxZ + m,
           position.y >= topY + hangMinAboveDeckMeters {
            return .hangFromTruss
        }
        return .floorStand(topY: max(0.3, position.y - standTopGapMeters))
    }
}
```

（若 `trussEndpoints`/`StageObjectSize`/`Vector3Meters` 型別在別檔，import 同 module 即可；均為 Foundation-only。`minX/maxX` 用 `min()!/max()!` 因已 `guard !pts.isEmpty`。）

### 2. `ImmersiveView.swift`（`#if os(visionOS)`，不在 smoke 集）— 通用燈架取代 FOH-only
改 `addRigFixture`（`:615`）：
- **刪掉** `let isFrontOfHouse = …`（`:623`），改成一次求 policy：
  ```swift
  let support = RigPlacement.support(forPosition: placement.position, layout: layout)
  ```
  （`addRigFixture` 需要 `layout`——目前簽名沒有；從呼叫端 `syncRig`（`:606`）多傳一個 `layout:` 參數進來，該處已有 `layout` in scope。）
- **非 laser 分支**（`:642-668`）：把原本 `if isFrontOfHouse { …strut… }` 改成 `if case .floorStand(let topY) = support { …strut… }`，柱 `to:` 用 `Vector3Meters(x: pos.x, y: topY, z: pos.z)`（沿用 radius 0.035 / hex "#3A3D42" / intensity 0.72 / 名 `model_<id>_post`）。
- **laser 分支**（`:637-641`）：laser 現在完全沒有柱。加同一 `if case .floorStand(let topY) = support` → 在雷射發射頭下也長一根 `laser_<id>_post`（同 strut 參數）。（雷射預設 `stageBack` 吊掛時 → 無柱，維持現狀。）
- **標籤方向**（`:679`）：`mountedAbove: isFrontOfHouse` → `mountedAbove: support.isFloorStand`。
- **pick proxy / spotlight / 效果**（`:670-687`）不動。

### 3. `TabletopStageEditorView.swift`（`#if os(visionOS)`，不在 smoke 集）— 編輯器 diorama 一致顯示燈架
讓桌面編輯器與 1:1 舞台觀感一致（使用者就是在這裡擺燈）。在 `TabletopStageScene.syncFixtures`（`:627`）定位 proxy 之後（`:671` 後），依同一 policy 增/減 container 內的一根燈架子實體：
- 求 `let support = RigPlacement.support(forPosition: placement.position, layout: layout)`。
- container 的子實體名 `"fixture_stand"`：
  - `.floorStand` → 若不存在則建一根細圓柱（半徑 ~scene 對應 0.035m、灰 `#3A3D42` `UnlitMaterial` 或現有 proxy 材質風格），**高 = container.position.y**（即 scenePos.y，燈到地板距離），本地置中於 `y = -container.position.y / 2`（從燈底往地板延伸；因它是 container 子實體，container 在 XZ 拖曳時燈架自動跟著、恆在燈正下方）；已存在則更新高度/位置、`isEnabled = true`。
  - `.hangFromTruss` → 若存在則 `isEnabled = false`（或移除）。
- 不影響選取高亮/`sceneToMeters`/`moveFixture`（拖曳提交仍走既有路徑；燈架在 sync 重算，故拖離/拖進 truss 後放手即更新——見 Caveats）。
- 需要 `layout` 已在 `syncFixtures(_:look:layout:selectedFixtureId:)` 簽名（`:627` 已有 `layout`）。

### 4. `Tests/LumaStageCoreSmokeTests.swift` — 新 smoke（記得在 `main()` 註冊）
新 `private static func fixtureSupportPolicyClassifiesTrussVsStand()`：
```swift
let layout = StageLayout.defaultStudentOutdoor()
// 用 placement 產生各 zone 的實際位置，再問 support：
let back  = RigPlacement.placement(zone: .stageBack,  slot: 0, count: 1, layout: layout).position
let left  = RigPlacement.placement(zone: .stageLeft,  slot: 0, count: 2, layout: layout).position
let front = RigPlacement.placement(zone: .stageFront, slot: 0, count: 2, layout: layout).position
expect(RigPlacement.support(forPosition: back,  layout: layout) == .hangFromTruss, "上舞台 truss 位吊掛")
expect(RigPlacement.support(forPosition: left,  layout: layout).isFloorStand,      "側台 boom 落地燈架")
expect(RigPlacement.support(forPosition: front, layout: layout).isFloorStand,      "FOH 落地燈架")
// 手動位置：truss 正下方且高 → 吊掛；台前高處（footprint 外）→ 落地。
if let f = RigPlacement.trussFootprint(in: layout) {
    let underTruss = Vector3Meters(x: (f.minX + f.maxX)/2, y: f.topY - 0.2, z: (f.minZ + f.maxZ)/2)
    expect(RigPlacement.support(forPosition: underTruss, layout: layout) == .hangFromTruss, "truss 正下方高處吊掛")
}
let floatingDownstage = Vector3Meters(x: 0, y: 3.0, z: 5.0)  // 台前遠處高空
if case .floorStand(let topY) = RigPlacement.support(forPosition: floatingDownstage, layout: layout) {
    expect(topY > 0.3 && topY <= 3.0, "落地柱頂在燈下")
} else { fatalError("台前高空應落地燈架，不可浮空") }
```
（若 `defaultStudentOutdoor` 的實際數值讓側台 boom 邊界卡在 margin 附近而 fail，微調 `trussHangMarginMeters` 至側台 boom 穩定落地——這正是實機也要的行為。）

## Constraints / 並行
- 單一 agent 序列：四檔共用新 policy 契約，policy（WI-1）必須先落地，其餘對著它寫。
- `LightingModels.swift` 維持 Foundation-only。renderer / 編輯器改動限 `#if os(visionOS)`。
- **不重寫**：`RigPlacement.placement` 的 zone 數學、`resolvedPlacement`、`validate()`、cue 編輯、`FoundationModelsLightingService`（AI 維持選 zone）、`LightEffectSystem`。
- 保留既有 FOH 柱的視覺參數（radius/hex/intensity），只是套用範圍從「FOH zone」擴成「policy 判定的 floorStand」。
- 使用者字串繁體中文；本 spec 無新 UI 文案（純幾何）。

## Verification
- **smoke**：新 `fixtureSupportPolicyClassifiesTrussVsStand` → `LumaStageCoreSmokeTests passed`（`LightingModels.swift`/`Tests` 已在編譯集，無需改指令；見 README 共用 smoke 指令）。
- **完整 build**：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build` → `** BUILD SUCCEEDED **`（Multipeer 既有警告忽略）。
- **實機**：開任一專案 → 上舞台燈仍**吊掛**在 truss 下（無柱）；**側台 boom 與 FOH 現在都站在落地燈架上**（無浮空）；雷射若在非 truss 位也長柱；進桌面編輯器把一盞燈**拖離 truss** → 放手後長出燈架，**拖回 truss 正下方** → 燈架消失改吊掛；AI 生成/音樂秀的任一 rig 皆無浮空燈。

## Caveats
- **門檻需實機微調**：`trussHangMarginMeters`(0.35)/`hangMinAboveDeckMeters`(1.0)/`standTopGapMeters`(0.18) 為初值。側台 boom 的 X/Z 只略超出 truss footprint，若某 layout 下被誤判吊掛，縮小 margin；若上舞台燈被誤判落地，放大 margin 或降 `hangMinAboveDeck`。以「側台 boom 穩定落地、上舞台穩定吊掛」為驗收基準。
- **拖曳中不即時、放手才更新**：桌面編輯器燈架在 `syncFixtures` 重算，`moveDrag` 只在 release 走 `moveFixture` → `replaceLightingLook` → 下一輪 sync 才切吊掛/落地。拖曳過程燈架維持上一狀態（v1 可接受；即時重算延後）。
- **多桁架 layout 自動泛化**：footprint 取所有 `trussEndpoints` 的 XZ 包圍盒，故若未來有橫跨全台的頂棚桁架，台中央高處的燈也會正確判吊掛——無需改 policy。
- **AI 重生成取代 manualPosition**：換 fixture 集合時手動位置隨舊 look 一起被取代（同既有行為），support 依新解析位置重算，仍保證不浮空。
- **雷射柱**：雷射預設吊掛（stageBack）時無柱；只有被移到非 truss 位才長柱。可見光束扇朝向不受本 spec 影響。
- **編輯器燈架為單純圓柱**：桌面 diorama 的燈架是抽象細圓柱（與 proxy 錐狀一致風格），非型號專屬幾何；1:1 舞台用既有 `strut` 立柱。
