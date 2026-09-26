# LumaStage

**LumaStage 是一款 visionOS 的 AI 舞台燈光設計 app**：戴上 Apple Vision Pro 進入一個 1:1 的夜間室外舞台數位孿生，用語音或文字對 AI 描述你要的氛圍，雲端模型即時生成一整套 cue-based 的燈光 look 並以動畫過場打在虛擬 rig 上；再丟一首歌，app 會在裝置端離線分析、生成一場節拍鎖相的多 cue 演出。目標使用者是沒有完整設備與場地的學生活動與燈光初學者——在頭顯裡把整套秀設計、預覽、走完。

- **主 app**：visionOS 26（部署目標 26.0）
- **iPad 伴侶**：iPadOS 26（可選的「LumaStage Control」即時控制面板，透過 Multipeer Connectivity 連線；visionOS app 為單一事實來源，沒有它也能獨立運作）
- **工具鏈**：Xcode 26.4（visionOS 26 SDK）
- **AI 生成**：**OpenAI 雲端獨佔**（model `gpt-5.5`；Apple 裝置端 Foundation Models 已於本版完整移除）

> 本 README 是**入口地圖**，幫你快速掌握整個專案的樣貌與檔案分工。深度架構、慣例與 footgun 的**單一事實來源（authoritative SoT）是根目錄的 [`CLAUDE.md`](CLAUDE.md)**；需要細節時往那裡與 [`docs/specs/`](docs/specs/) 查。

---

## 作者與分工

兩人合作開發：

- **蔡承曄（[@Ruxiu0409](https://github.com/Ruxiu0409)）**：整體架構與 `AppModel` 狀態流、AI 燈光生成（Foundation Models → OpenAI 雲端）、1:1 沉浸舞台渲染、語音指令、音樂秀 pipeline、iPad 控制面板伴侶、燈具觀星窗、smoke 測試骨架。
- **[@Yacolate0519-cmd](https://github.com/Yacolate0519-cmd)**：桌面舞台編輯器（架設／編程／播放三階段工作流程）、迷你燈光 previz、表演者人偶、舞台結構詞彙、體積光束。

開發過程大量使用 AI coding agent（Claude Code、Codex）協作：由我們撰寫規格（[`docs/specs/`](docs/specs/)）與架構約束（[`CLAUDE.md`](CLAUDE.md)、[`AGENTS.md`](AGENTS.md)），agent 依規格實作，再由我們驗收與 smoke 測試把關。

---

## 核心功能全貌

### (a) 沉浸式 1:1 舞台數位孿生 + 雙沉浸模式
一個 RealityKit 打造的等比夜間舞台（真 `SpotLight` 燈具、桁架、甲板、表演者人偶），一模一米對應真實一米。兩種模式（`StageImmersionMode`）：`.fullStage`（預設，`.full` 不透明夜舞台場景）與 `.roomSpill`（`.mixed` 透視你的真實房間並調暗）。
> 注意：visionOS 27 上虛擬燈可打亮真房間，本 26 港版該 API（`SurroundingsLight`）已移除，房間溢光只切透視 + 調暗，**不會**把 rig 的光投到真房間。

### (b) AI 燈光生成（OpenAI 雲端）
語音／文字 prompt（支援中英混講）→ `OpenAILightingService`（Responses API + strict `json_schema` 結構化輸出，model `gpt-5.5`）**一次呼叫生成整套多 cue look**（雲端 schema：2–4 個 cue、4–8 盞 rig，每盞授權 `enabled`/`intensity`/`colorHex`/`beamAngle`/`gobo`）→ 經 `LightingLook.validate()` 驗證後以過場動畫套用。需在 `ProjectSelectionView` 齒輪 → `OpenAISettingsView` 設定 Keychain 金鑰才可用。每次生成都附一段「業界詞 + 白話 + 設計理由」的教學式 explanation。

### (c) 音樂秀 pipeline（旗艦）
丟一首歌 → **裝置端離線**用 WWDC26 `MusicUnderstanding` 框架分析（`SongAnalysis`）→ `ShowPlan`（段落 → cue、依 pace/響度算能量）→ `MusicShowBuilder`（**確定性、AI-free**，保證可渲染、L/R 對稱 rig，cue id `cue_music_<i>`）→ `MusicSyncEngine` + `MusicBeatClock` 節拍鎖相播放，cue 隨段落邊界自動走場。歌曲來源：檔案匯入 / 裝置音樂庫（MediaPlayer）/ 內建示範曲（`DemoTrackSynth` 程序合成，不綁版權 MP3）。`RigConstraint` 為專案級鎖定設備檔，也套用到 AI 生成結果。

### (d) 桌面舞台編輯器（ARKit 桌上 diorama）
「架設」階段用 ARKit 把一個小型 3D 舞台孿生**擺在你的真實桌面上**編輯，是一個獨立的 mixed passthrough 沉浸空間（編輯時**取代** 1:1 舞台空間）。它承載完整的**三階段工作流程**（`WorkflowPhase`）：
- **架設 (rigging)** — 重塑 `StageLayout`、擺放/移動/複製/鏡射 rig 燈具、加結構。
- **編程 (programming)** — 逐 cue 調每盞燈的顏色/角度/亮度（燈具位置鎖定）。
- **播放 (playback)** — 連續 cue-list 播放 + 一條播放進度時間軌。

編輯器內含：**迷你燈光 previz**（每盞燈依目前 cue 畫一支半透明彩色光束錐，切 cue 就地預覽整套 look）、可拖曳的**表演者人偶**（位置存進 layout，前光/側光 aim 會朝人偶微調）、擴充的**結構詞彙**（側塔 / 地面 boom 架 / 中場第二道桁架，皆由既有桁架段組成）、**方向微調鍵 / 連接節點吸附 / 拖入桁架自動吊掛 / 就地瞄準**。編輯持久化後 1:1 舞台立即反映。

### (e) 就地單燈控制 + 語音指令 + 單燈旋轉
在頭顯裡直接點一盞燈即選取，彈出原生單例控制卡（`SelectedLightControlView`）調開關/亮度/顏色。英文/中文單燈指令走 `LightCommand.parse`（「turn off light 2」「set light 1 to blue」「dim light 2 to 30%」「blackout」「把 Front Light 改成紅色」…）。**單燈旋轉**：「Light N turn right/left/up/down M degrees」持久化為 `aimOffset`，燈頭幾何 + 光束一起轉。

### (f) 體積光束（空中可見光）
- **雷射**（`.laser`）：發射頭 + 一扇 core（白熱核心）+ sheath（低透明度光暈）雙層圓柱光束，在空氣中看得到光——demo 的 show-stopper。數學在 `LaserScatterMath`。
- **一般聚光燈**：同樣的幾何式做法推廣成半透明**體積光錐**（`SpotBeamScatterMath`），讓整組 rig 都有真實舞台的煙幕光束觀感。
> 兩者都走幾何路線；per-beam 粒子霧氣曾試過並**刻意移除**（1:1 尺度下呈離軸噪點、不受場景光照），勿在無明確需求下重加。

### (g) iPad 控制面板伴侶（Multipeer）
可選的「LumaStage Control」iPad app，透過本地 P2P（Multipeer Connectivity，無伺服器/帳號）即時鏡射 host 狀態並送出編輯。含 Chat 分頁與 Lighting 分頁（頂部五支垂直群組推桿 `PanelFaderBankView` + GO / 播放）。

### (h) 燈具觀星窗
在進舞台前的燈具指南（`LightingFixtureIntroView`）點任一燈具卡，開兩個獨立可移動的視窗：一個體積 3D 模型窗（雙手縮放/旋轉，鎖定平移像轉盤）+ 一張可翻頁的資訊卡，教學真實燈具型號的名稱、角色與用途。

---

## 架構

### 慣例：可測核心 vs. 薄視圖
本專案的定義性慣例——**所有純邏輯（資料模型、驗證、幾何、渲染順序、排版數學、AI 解析、工作流 policy、時間軌數學）都放在 `Foundation`-only 檔並配 smoke 測試**；SwiftUI / RealityKit 視圖只當薄消費者。這讓 smoke 測試能不開模擬器 headless 跑。新增行為時，把「可判定的部分」抽進這些 model 檔並補 smoke，別埋進 view。

### 狀態流
`AppModel`（`@MainActor @Observable`）是**單一事實來源**，由 `LumaStageApp` 以 `.environment(appModel)` 注入。視圖從不直接改燈光狀態——一律呼叫 `AppModel` 方法，委派給 `StageState`，`StageState` **每次 mutate 都重新 `validate()`**。

```
語音/文字 prompt → AppModel.generate → OpenAILightingService → LightingLook
  → RigConstraint.enforce → StageState.replaceLightingLook（驗證）→ AppModel（Observable）→ 視圖重繪
cue 編輯 → StageState.patchSelectedCue（只動選取 cue、驗證）→ AppModel → ImmersiveView 更新
單燈指令 → LightCommand.parse → AppModel.applyLightCommand → lightOverrides / rotateFixture
```

### 關鍵檔案（Key files）

| 檔案（`LumaStage/`） | 職責 |
|---|---|
| `LightingModels.swift` | 核心資料模型：`LightingLook`/`LightingCue`/`FixtureGroup`/`CuePatch`/`StageState`/`LumaStageProject`，`validate()` 不變式，以及 `RigPlacement`（燈具擺位/支撐/吊掛的唯一入口）、`SpotLightRenderMath`/`LaserScatterMath`/`SpotBeamScatterMath`/`PreviewBeamCone` 等純數學。 |
| `LightingAIService.swift` | Foundation-only 生成契約（`LightingLookGenerating`/`LightingModelAvailability`）與 AI→domain 組裝器 `LightingLookDraft.makeValidatedLook()`。 |
| `OpenAILightingService.swift` | 唯一的生成後端：OpenAI Responses API + strict `json_schema` → DTO → `LightingLookDraft` → 驗證。Foundation-only（`URLSession` 走可注入的 `HTTPSend` seam、金鑰走 `apiKeyProvider`）。 |
| `StageBuilderModels.swift` | 最大的檔：共用舞台幾何（`StageLayout`/`StageObject`/桁架/preset/`ImmersiveStageGeometryPlan`）、沉浸模式 policy（`StageImmersionMode`/`SurroundingsLightPolicy`）、桌面編輯器純邏輯（節點吸附、`StageStructurePreset`、表演者位置）與 space-swap 重試 policy。 |
| `ImmersiveView.swift` | 1:1 舞台 RealityKit 渲染器：`syncRig` 依 fixture 集重建 rig、`apply` 逐 cue 重打光、體積光束/雷射、單燈選取代理。 |
| `AppModel.swift` | 單一事實來源：生成、cue 編輯、單燈 override、群組推桿、音樂秀、cue-list 播放、工作流階段、桌面編輯器狀態、iPad sync 的所有 mutation 方法。 |
| `TabletopStageEditorView.swift` | 桌面 diorama 編輯器（`#if os(visionOS)`）：ARKit 桌面偵測、可選取/拖曳的桁架與燈具代理、迷你 previz 光束錐、表演者代理、結構/燈具新增選單。 |
| `WorkflowPhase.swift` | Foundation-only 的三階段（架設/編程/播放）列舉 + `WorkflowPhasePolicy`（各階段允許哪些操作、對應到哪個沉浸空間）。 |
| `CueTimeline.swift` | Foundation-only 的播放頁時間軌數學（cue 區塊起訖、游標比例、點擊位置→cue）；view 端為 `PlaybackTimelineView.swift`。 |
| `iPadPanel/` + `LumaSync*.swift` | iPad 面板（`LumaPanelApp`/`LumaPanelModel`/`PanelRootView`/`PanelChatView`/`PanelLightingView`/`PanelFaderBankView`，`#if os(iOS)`）與同步層：`LumaSyncProtocol`（wire 型別）、`LumaSyncTransport`（協定 + loopback）、`MultipeerSyncTransport`（真傳輸）、`LumaSyncCoordinator`（host 端觀察 `AppModel` 並收發命令）。 |

---

## 建置與測試

### 兩個 scheme（皆 shared）
- **`LumaStage`** — visionOS 主 app（部署 26.0；連結本地 SwiftPM 套件 `Packages/RealityKitContent`）。
- **`LumaStageControl`** — iPadOS 26.0 控制面板伴侶。

日常在 Xcode GUI build/run 是正常路徑。命令列驗證：

```bash
# 建置驗證（specs 的標準檢查；通過 = "** BUILD SUCCEEDED **"）
xcodebuild -scheme LumaStage \
  -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
```
> 綠 build 裡的已知非錯誤噪音：Multipeer `Sendable` 警告，以及 MCSession delegate 簽名裡含 `error:` 字樣的行——別追。

### Smoke 測試（不需 Xcode）
測試是一套**自製的 `@main` smoke-test harness**（**不是 XCTest**，也不在 Xcode 專案裡）。用 Foundation-only 核心原始檔一起編譯成一個 binary，**從 repo 根目錄執行**：

```bash
swiftc \
  Tests/LumaStageCoreSmokeTests.swift \
  LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
  LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
  LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift LumaStage/LightEffect.swift \
  LumaStage/MusicBeatClock.swift LumaStage/FixtureGroups.swift \
  LumaStage/OpenAILightingService.swift LumaStage/OpenAIKeychain.swift LumaStage/SongAnalysis.swift \
  LumaStage/ShowPlan.swift LumaStage/RigConstraint.swift LumaStage/MusicShowBuilder.swift \
  LumaStage/SongLibrary.swift LumaStage/DemoTrackSynth.swift LumaStage/CuePlayback.swift \
  LumaStage/WorkflowPhase.swift LumaStage/CueTimeline.swift \
  -o /tmp/LumaStageCoreSmokeTests && /tmp/LumaStageCoreSmokeTests
# 成功會印 "LumaStageCoreSmokeTests passed" 並 exit 0
```
每個檢查在 `static func main()` 內**逐行呼叫**（無自動發現）。新增測試：寫一個 `private static func` 並**在 `main()` 註冊**。新增 Foundation-only 檔時，記得把它加進上面的編譯清單（並同步更新 `CLAUDE.md` / `AGENTS.md` 的測試段）。

---

## 文件地圖（哪份看什麼）

| 文件 | 讀它做什麼 |
|---|---|
| **[`CLAUDE.md`](CLAUDE.md)** | **權威架構 SoT**（AI 與人都讀）：分層慣例、狀態流、渲染器 footgun、視窗生命週期、各子系統細節。任何與本 README 衝突時**以它為準**。 |
| [`AGENTS.md`](AGENTS.md) | 給自動化 agent（Codex 等）的**逐條修 issue 協定**：硬規則、工作流程、smoke/build 驗證與誠實回報。 |
| [`docs/specs/`](docs/specs/) | 每個功能的 **agent-executable SPEC**。[`docs/specs/README.md`](docs/specs/README.md) 定義 SPEC 格式並維護**現況基線（已完成功能的 changelog + caveat）**；完成的 SPEC 封存到 `docs/specs/archive/`。 |
| [`docs/system-spec.md`](docs/system-spec.md) | 產品規格書（MVP 範圍、資料邊界、schema、驗收標準）。 |
| [`docs/demo-runbook.md`](docs/demo-runbook.md) | 決賽現場 demo 的「零失敗」操作手冊。 |
| [`docs/issue-sweep-followup.md`](docs/issue-sweep-followup.md) | 最近一輪 issue 大掃除後的**後續 backlog**（實機驗收待辦、殘口、文件衛生）。GitHub 目前 **0 個 open issue**。 |
| [`docs/ipad-control-panel-setup.md`](docs/ipad-control-panel-setup.md) | iPad 伴侶 target 的設定說明。 |
| [`docs/foundation-models-setup.md`](docs/foundation-models-setup.md) | 檔名為歷史遺留；內容實為 **OpenAI 金鑰設定**指南。 |
| [`docs/social-value.md`](docs/social-value.md) | 社會價值與目標使用者論述。 |

> 提示：`docs/dynamic-rig-plan.md`、`docs/brainstorming.md` 是**歷史**規劃/發想文件，狀態可能過時——以 `CLAUDE.md` 與 `docs/specs/README.md` 的基線為準。
