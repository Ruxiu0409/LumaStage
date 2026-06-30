# SPEC 05 — 音樂節拍同步（B1，依賴 A1）

**Goal**：匯入/播放音檔 → 取節拍 → 驅動 A1 動態效果(strobe/chase/sweep 跟著拍子),學生成發/舞團/音樂之夜的核心。**高風險在分析準度**——賽前降級為「預先分析好的內建示範曲」可達零失敗。

## Ground truth
- A1 已完成:`LightEffect`(speedHz/phase)、`LightEffectEngine`、`LightEffectComponent` + `LightEffectSystem`(每幀 `time += deltaTime`,`LightEffectEngine.output(effect, at: time)`) — `LightEffect.swift` / `LightEffectSystem.swift`。
- 效果速度目前由 `LightEffect.speedHz` 決定;system 用自累加的場景時間。

## Work items
### 1. `LumaStage/MusicBeatClock.swift`（owner A，新檔,Foundation-only,加進 smoke 編譯集 + 測試）
純可判定的節拍格:
```swift
struct MusicBeatClock: Equatable {
    var bpm: Double          // 例 128
    var startOffset: Double  // 第一拍的時間(秒)
    func beatPhase(at time: Double) -> Double   // 0..1 在當前拍內的相位
    func beatIndex(at time: Double) -> Int       // 第幾拍
    var beatHz: Double { bpm / 60 }
}
```
smoke:phase 在 0..1、每拍邊界回 0、beatHz 正確、startOffset 平移。

### 2. `LumaStage/MusicSyncEngine.swift`（owner B，新檔,平台,`#if os(visionOS) || os(iOS)`)
- 播放內建示範曲(已知 BPM,bundled),用 `AVAudioPlayer`/`AVAudioEngine`;暴露目前播放時間。
- (進階,可後補)即時 BPM 偵測(`Accelerate`/`AVAudioEngine` tap)——**賽前不必,先用內建曲已知 BPM**。
- 提供目前 `MusicBeatClock` + 播放時間給 system。

### 3. `LightEffectSystem.swift`（owner C）— 拍同步
當音樂模式開啟,system 的 `time` 改由 `MusicSyncEngine` 的拍時鐘驅動(或把 strobe/chase 的相位鎖到 `beatPhase`),讓閃爍/chase 落在拍上。加一個開關(`AppModel.musicSyncEnabled`)。沒開時維持自累加時間(不回歸)。

### 4. UI（owner D，`VisionAIComposerBox` 或新控制）
匯入/選示範曲 + 開關音樂同步的按鈕;狀態顯示(BPM、播放中)。

## Constraints / 並行
- owner A 純 Foundation(最先,可獨立測);B/C/D 對 A 的 `MusicBeatClock` + engine 介面寫。**依賴 A1(已完成)**,不要在 A1 之前做。

## Verification
- smoke(MusicBeatClock)→ passed。完整 build → SUCCEEDED。

## Caveats
- 即時 BPM 偵測準度高風險——**賽前固定用內建示範曲 + 已知 BPM**(零失敗)。實機驗拍同步的視覺鎖拍與效能。
