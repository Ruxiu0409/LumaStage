# SPEC 05 — 音樂理解 → 自動生成整場演出 + 鎖定燈具（B1，旗艦）

**Goal**：使用者丟一首歌 → **裝置端離線**用 WWDC26 `MusicUnderstanding` 框架分析 → 自動生成「屬於那首歌」的多 cue 舞台演出（依段落/調性/能量/節拍）→ 真實節拍鎖相播放，cue 隨段落自動走。外加**鎖定燈具**（數量/種類）——某些情境使用者已知道自己有什麼設備，生成一律遵守。對應 MAIC「最具創新獎」旗艦敘事：裝置端、隱私、離線、第一方音樂理解。

> 風險控管（最高優先）：**確定性的「分析→演出」是骨幹**——用真實音樂分析（段落、調性、pace、樂器、節拍）以樣板映射出多 cue look，**AI 不在/分析失敗也能跑**。AI 逐 cue 精修是可選層。內建示範曲**預分析成 JSON 打包**，現場零失敗（不依賴框架即時跑）。

## Ground truth

### 已完成可沿用
- **A1 動態效果**：`LightEffect`/`LightEffectKind`/`LightEffectOutput`/`LightEffectEngine.output(_:at:)`、`LightEffectPlan.effects(for:)` — `LightEffect.swift`。`LightEffectComponent`/`LightEffectSystem`（每幀 `time += deltaTime`，render thread）— `LightEffectSystem.swift`（`#if os(visionOS)`）。
- **節拍格 + 鎖拍數學（本 spec owner A 已完成、smoke 綠、已在 smoke 集）**：`MusicBeatClock { bpm, startOffset, beatHz, beatPhase(at:), beatIndex(at:) }` + `enum MusicBeatSync { static func output(_ effect: LightEffect, clock: MusicBeatClock, at time: Double) -> LightEffectOutput }`（strobe 落拍、chase 每拍一次、sweep 每拍一圈、連續無跳變）— `MusicBeatClock.swift`（Foundation-only）。
- **生成契約**：`LightingLookGenerating`（`LightingAIService.swift`，可注入）、`LightingLookDraft.makeValidatedLook(...)`、`LightingLook`/`LightingCue`/`FixtureGroup`/`FixtureColor`/`FixtureFineControl`/`StageState`/`LumaStageProject` — `LightingModels.swift`。`LightingFixtureVisualModel`（型號列舉）、`FixtureRole`、`StageZone` — `LightingModels.swift` / `LightingFixtureCatalog.swift`。
- **AppModel**：`@MainActor @Observable`，`stageState`、`cues`、`selectedCueId`、`selectCue(id:)`、`goToNextCue()`、`appendCue()`、`replaceLightingLook(...)`、`openProject(id:)`/`generate(from:)`/`closeProject()` 的 reset 點（`lightOverrides=[:]`/`resetGroups()`/`selectedLightNumber=nil`）— `AppModel.swift`。
- **composer 工具列**：`VisionAIComposerBox.topBar`（capsule/circle bordered 按鈕、`lumaGazeTarget()`、tint）— `VisionAIComposerBox.swift`。

### WWDC26 `MusicUnderstanding` 框架（owner B 對此盲寫，已釘準）
`@available(iOS 27.0, *)`，**支援 visionOS**。全裝置端、離線、隱私。
```swift
import MusicUnderstanding
let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
let session = try await MusicUnderstandingSession(asset: asset)
let results: SessionResult = try await session.analyze()        // 全維度
// 或 try await session.analyze(for: [.rhythm, .structure])     // 只算需要的（較快）

public struct SessionResult: Codable, Sendable {
    public let instrumentActivity: InstrumentActivityResult?
    public let key: KeyResult?
    public let loudness: LoudnessResult?
    public let pace: PaceResult?
    public let rhythm: RhythmResult?
    public let structure: StructureResult?
}
public struct RhythmResult: Codable, Sendable {
    public let beats: [CMTime]; public let bars: [CMTime]; public let beatsPerMinute: Float?
}
public struct StructureResult: Codable, Sendable {
    public let sections: [CMTimeRange]; public let segments: [CMTimeRange]; public let phrases: [CMTimeRange]
}
// KeyResult: [RangedValue<KeySignature>]，KeySignature{ tonic, mode(major/minor) }
// PaceResult: ranged 0..1；InstrumentActivityResult{ ranges:[Instrument:[CMTimeRange]], activity:[Instrument:[TimedValue<Float>]] }
// LoudnessResult{ integrated, momentary, shortTerm, peak }（LUFS）；TimedValue(value+CMTime)、RangedValue(value+CMTimeRange)
```
**Footgun**：`analyze(for:)` 沒要的維度回 `nil`。各 result property 名（上）以 WWDC26 session 253 為準；若實機簽名有出入，**只調整 `MusicUnderstandingService` 這層轉換**，Foundation 模型不動。`KeySignature.mode`/`Instrument`/`PaceResult` 內部成員名不確定 → owner B 取值時容錯（`Mirror`/可選鏈/預設值），拿不到就給中性預設，不可讓整個分析 throw。

---

## 架構總覽（依賴 + 檔擁有權）

純可判定邏輯（分析鏡像、show 規劃、燈具鎖定、確定性 show 組裝）全進 **Foundation-only + smoke**；框架/音訊/RealityKit 為薄平台層。平台層在我的環境**無法 headless 編譯/執行**，靠最後完整 Xcode 27 build + 實機驗。

```
匯入 url ──▶ SongAnalyzing.analyze(url) ──▶ SongAnalysis (Foundation, Codable)
   │            (平台: MusicUnderstandingService 包框架；或內建曲 cached JSON)
   ├──▶ SongAnalysis.makeBeatClock() ─▶ MusicBeatClock ─▶ MusicSyncClockSource（render thread 讀）─▶ LightEffectSystem 鎖拍
   └──▶ ShowPlan.make(from:) ─▶ [CueBrief] ─▶ MusicShowBuilder.buildLook(plan:rig:) ─▶ LightingLook(多 cue)
                                                          │ (確定性骨幹；RigConstraint.enforce 套用)
                                                          └─(可選) AI 逐 cue 精修：LightingLookGenerating
   播放: MusicSyncEngine(AVAudioPlayer) ─每段落邊界─▶ AppModel.goToCue(段落 index)（main 計時）
```

## Work items

### P1 — Foundation 核心（owner A2，**單一 agent 擁有以下全部新檔 + LightingModels 加欄位**，一起編到 smoke 綠）
這些型別互相依賴，交給一個 agent 一致地寫 + 迭代 smoke。全部 `import Foundation` 無平台 import。

1. **`LumaStage/SongAnalysis.swift`** — 平台無關的分析鏡像（秒為單位 `Double`，非 CMTime）：
   ```swift
   enum SectionKind: String, Codable { case intro, verse, chorus, bridge, breakdown, drop, outro, unknown }
   enum MusicKeyMode: String, Codable { case major, minor, unknown }
   struct SongSection: Codable, Equatable {
       var start: Double; var end: Double          // 秒
       var kind: SectionKind
       var pace: Double                             // 0..1（聽感快慢，取段內平均）
       var loudness: Double                         // 0..1（normalized，取段內平均）
       var keyMode: MusicKeyMode
       var dominantInstruments: [String]            // e.g. ["drums","vocals"]（可空）
       var duration: Double { max(0, end - start) }
   }
   struct SongAnalysis: Codable, Equatable {
       var title: String
       var duration: Double                         // 秒
       var bpm: Double?                             // 來自 beatsPerMinute（可 nil）
       var beatTimes: [Double]                      // 每拍秒數
       var barTimes: [Double]                       // 每小節秒數
       var sections: [SongSection]                  // 已依 start 排序、不重疊（轉換層保證）
       /// 由 bpm + 第一拍 offset 推 MusicBeatClock；bpm 缺則由 beatTimes 估（相鄰拍間隔中位數）。
       /// 無拍可推 → nil（呼叫端退回自累加時間）。
       func makeBeatClock() -> MusicBeatClock?
   }
   /// 可注入的分析邊界（同 LightingLookGenerating 模式）。Foundation-only 協定；平台 impl 在 MusicUnderstandingService。
   protocol SongAnalyzing { func analyze(url: URL, title: String) async throws -> SongAnalysis }
   enum SongAnalysisError: Error { case unsupported, empty, analysisFailed(String) }
   ```
   - `makeBeatClock`：bpm 有效→`MusicBeatClock(bpm: bpm!, startOffset: beatTimes.first ?? 0)`；bpm nil 但 `beatTimes.count>=2`→由間隔中位數算 bpm；否則 nil。
   - smoke：makeBeatClock 三條路徑；Codable round-trip；section duration。

2. **`LumaStage/ShowPlan.swift`** — 段落 → cue brief：
   ```swift
   struct CueBrief: Codable, Equatable {
       var name: String                 // 顯示名（依 SectionKind 給繁中：開場/主歌/副歌/橋段/…）
       var startTime: Double            // 段落起點秒（播放時據此自動走 cue）
       var energy: Double               // 0..1 = f(pace, loudness)（鉗 0...1）
       var keyMode: MusicKeyMode
       var dominantInstruments: [String]
       var suggestedIntensity: Double   // 0..1（high energy→亮）
       var highEnergy: Bool             // energy >= 0.6（對齊 LightEffectPlan.highEnergyThreshold）
   }
   struct ShowPlan: Codable, Equatable {
       var cues: [CueBrief]
       /// 由分析建。把過短/過多段落合併到 minCueSeconds / maxCues（預設 6）內，且至少 2 個 cue
       /// （沿用 look 至少需要可選 cue 的不變式）。空分析 → 一個中性 cue。
       static func make(from analysis: SongAnalysis, maxCues: Int = 6, minCueSeconds: Double = 8) -> ShowPlan
   }
   ```
   - `energy = clamp(0.6*pace + 0.4*loudness)`；`suggestedIntensity = 0.35 + 0.6*energy`（鉗 0...1）。
   - 合併規則：相鄰同 kind 合併；段落短於 minCueSeconds 併入前一個；多於 maxCues 時，依時長挑最長的前 maxCues 個邊界。
   - smoke：段落→cue 數在 [2, maxCues]；energy/intensity 範圍；短段合併；空分析給 1→補成 2 中性 cue。

3. **`LumaStage/RigConstraint.swift`** — 鎖定燈具：
   ```swift
   struct RigConstraint: Codable, Equatable {
       var fixtureCount: Int?                       // nil = 不限
       var allowedModels: [LightingFixtureVisualModel]   // 空 = 不限型號
       var isUnconstrained: Bool { fixtureCount == nil && allowedModels.isEmpty }
       /// 把一個 look 的每個 cue 夾到限制：型號不在白名單者，映射到白名單中「同 role 最近」者
       /// （用 FixtureRole 對應；無對應取白名單第一個）；數量超過 fixtureCount 時，依 rig 順序裁掉尾端，
       /// 不足時不補（生成端負責多給）。維持每 cue 的 fixtureGroups 一致（同一組 fixtureId 集合）。
       func enforce(on look: LightingLook) -> LightingLook
   }
   ```
   - 型號→role 對應沿用 `LightingFixtureVisualModel` 既有 role 標註（catalog）。`enforce` 為**冪等**（已合規不變）。
   - smoke：超量裁切到 fixtureCount；非白名單型號被改寫成白名單同 role；`isUnconstrained` 時原樣返回；冪等；每 cue fixtureId 集合一致。

4. **`LumaStage/MusicShowBuilder.swift`** — **確定性** show 組裝（零失敗骨幹，不需 AI）：
   ```swift
   enum MusicShowBuilder {
       /// 由 ShowPlan 造一個多 cue LightingLook：每個 CueBrief → 一個 cue。
       /// 每 cue 用一套依 (SectionKind, keyMode, energy) 決定的調色盤 + 強度 + 動態效果
       /// （high energy 段給 strobe/chase/sweep；低能量給穩定主光+背景）。固定一組對稱 rig
       /// （L/R 對稱，沿用 rig-symmetry 慣例），rig 大小依 maxFixtures（預設 8）。最後套 RigConstraint.enforce。
       /// 全程經 LightingLookDraft.makeValidatedLook(...) → validate()，保證可渲染。
       static func buildLook(plan: ShowPlan, rig: RigConstraint, lookName: String) throws -> LightingLook
   }
   ```
   - 調色盤：major→暖偏白、minor→冷偏藍紫；chorus/drop→飽和高彩 + 動態；verse→中性穩定；intro/outro→低強度暖。
   - 動態：highEnergy 段對 mover/strobe 型號給 `LightEffect`（sweep/strobe/chase，沿用 `LightEffect.suggested` 的型號邏輯或直接指定），低能量段 `.none`。
   - rig 對稱：成對放置，避免單一 laser 落單（沿用 rig-symmetry 慣例）。
   - smoke：cue 數 == plan.cues 數；每 cue validate 過；major/minor 影響色溫（暖/冷可判定）；highEnergy 段有動態 effect、低能量段無；套 RigConstraint 後合規。

5. **`LumaStage/LightingModels.swift`（同一 agent，加欄位）** — `LumaStageProject` 加 `var rigConstraint: RigConstraint = RigConstraint(fixtureCount: nil, allowedModels: [])`（additive；同 SPEC 03 的 back-compat 手法：若 `LumaStageProject` 走 synthesized Codable 且新欄位非可選，加 `decodeIfPresent ?? 預設` 的容錯 decoding，舊存檔解為預設「不限」）。**不改**其他建構點（給預設）。
   - smoke：舊 project JSON（無 rigConstraint）解為 unconstrained。

6. **smoke 集登記**：把 `SongAnalysis.swift`/`ShowPlan.swift`/`RigConstraint.swift`/`MusicShowBuilder.swift` 加進 `docs/specs/README.md` 的 smoke 指令 **與** 根 `CLAUDE.md` 測試段的 `swiftc` 清單；新測試 func 全部註冊進 `Tests/LumaStageCoreSmokeTests.swift` 的 `main()`。
   - **Verify**：repo root 跑 smoke → `LumaStageCoreSmokeTests passed`。

### P2 — 平台層（P1 綠後；B1/B2 檔互斥可並行）

7. **`LumaStage/MusicUnderstandingService.swift`（owner B1，新檔，`#if os(visionOS) || os(iOS)`）** — `SongAnalyzing` 實作：
   - `import MusicUnderstanding`（用 `#if canImport(MusicUnderstanding)` 包，buildable 即使 SDK 缺）。
   - `analyze(url:title:)`：建 `AVURLAsset`（`AVURLAssetPreferPreciseDurationAndTimingKey: true`）→ `MusicUnderstandingSession(asset:)` → `analyze()`；把 `SessionResult` 轉成 `SongAnalysis`：`CMTime.seconds`→Double、`CMTimeRange`→(start,end)；section kind 由 framework 標籤字串映射到 `SectionKind`（容錯，未知→`.unknown`）；pace/loudness 取段內平均並 normalize 到 0..1；key mode 由 `KeyResult` 在該段時間點取值；dominant instruments 由 `InstrumentActivityResult` 取段內活躍度 top-N（容錯：拿不到→空陣列）。
   - **內建示範曲（零失敗）**：`CachedSongAnalyzer`（或 static）載入打包的 `demo-song-analysis.json`（owner B1 產生一份合理的假分析或對某 bundled 曲預分析；無真曲時手寫一份 ~150s、128bpm、intro/verse/chorus/bridge/chorus/outro 的 JSON）解成 `SongAnalysis`，給「使用內建示範曲」用。也提供 `PreviewSongAnalyzer`（mock）給預覽。
   - 容錯：任何維度取值失敗給中性預設，不整體 throw（除非 session 建不起來 → `SongAnalysisError.analysisFailed`）。
   - **不在 smoke 集**（imports MusicUnderstanding/AVFoundation）。

8. **`LumaStage/MusicSyncEngine.swift`（owner B2，新檔，`#if os(visionOS) || os(iOS)`）** — 播放 + 跨執行緒時鐘：
   ```swift
   @MainActor @Observable final class MusicSyncEngine {
       private(set) var isPlaying: Bool
       private(set) var currentTime: Double
       private(set) var clock: MusicBeatClock?
       func load(url: URL, clock: MusicBeatClock?)   // 建 AVAudioPlayer，設 AVAudioSession .playback
       func play()    // 播放；錨定 MusicSyncClockSource（startMediaTime = CACurrentMediaTime()）
       func stop()    // 停止；清 MusicSyncClockSource
       /// 回呼：播放時間越過某段落起點時呼叫（owner C 接到 AppModel.goToCueIndex）。main 計時（DisplayLink/Timer）。
       var onSectionBoundary: ((Int) -> Void)?
       func setSectionStarts(_ starts: [Double])
   }
   /// 跨執行緒（render thread 可讀）時鐘來源；engine 寫、LightEffectSystem 讀。
   final class MusicSyncClockSource {
       static let shared: MusicSyncClockSource
       // lock 保護的快照；play 設、stop 清。
       func setActive(startMediaTime: Double, clock: MusicBeatClock)
       func clear()
       /// render thread：現在的音樂時間 + clock，或 nil（未啟用/已停）。time = CACurrentMediaTime() - startMediaTime。
       func snapshot() -> (time: Double, clock: MusicBeatClock)?
   }
   ```
   - 用 `OSAllocatedUnfairLock`（或 `NSLock`）保護快照；`CACurrentMediaTime()`（QuartzCore）跨執行緒安全。
   - 播放與視覺鎖相共用同一 `CACurrentMediaTime()` 時基 → 不漂移（恆定偏移可接受；長曲微漂移列 caveat）。
   - **不在 smoke 集**。

### P3 — 接線 ∥ UI（P2 後；C 與 D 對下方 AppModel 契約並行）

9. **`LightEffectSystem.swift`（owner C）** — 拍同步：`update` 仍 `time += deltaTime`（**沒開音樂時不回歸**）；每幀讀 `MusicSyncClockSource.shared.snapshot()`，有值→用 `MusicBeatSync.output(component.effect, clock:, at: musicTime)`，無值→現有 `LightEffectEngine.output(component.effect, at: time)`。**Observation footgun 不適用**（System 不在 SwiftUI body；直接讀 shared 即可）。

10. **`AppModel.swift`（owner C）** — 音樂 + 設備檔介面（**D 對此契約寫**）：
    ```swift
    // 觀察用
    var isMusicShowActive: Bool          // 已載入分析 + 有 show
    var isMusicPlaying: Bool             // = engine.isPlaying
    var musicBPM: Double?                // = analysis.bpm
    var currentSongTitle: String?
    var rigConstraint: RigConstraint     // 鏡射目前 project 的；setRigConstraint 改並存回 project
    // 動作
    func importSong(url: URL) async      // 經 songAnalyzer.analyze → 存 analysis → ShowPlan.make → MusicShowBuilder.buildLook(rig:) → replaceLightingLook → engine.load(clock:) → setSectionStarts；錯誤走既有 fail(...)
    func useBuiltInDemoSong() async      // 同上，用 CachedSongAnalyzer
    func playMusicShow()                 // engine.play()；onSectionBoundary→selectCue(該 index)
    func stopMusicShow()                 // engine.stop()
    func setRigConstraint(_:)            // 存 project + 重套 enforce 到目前 look（或下次生成生效）
    func clearMusicShow()                // stop + 丟 analysis/plan（openProject/closeProject 呼叫）
    ```
    - 注入 `songAnalyzer: SongAnalyzing`（預設 `MusicUnderstandingService`，可注入 mock）+ `musicSyncEngine`（`#if os(visionOS)` 守衛，比照 AppModel 既有平台守衛）。
    - reset：`openProject`/`closeProject`/`generate` 呼叫 `clearMusicShow()`（沿用 `lightOverrides=[:]` 清除點）；`openProject` 時 `rigConstraint = project.rigConstraint`。
    - `generate(from:)`（手動 AI 生成）末端套 `rigConstraint.enforce(on:)` 後再 `replaceLightingLook`（設備檔對 AI 生成也生效）。
    - **不可** headless 編譯；對 P1/P2 契約寫，靠完整 build 驗。

11. **UI（owner D，`VisionAIComposerBox.swift` + 新 sheet）**：
    - `topBar` 加「音樂」按鈕（`music.note`/`waveform`）：開一個小選單/sheet → 匯入音檔（`.fileImporter`，UTType.audio）或「使用內建示範曲」。匯入後顯示分析中狀態 → 完成顯示 BPM + 段落數 + 播放/停止鍵 + 目前段落名。
    - 播放/停止鍵呼叫 `appModel.playMusicShow()`/`stopMusicShow()`；狀態列顯示 `musicBPM`、`isMusicPlaying`、`currentSongTitle`。
    - 「設備檔」入口（齒輪或專屬鈕）→ `RigConstraintEditorView`（新檔或同檔）sheet：數量 stepper（含「不限」）+ 型號多選（`LightingFixtureVisualModel` 全列），存 `appModel.setRigConstraint(...)`。可在生成前臨時改。
    - 全部繁中、`lumaGazeTarget()`、`accessibilityLabel`、Dynamic Type、Reduce Motion gate 動畫；設計 token 沿用 `LumaStageDesign`。
    - 對 owner C 的 AppModel 契約寫。

## Constraints / 並行
- 一個 agent 一個檔（P2/P3）；P1 的互依純型別交給**單一 agent** 一起寫到 smoke 綠。
- 平台層全在我環境無法 headless 驗 → 靠最後 **完整 Xcode 27 build**（`DEVELOPER_DIR=/Applications/Xcode-beta.app`）＋實機。
- **不改** A1 的 `LightEffect.swift` 數學、`MusicBeatClock.swift`（owner A 已定）。

## Verification
- P1：smoke（含全部新測試）→ `LumaStageCoreSmokeTests passed`。
- 全部：`** BUILD SUCCEEDED **`（visionOS）。
- 實機：真曲分析品質（段落/拍準度）、節拍視覺鎖相與效能（4–12 燈×每幀效果）、cue 自動走場時序、播放長曲是否漂移、設備檔 enforce 後觀感。

## Caveats（實機/刻意延後）
- `MusicUnderstanding` result property/enum 細名若與此 spec 有出入 → **只修 `MusicUnderstandingService` 轉換層**。
- **即時串流 BPM/loudness 反應**（邊播邊驅動亮度包絡）延後；先用整曲預分析。
- **AI 逐 cue 精修**（用 `LightingLookGenerating` 對每個 CueBrief 重生成該 cue）為可選增強層，骨幹是確定性 `MusicShowBuilder`，賽前零失敗。
- 長曲音訊時鐘 vs `CACurrentMediaTime()` 可能微漂移；demo 長度可忽略，必要時改錨到 AVAudioPlayer 自身時間軸。
- 真曲版權：示範用無版權/自有音檔；內建示範曲用預分析 JSON。
