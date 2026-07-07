# SPEC 16 — GO 升為「播放」：cue list 自動連續走場（issue #6）

> Status: in-progress

**Goal**：按下「播放」後，非音樂的一般 look 像真實數位控台的 cue list playback 一樣**自動連續跑**：每個 cue 停留其 follow/hold 時間後自動 follow 到下一個，跑到最後一個 cue 停止（不迴繞），不需每次手動按 GO。提供播放/停止控制；播放中操作者仍可手動 GO。對應 issue #6。

> 風險控管：**可判定的排程邏輯（hold 解析、下一顆 index、能否自動播）全進 Foundation-only `CuePlayback` + smoke**；計時器引擎與 UI 是薄平台層。音樂秀已有 `MusicSyncEngine` 段落邊界自動走場——本 spec 是它的**非音樂對應**，兩者**互斥**（同時只有一條在驅動 cue）。

## Ground truth（已存在、沿用而非重寫）

- **cue 堆疊 + GO**：`StageState.goToNextCue()/goToPreviousCue()`（**會迴繞**）、`selectedCueIndex`、`cueOrder`、`selectCue(id:)` — `LightingModels.swift` / `AppModel.swift`。`AppModel.goToNextCue()`（呼 `announce`）、`applyVoiceCommand(_:)`、`cues`/`selectedCueId`/`selectedCue` — `AppModel.swift`。
- **cue 模型**：`LightingCue{ id, name, transition: CueTransition, fixtureGroups }`（synthesized `Codable`/`Equatable`，memberwise init，**無自訂 decoder**）、`CueTransition.mvpDefault`（2.5s linear）— `LightingModels.swift`。
- **計時器引擎範本**：`MusicSyncEngine`（`@MainActor @Observable`，`Timer` on `RunLoop.main` `.common`、`onSectionBoundary` callback、`play`/`stop`、`MainActor.assumeIsolated`）— `MusicSyncEngine.swift`（**不在 smoke 集**）。音樂秀走場：`AppModel.musicSyncEngine.onSectionBoundary → selectCueAtSectionIndex(index)`；`isMusicPlaying`、`isMusicShowActive`、`playMusicShow()`/`stopMusicShow()`/`clearMusicShow()` — `AppModel.swift`。
- **reset 點**（overlay 清除處，本 spec 的 playback 也要在此停）：`openProject`（`AppModel.swift:638` 附近 `lightOverrides=[:]` + `clearMusicShow()`）、`closeProject`（:673）、`generate`（:998–1002）。
- **iPad 協定/接線**：`LumaControlCommand`（`LumaSyncProtocol.swift:97`，每 case 1:1 對應一個 `AppModel` mutation）、`LumaHostState`（:52）、`LumaSyncCoordinator.apply(_:)`（`.goToNextCue → appModel.goToNextCue()`）、`LumaPanelModel.applyLocally(_:)` 的離線 mock、`PanelFaderBankView` 的 `GoFooter`（GO 鈕，`.borderedProminent`/green/`play.fill`）。
- **語音**：`StageVoiceCommand{ nextCue, previousCue, addCue, readExplanation }` + 中英片語表（`englishPhrases`/`chinesePhrases`）— `StageVoiceCommand.swift`（**在 smoke 集**）。
- **composer topBar**：`VisionAIComposerBox.swift` — 已有「GO」鈕（:123）、cue 選單、「音樂」鈕（:59）、狀態列 `musicStatusChipTitle`（:239）。設計 token `LumaStageDesign`、`lumaGazeTarget()`。
- **round-trip smoke**：`lumaSyncProtocolRoundTrips`（建構 `LumaHostState` / `LumaControlCommand` 並驗 Codec）— `Tests/LumaStageCoreSmokeTests.swift`。

**Footgun**：
- `LightingCue` 加**可選**欄位即可靠 synthesized `Codable` 的 `decodeIfPresent`（Optional 專屬）達成舊 JSON 解 nil——**不需**自訂 decoder（同 SPEC 13 `aimOffset`、SPEC 07 `manualPosition`）。放在 `fixtureGroups` 之後並給 `= nil`，memberwise init 得預設值，既有呼叫端零改動。
- 手動 GO **迴繞**、自動 follow **不迴繞**（跑到最後一顆停）——刻意不對稱：手動可一直循環，自動播放一次跑完。
- `LumaHostState` 是**同 build 即時線路**（非落盤），加欄位給 `= false` 預設即可（memberwise 構造省略；線路一定含）。

## Work items

### WI-1 — Foundation 核心（owner：`CuePlayback.swift` 新檔，**納入 smoke 集**）
`import Foundation` only。純可判定邏輯：
```swift
enum CuePlayback {
    static let defaultHoldSeconds: Double = 6      // cue 未指定 hold 時的預設 follow 時間
    static let minHoldSeconds: Double = 1.5        // 下限：防 0/負值把排程打成空轉
    static let maxHoldSeconds: Double = 600        // 上限：防 NaN/超大值卡死

    /// cue 的有效 follow/hold 秒數：`holdDuration` nil→預設；非有限或超範圍→鉗到 [min,max]。
    static func holdDuration(for cue: LightingCue) -> Double

    /// 自動播放時的下一顆 index（**不迴繞**）：`index+1`，已在最後一顆→`nil`（播放結束）。
    static func nextIndex(after index: Int, count: Int) -> Int?

    /// 能否自動播放：需 ≥2 個 cue。
    static func canAutoPlay(cueCount: Int) -> Bool { cueCount >= 2 }
}
```
- `holdDuration`：`guard let h = cue.holdDuration, h.isFinite else { return defaultHoldSeconds }; return min(max(h, minHoldSeconds), maxHoldSeconds)`。
- smoke（3 條，全註冊進 `main()`）：
  1. `cuePlaybackResolvesHold` — nil→6；0.5→floor 到 1.5；999→cap 到 600；正常 4→4；NaN/inf→6。
  2. `cuePlaybackAdvancesWithoutWrap` — `nextIndex(after:0,count:3)==1`；`nextIndex(after:2,count:3)==nil`；`canAutoPlay(1)==false`、`canAutoPlay(2)==true`。
  3. `cuePlaybackHoldDurationDecodesFromOldJSON` — 一段**不含** `holdDuration` 的 `LightingCue` JSON 解得 `holdDuration==nil`；含值者解得該值；round-trip 保留。

### WI-2 — cue 模型加欄位（owner：`LightingModels.swift`）
- `LightingCue` 於 `fixtureGroups` 後加 `var holdDuration: Double? = nil`（additive、Codable/Equatable synthesized、舊 JSON→nil）。文件註解：秒為單位的 follow/hold 時間，`nil`＝用 `CuePlayback.defaultHoldSeconds`；由 `CuePlayback.holdDuration(for:)` 解析。
- `LightingLook.validate()`：每個 cue 若 `holdDuration != nil`，要求有限且 `0...CuePlayback.maxHoldSeconds`（越界→新 `ValidationError.invalidHoldDuration(Double)`，繁中訊息）。保持驗證器有牙。
- **不動** 既有 cue 建構點（templates/`mvpDemo`/`showcaseDemo`/`MusicShowBuilder`/draft）——全吃 `nil` 預設。

### WI-3 — 計時器引擎（owner：`CuePlaybackEngine.swift` 新檔，**不在 smoke 集**，`@MainActor @Observable`）
`import Foundation`（`Timer`/`RunLoop`）。單發重排計時器，鏡射 `MusicSyncEngine` 形狀，但**無音訊、由 hold 驅動**、不依賴 `AppModel`（靠 closure）：
```swift
@MainActor @Observable final class CuePlaybackEngine {
    private(set) var isPlaying = false
    /// hold 到期時呼叫：handler 前進到下一顆 cue 並回傳「新目前 cue 的 hold 秒數」以排下一次；回傳 nil＝到底、停止。
    @ObservationIgnored var onFollow: (() -> Double?)?
    func start(initialHold: Double)   // stop() 後 isPlaying=true、排 initialHold 後首次 follow
    func stop()                       // 失效計時器、isPlaying=false（idempotent）
    // 內部：schedule(after:) 用 Timer(repeats:false) + RunLoop.main .common + MainActor.assumeIsolated；
    //       fire(): guard isPlaying; if let h = onFollow?() { schedule(after: h) } else { stop() }
    //       schedule 的 interval 取 max(0.05, seconds)
}
```

### WI-4 — AppModel 接線（owner：`AppModel.swift`）
- 觀察狀態：`var isPlayingCueList = false`。計算 `var isShowRunning: Bool { isMusicPlaying || isPlayingCueList }`（UI 用）。引擎：`@ObservationIgnored let cuePlaybackEngine = CuePlaybackEngine()`。
- `func playCueList()`：`guard !isMusicShowActive, CuePlayback.canAutoPlay(cueCount: cues.count) else { 設友善 aiUnderstoodCommand（「至少需要兩個場景才能自動播放。」/音樂秀提示）; conversationState=.explaining; return }`；接 `cuePlaybackEngine.onFollow = { [weak self] in self?.followToNextCueDuringPlayback() }`；`isPlayingCueList=true`；`cuePlaybackEngine.start(initialHold: CuePlayback.holdDuration(for: cues[selectedCueIndex]))`；`aiUnderstoodCommand="開始播放，共 \(cues.count) 個場景會自動依序切換。"`；`conversationState=.explaining`；`narrateIfEnabled`。
- `private func followToNextCueDuringPlayback() -> Double?`：`guard isPlayingCueList else { return nil }`；`let idx = stageState.selectedCueIndex`；`guard let next = CuePlayback.nextIndex(after: idx, count: cues.count) else { isPlayingCueList=false; aiUnderstoodCommand="已播放完整場演出，停在最後一個場景。"; conversationState=.explaining; return nil }`；`selectCue(id: cues[next].id)`（沿用既有走場/relight/persist）；`return CuePlayback.holdDuration(for: cues[next])`。
- `func stopCueList()`：`cuePlaybackEngine.stop(); isPlayingCueList=false`。**靜默、idempotent**（不設 aiUnderstoodCommand，以免蓋掉 reset 訊息）；可 `narrateIfEnabled` 選擇性（不設）。
- `func togglePlayback()`：`if isMusicShowActive { if isMusicPlaying { stopMusicShow() } else { playMusicShow() } } else { if isPlayingCueList { stopCueList() } else { playCueList() } }`（headset/語音統一入口）。
- **手動 GO 在播放中重排**：`goToNextCue()`/`goToPreviousCue()` 末端 `if isPlayingCueList { cuePlaybackEngine.start(initialHold: CuePlayback.holdDuration(for: cues[selectedCueIndex])) }`（手動跳一顆後 follow 倒數重來）。
- **互斥**：`playMusicShow()` 開頭 `stopCueList()`。
- **reset 停止**：`openProject`/`closeProject`/`generate` 三處在既有 `clearMusicShow()` 旁加 `stopCueList()`。
- **語音**：`applyVoiceCommand` 加 `case .playShow: togglePlayback()`（或分 `.playShow`/`.stopShow` → play/stop）；見 WI-5 決定 case 形狀。採**兩個 case**：`.playShow → (isMusicShowActive ? playMusicShow() : playCueList())`、`.stopShow → (isMusicShowActive ? stopMusicShow() : stopCueList())`。
- **iPad 命令**：無新 AppModel 方法之外的（`playCueList`/`stopCueList` 已定義）。

### WI-5 — 語音指令（owner：`StageVoiceCommand.swift`，**在 smoke 集**）
- 加 `case playShow`、`case stopShow`。
- `englishPhrases`：`(.playShow, [["play","show"],["run","show"],["start","show"],["play","cues"],["run","cues"],["auto","play"]])`、`(.stopShow, [["stop","show"],["stop","playback"],["halt","show"],["stop","cues"]])`。
- `chinesePhrases`：`(.playShow, ["播放","自動播放","跑全場","開始演出","自動走場","播放全部"])`、`(.stopShow, ["停止播放","停止走場","停止演出","停止自動"])`。
  - **不可誤吃**：既有 `.nextCue`/`.previousCue` 片語不變；「停止」單獨太廣→只收「停止播放/走場/演出/自動」等組合詞（比照既有精確片語慣例，避免吃到一般 prompt）。
- smoke（1 條 `voiceCommandParsesPlayAndStop`，註冊 `main()`）：解析 "play the show"/"stop playback"/「播放」/「停止播放」→ 對應 case；且 "next cue"/「下一個場景」仍→ `.nextCue`（回歸）；一般 prompt「把燈調成藍色」→ nil。

### WI-6 — iPad 協定 + 接線（owner：`LumaSyncProtocol.swift`）
- `LumaControlCommand` 加 `case playCueList`、`case stopCueList`（1:1 對應 `AppModel.playCueList()`/`stopCueList()`）。
- `LumaHostState` 加 `var isPlayingCueList: Bool = false`（預設值；同 build 線路）。
- smoke：擴充 `lumaSyncProtocolRoundTrips` 覆蓋 `.playCueList`/`.stopCueList` 與帶 `isPlayingCueList=true` 的 `LumaHostState` round-trip。

### WI-7 — coordinator + 面板 mock（owner：`LumaSyncCoordinator.swift` + `iPadPanel/LumaPanelModel.swift`）
- `LumaSyncCoordinator.apply(_:)`：`case .playCueList: appModel.playCueList()`、`case .stopCueList: appModel.stopCueList()`。組 `LumaHostState` 時填 `isPlayingCueList: appModel.isPlayingCueList`（找到既有 makeHostState/publish 處加一欄）。
- `LumaPanelModel.applyLocally(_:)`：`case .playCueList: state.isPlayingCueList = true`、`case .stopCueList: state.isPlayingCueList = false`（離線 mock 樂觀反映）；補齊 switch 的 exhaustiveness。

### WI-8 — iPad 面板 UI（owner：`iPadPanel/PanelFaderBankView.swift`）
- `GoFooter` 在 GO 鈕旁加一顆**播放/停止**切換鈕：`model.host?.isPlayingCueList == true` → 顯示「停止」`stop.fill`（tint red）送 `.stopCueList`；否則「播放」`play.circle.fill`（tint green）送 `.playCueList`。`.disabled(!model.isConnected || cueCount <= 1)`；繁中 `accessibilityLabel`/hint。GO 鈕保留（播放中仍可手動 GO）。

### WI-9 — composer 播放鈕（owner：`VisionAIComposerBox.swift`）
- topBar 於 GO 鈕旁加一顆播放/停止鈕：`appModel.isShowRunning` → 「停止」`stop.fill`；否則「播放」`play.circle.fill`。action = `appModel.togglePlayback()`。`.disabled` 條件：非音樂秀時 `cues.count <= 1`（音樂秀時永遠可播/停）。繁中 label + `.help`；`lumaGazeTarget()`；沿用既有按鈕樣式。狀態列可加「播放中」指示（沿用 `musicStatusChipTitle` 風格；非必須）。

## Constraints / 並行
- 一檔一 owner；跨檔契約以本 spec 釘死（`CuePlayback` 介面、`LightingCue.holdDuration`、`LumaControlCommand.playCueList/stopCueList`、`LumaHostState.isPlayingCueList`）。
- **不動** `MusicSyncEngine.swift`、`LightEffect*`、音樂秀既有路徑。cue-list 與音樂秀**互斥**（playMusicShow 先 stopCueList；playCueList 於 isMusicShowActive 時 no-op）。
- 使用者字串繁中；語音英文片語比照既有。設計 token `LumaStageDesign`；`accessibilityLabel`；Reduce Motion 不涉（無新動畫，走場沿用 cue cross-fade）。
- **Observation footgun**：本功能不新增 `RealityView update:` 依賴（走場走既有 `selectCue`→relight 路徑，已被現有 `body` eager-read 覆蓋）。

## Verification
- smoke：repo root 跑更新後的 `swiftc`（含新 `CuePlayback.swift`）→ `LumaStageCoreSmokeTests passed`（含 WI-1/5/6 新測試）。
- 完整 build：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build` → `** BUILD SUCCEEDED **`。
- smoke 編譯集登記：`CuePlayback.swift` 加進 `docs/specs/README.md` 與根 `CLAUDE.md` 的 `swiftc` 清單。

## Caveats（實機/刻意延後）
- **暫停/續播**延後：v1 僅播放/停止（停止＝停在目前 cue，不記進度）。
- **不迴繞**：自動播放跑到最後一顆停；要循環需另做（或未來 per-cue「follow to first」）。
- **per-cue hold 目前無 UI 可編**：所有生成/樣板 cue 的 `holdDuration` 為 nil → 一律預設 6s；編輯 hold 屬「編程頁」（issue #9）範疇。音樂秀不受影響（走 `MusicSyncEngine` 段落時序）。
- 計時器精度、播放中手動 GO 的手感、headset 內播放鈕與音樂鈕的心智模型需實機驗。
