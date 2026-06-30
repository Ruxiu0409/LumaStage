# LumaStage 實作規格集（agent-executable specs）

這個資料夾的每一份 spec 都是**一個可獨立分派給 subagent 的任務**,格式刻意統一,讓 agent 拿了就能做、做完能驗:

- **Goal** — 一句話目標 + 對應 MAIC 戰略書的哪一項。
- **Ground truth** — 已存在、要「呼叫/沿用」而非重寫的 API/型別/檔案(附 `file:符號`),以及關鍵 footgun。
- **Work items** — 每項標明**擁有哪一個檔**(file ownership,避免並行 agent 互相覆蓋),與**精確契約**(型別名、方法簽名、entity 命名)。
- **Constraints** — 不可動的檔、平台守衛、風格。
- **Verification** — 確切的 build / smoke 指令與通過條件。
- **Caveats** — 只能實機驗證、或刻意延後的部分。

## 共用慣例（所有 spec 適用）

- **平台/工具**:visionOS 27,RealityKit/SwiftUI,Swift 6(`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)。Build 用 Xcode 27:`/Applications/Xcode-beta.app`,經 `DEVELOPER_DIR`。
- **可判定邏輯進 Foundation-only 檔 + smoke test**;SwiftUI/RealityKit view 當薄消費者(專案核心慣例)。
- **使用者字串繁體中文**;FM system prompt / `@Guide` / 解析關鍵字維持英文(見根 `CLAUDE.md`)。
- **設計 token**:`LumaStageDesign`(`lumaFloatingPanel`/`lumaNativeGlass`/`lumaGazeTarget`/`minGazeTarget=60`/tints)。
- **無障礙**:新互動元件一律 `accessibilityLabel`(必要時 hint/value)、≥60pt 注視目標、動畫 gate 在 `@Environment(\.accessibilityReduceMotion)`、非顏色狀態指示(symbol/粗體/checkmark)。
- **Observation footgun**:`RealityView` 的 `update:` closure 不自成 Observation 依賴——任何它要反應的 `@Observable` 狀態,必須在 `body` 以 `let _ = appModel.x` 先讀(見 `ImmersiveView`)。
- **smoke 編譯集(目前)**:
  ```
  swiftc Tests/LumaStageCoreSmokeTests.swift \
    LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
    LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
    LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift LumaStage/LightingPatchSheet.swift \
    LumaStage/LightEffect.swift LumaStage/StageLightAccessibility.swift \
    LumaStage/LightControlCardPlacement.swift LumaStage/FixtureGroups.swift \
    LumaStage/OpenAILightingService.swift LumaStage/FallbackLightingService.swift LumaStage/OpenAIKeychain.swift \
    -o /tmp/smoke && /tmp/smoke    # 印出 "LumaStageCoreSmokeTests passed" 即過
  ```
  新增 Foundation-only 檔時,把它加進這個指令(並更新根 `CLAUDE.md` 的測試段)。
- **完整 build 驗證**:
  ```
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage \
    -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
  ```
  通過條件 `** BUILD SUCCEEDED **`。Multipeer 的 Sendable 警告、以及 MCSession delegate 簽名裡含 `error:` 字樣的行,是既有非錯誤,忽略。
- **並行分派守則**:一個 agent 只擁有一個檔;跨檔依賴用「spec 釘死介面」解決(agent 各自對著契約寫,最後一起編譯整合)。需要同檔多處改時,該檔只給一個 agent。

## 現況基線（已完成,勿重做）

- **S2 多 cue + GO**、**S1 語音指令/朗讀**(`StageVoiceCommand`/`SpeechNarrator`,zh-TW 辨識)、**A2 配接表匯出**(`DMXPatchPlanner`/`LightingPatchSheet`/`PatchSheetExportView`)、**A1 動態效果引擎**(`LightEffect`/`LightEffectEngine`/`LightEffectPlan` + `LightEffectComponent`/`LightEffectSystem`,目前為「依燈具型號×cue 能量」的確定性效果)、**頭顯內就地手動控燈**(`AppModel` 選取+override 方法、`SelectedLightControlView`、`ImmersiveView` 的 `lightpick_<n>`+選取環+attachment)——**都已實作、編譯通過、smoke 綠**。
- **SPEC 04 連續調光 / 捏拉調暗**(`SelectedLightControlView` 連續亮度 `Slider`(0...1,綁 `setManualIntensity`,顯示 % + a11y)+ `ImmersiveView` 捏拉 `lightpick_<n>` 上下調光(`.simultaneousGesture(DragGesture)`,`dragIntensityPerPoint` 係數待實機調)+ 手動 override 走 0.12s 短過場(`apply` 的 `manualTransition`,不動 cue 2.5s 預設))——已實作、**完整 build 綠**(spec 已封存至 `archive/`)。
- **SPEC 06 社會價值 + 全面無障礙**(S1 完成):全 app 無障礙 sweep(`ProjectSelectionView`/`LightingFixtureIntroView`/`FixtureObservatoryView`/`TabletopStageEditorView`/`ContentView`/`PatchSheetExportView` + iPad panel 三檔)——互動元件補 `accessibilityLabel`/hint/value、非顏色狀態(`.isSelected`/symbol)、Dynamic Type(`@ScaledMetric`)、Reduce Motion gate(含 Tabletop 轉盤的 RealityKit `move(to:)`)、≥60pt 注視目標、增高對比變體;**場上每盞燈進 VoiceOver 樹**——`ImmersiveView` 在 `lightpick_<n>` 設 `AccessibilityComponent`(identity label + 每次 relight 更新 value),字串由新 Foundation-only `StageLightAccessibility`(hex→繁中色名 / 標籤組字,smoke-tested)產生;**社會價值敘事** `docs/social-value.md`(誠實底線對齊 `maic-strategy.md` §5)。——已實作、**完整 build 綠**、smoke 綠(spec 已封存至 `archive/`)。VoiceOver 走 RealityKit 場景、極大 Dynamic Type 版面需實機驗。
- **SPEC 09 單燈控制卡:就近顯示 + 可移動**:選燈時的手動控制卡不再寫死正前方 / 每幀彈回——新 Foundation-only `LightControlCardPlacement`(把卡從(可能 5m 高、數米深的)燈拉向使用者、夾到 0.9...1.6 伸手可及高度、側移避開光束;smoke-tested `lightControlCardPlacementStaysReachable`)決定落點;`ImmersiveView` 只在**選取編號改變時**放置一次(`placeLightControlCardIfSelectionChanged`,讀 `lightpick_<n>` 的 root-space 位置),卡掛在一條可抓握小橫桿(`light_control_handle`)下,橫桿帶 `ManipulationComponent`(只平移、`releaseBehavior = .stay`)所以卡可被拖到任意位置不被彈回、且滑桿/按鈕仍可點;`apply` 只讓**受控的那盞燈**走 0.12s 短過場(其餘維持 cue cross-fade,GO 不再硬切整桿);`lightpick_<n>` pick proxy 移到燈本體、`addLightLabel` 桁架燈標籤下移避桁架。——已實作、smoke 綠(`LightControlCardPlacement.swift` 已納入 smoke 編譯集)。`** BUILD SUCCEEDED **`、抓握手感、固定 viewer 原點與 `dragIntensityPerPoint` 係數需實機驗。
- **SPEC 01 AI 指定動態效果（A1 延伸）**：AI 在生成時可為每盞燈每個 cue 指定動態效果（掃動/畫圓/頻閃/chase/無），取代「依燈具型號×cue 能量」的確定性預設。`FixtureGroup` 加可選 `effect: LightEffect?`（additive/Codable/舊資料解 nil）；`LightEffectPlan.effects(for:)` 改 `fixture.effect ?? suggested(...)`（AI 指定優先、無則回退、不回歸）；`LightingLookDraft.Fixture` 帶 `effect`、`fixtureGroup(from:)` 設值；`@Generable` 加 `GeneratedMovement{none,sweep,circle,strobe,chase}`（per-cue）+ `draftFixture` 映射（容錯：未知/缺值→none）+ instructions 補一句（英文）；`ImmersiveView.apply` 改用共用 `LightEffectPlan.effects(for:)[index]` 與 debug 同源。2 個新 smoke（draft/Codec/舊 JSON 回退 nil；Plan 授權優先）。**不動** `LightEffectSystem.swift`/`AppModel.swift`。——已實作、**完整 build 綠**、smoke 綠（spec 已封存至 `archive/`）。AI 是否在對的時刻指定 movement、多盞同時動態效能、on-device 巢狀結構生成穩定度需實機驗。
- **SPEC 10 OpenAI 雲端後端（預設）+ FM 備援**：在既有 `LightingLookGenerating` seam 後新增 `OpenAILightingService`(OpenAI Responses API `/v1/responses` + strict `json_schema`,Foundation-only/`URLSession`,錯誤一律 `.generationFailed`(不冠 Apple Intelligence 前綴)、共用 `LightingLookDraft.makeValidatedLook()`+`validate()`,count/range/hex 不重寫;model `gpt-5.5`)、`FallbackLightingService`(OpenAI primary + FM secondary,任一可用即 `.available`,失敗退回,`result.source` 反映實際生成者)、`OpenAIKeychain`(`kSecClassGenericPassword`+`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)、`OpenAISettingsView`(金鑰輸入/清除 + `ProjectSelectionView` 齒輪入口)。`AppModel.makeDefaultLightingClient` 改注入組合器、`generationSource` 預設 `.openAI`,**generate/gate/fail/cue 編輯不動**;4 個新 smoke(decode+validate / refusal / 超範圍走 validator / fallback)。三個新 Foundation-only 檔已納入 smoke 集。——已實作、**完整 build 綠**、smoke 綠(spec 已封存至 `archive/`)。**live OpenAI endpoint(gpt-5.5 真 key/網路)、設定畫面手感、刻意延後的「強制裝置端(隱私模式)」開關需實機補驗;正式上架前金鑰應改走自家 proxy。**
- **SPEC 08 編組推桿與現場控制模型（核心路徑）**：以「編組」為快速控制單位，把群組 master 折入既有 cue→override 解析（**不另起平行 state**）。新 Foundation-only `FixtureGroups.swift`：`FixtureGroupMask` + `StandardFixtureGroup`(前光/背景洗/上舞台/動態/全部,從 role/zone/renderModel auto-seed,空組略過)、`autoSeed(from:)`、`effectiveMaster(forFixtureId:groups:masters:)`(只有被 ride 的組貢獻、多組取 **HTP**、預設 1.0)，以及 `LightOverride.resolved(cueColor:cueIntensity:groupMaster:)`(載重不變式 `final = isOff ? 0 : intensity ?? cueIntensity×master`;單燈覆寫壓過 master、顏色不受 master 影響)。`AppModel`：`groups`/`groupMasters` + `setGroupMaster`/`bumpGroup`/`clearGroupMaster`/`effectiveGroupMaster(forLight:)`/`groupMasterByLight()`，於 `openProject`/`generate` auto-derive+清空(沿用 lightOverrides 清除點)。`ImmersiveView.apply` 折入 groupMaster(body eager-read `groupMasters` 避 Observation footgun)。`LumaControlCommand.setGroupMaster/bumpGroup` + `LumaSyncCoordinator` 接收 + round-trip。iPad 新 `PanelFaderBankView`(5 支垂直群組推桿,各自 `DragGesture` 支援多指同時 ride、bump、latching solo、GO footer,推桿靜止於 **full=1.0** 對齊比例 master 中性值) 置於 `PanelLightingView` 頂部。2 個新 smoke(`groupAutoSeedFromRoleZone`/`groupMasterResolutionAndPrecedence`)+ round-trip 擴充。——已實作、**完整 build 綠**、smoke 綠(`FixtureGroups.swift` 已納入 smoke 集;spec 已封存至 `archive/`)。**多指同時 ride 手感、bump 閃光時序、solo 取捨需實機驗。刻意延後(非核心)：語音群組名詞/solo 解析、群組整體換色(載重不變式只調亮度,「movers to blue」需逐燈色覆寫,另開)、頭顯內空間化「圈燈成組」UI、GO 升為頭顯 composer 常駐鍵。**

- **SPEC 02 燈具型號專屬幾何上台（B4）**：場上 rig 的燈改用「型號專屬幾何」取代通用 stand/moving-head 形狀。`FixtureSpatialScene` 新增 `makeStageFixture(for:targetHeight:aim:)`——沿用觀星窗的 `build*` 程序幾何，另開 `stageCache`(去掉縮圖的三分之四傾斜+填滿縮放)、量 `visualBounds` 等比縮到 `targetHeight`、用本地 shortest-arc `rotation(from:+Z,to:aim)` 對朝向,回傳容器供呼叫端定位。`ImmersiveView.addRigFixture`:`.laser` 維持 `addLaserProjector`(可見光束扇);其餘型號改走 `makeStageFixture(fixture.renderModel, sceneLength(0.4), aim)`、`scenePoint(placement.position)` 定位、新 `markShadowCasterRecursively` 遞迴標陰影;FOH 型號(frontFresnel/ledFresnel/spotBarrel/audienceBlinder)補一根 `strut` 立柱(floor→燈下)避免懸浮。`spot_<id>`/`light_label_<n>`/`lightpick_<n>`/選取環/`LightEffectComponent` 為獨立實體,**全未動**;舊 `addFrontLightStand`/`addMovingHeadFixture` 留作 fallback(已不被呼叫)。——已實作、**完整 build 綠**(純 RealityKit,smoke 不覆蓋;spec 已封存至 `archive/`)。**縮放(0.4m 取最長軸,寬型燈會偏矮寬)、各型號 lens 是否朝台且不翻轉/打滾、FOH 立柱頂端是否貼合模型底、型號幾何面數×4–12 盞的軟陰影開銷(吃緊時對非 key light 降 shadow)需實機驗。**

## Spec 生命週期

- 每份 spec **完成後(實作 + build 綠 + smoke 過)就移到 `docs/specs/archive/` 或直接刪除**——完成的 spec 不留在待辦清單裡(完成內容反映在「現況基線」與程式碼/git)。
- 範例:本功能集的「頭顯內就地手動控燈」**原始實作 spec 與其收尾打磨 spec(`00-manual-light-control-polish.md`,review 4 條)皆已完成並刪除**——功能反映在「現況基線」與程式碼/git。
- 一份 spec 開工前,可在檔頭加 `> Status: in-progress / done`;done 即封存。

## 優先序

| 序 | Spec | 對應 | 工作量 | 風險 |
|---|---|---|---|---|
| P1 | `03-ai-lighting-tutor.md` | B2 · 教育/社會價值 | S | 低 |
| P3 | `05-music-sync.md` | B1 · 依賴 A1 | L | 高(分析準度→降級內建曲) |
| P3 | `07-tabletop-place-lights.md` | C2 · 空間 wow | L | 中 |

> 風險高/實機相依者,先在實機把 A1 + 房間溢光驗過再排(見根 `docs/demo-runbook.md`)。
