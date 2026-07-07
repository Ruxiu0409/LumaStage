# SPEC 12 — MusicKit 選曲來源（資料庫選曲 → 既有分析管線）

> Status: done（已實作、完整 build 綠、smoke 綠，2026-07-01 封存）
> **這是正式版打磨，不是 demo 路徑。** Demo 仍走「使用內建示範曲」(零失敗) 與「匯入音檔」。本 spec 只是再加一條*來源*，不動分析/播放/生成。

## Goal

讓使用者**從裝置上的音樂資料庫挑一首歌**（而不是只能用檔案瀏覽器），把解析到的**可讀取檔案 URL** 餵進**既有**的 `AppModel.importSong(url:)` → `SongAnalyzing` → `ShowPlan` → `MusicShowBuilder` 管線。受 DRM 保護的 Apple Music 串流曲目（取樣不可讀、`assetURL == nil`）**優雅拒絕**並以繁中說明。對應 MAIC 旗艦音樂功能 (SPEC 05) 的正式版易用性打磨。

**核心技術事實（agent 必讀，這是整個 spec 的前提）**：分析 (`MusicUnderstandingSession(asset:)` / `AVURLAsset`) 與播放 (`MusicSyncEngine` → `AVAudioPlayer(contentsOf:)`) **兩者都需要一個可讀取取樣的真實檔案 URL**。MusicKit 能瀏覽/播放 Apple Music 曲庫，但**不會**對 DRM 保護內容交出可解碼的檔案 URL。唯一能從資料庫項目拿到可用 `URL` 的是 **`MediaPlayer.MPMediaItem.assetURL`**，且它**只在非保護、已下載到本機的項目**為非 nil。所以本功能本質上是「**使用者自己擁有的本機曲目**」選曲，不是 Apple Music 全曲庫選曲。

## Ground truth（呼叫/沿用，**不要重寫**）

- `AppModel.importSong(url: URL) async`（`AppModel.swift:644`）——已處理 security-scoped 存取、derive title、跑完整管線 + 載入播放。**沿用**，只允許下方 WI-4 的*單一 additive* 改動（加一個有預設值的 `title:` 參數）。
- `AppModel.useBuiltInDemoSong()` / `buildAndLoadShow(from:audioURL:)`（`AppModel.swift`）——**完全不動**。
- `SongAnalyzing.analyze(url:title:)`（`SongAnalysis.swift:93`）——分析 seam，**不動**。
- `MusicSyncEngine.load(url:clock:)`（`MusicSyncEngine.swift:96`，內部 `AVAudioPlayer(contentsOf: url)`）——播放層，**不動**。URL 必須是真實可播檔案。
- `MusicShowSheet.sourceSection`（`VisionAIComposerBox.swift`，目前「匯入音檔」`fileImporter(.audio)` + 「使用內建示範曲」兩顆鈕）——WI-5 在這裡**新增第三顆**「從音樂資料庫選曲」，前兩顆保留不動。
- **注入慣例範本**：`LightingLookGenerating`（雲端/FM 可注入）、`SongAnalyzing`、`LumaSyncTransport` + `LoopbackSyncTransport`——本 spec 的 `SongLibraryBrowsing` + `LoopbackSongLibrary` 完全照這個 seam + loopback 形狀做。
- **設備檔入口目前隱藏**（`MusicShowSheet.showsRigConstraintEntry = false`）——**不要**順手重新顯示它。

**Footgun**

- `importSong` 用 `url.deletingPathExtension().lastPathComponent` 當 title。`assetURL` 是 `ipod-library://…` 形式、檔名無意義 → **必須**讓資料庫項目的真實 title 流過去（WI-4 的 `title:` 參數）。
- MusicKit / MediaPlayer 在 **visionOS 27 的可用性不確定**（post-cutoff 框架）——**WI-1 是 gate**，先確認再實作 WI-3。可判定邏輯與 UI 不依賴框架可用與否（WI-2/WI-5 對著協定寫）。
- `MPMediaItem.assetURL` 對 Apple Music 串流/未下載項目為 `nil` → 這類項目要在挑選前就標 `isProtected = true` 並 disable，挑到也要 throw `.protected`。

## Work items（標明檔案擁有權與精確契約）

### WI-1 — 能力 spike（gate，先做；產出寫進本 spec 的 Caveats）
擁有：本檔（doc）。確認 visionOS 27 上：(a) `import MusicKit` + `MusicLibraryRequest<Song>`（或退而求其次 `import MediaPlayer` + `MPMediaQuery`）是否可用；(b) 能否對「本機已下載、非保護」項目取得可讀 `URL`（`MPMediaItem.assetURL` 橋接）。把結論（哪條路可行 / visionOS 是否根本沒有 MediaPlayer）寫回本 spec 的 **Caveats**。**若 visionOS 完全拿不到可讀 URL** → 功能降級為「僅瀏覽 + metadata、無法分析」，並在本 spec 明記、WI-5 改為顯示「此平台無法從資料庫分析，請改用匯入音檔」。其餘 WI 仍照協定完成（seam 對 iOS companion 仍有價值）。

> **WI-1 結論（已完成，2026-07-01；驗證對象 = Xcode 27 XROS.sdk，SDKSettings Version 27.0）**：**SPEC 12 可照設計實作，不需降級。** MusicKit 與 MediaPlayer **兩個框架在 visionOS 27 都原生可用**（各自 `.tbd` 的 `targets: [ arm64e-xros ]`），且 `MPMediaItem.assetURL` 在 visionOS 上**存在且可編譯/連結**。**建議實作路徑 = MediaPlayer**（`#if canImport(MediaPlayer)`，因為唯一能取得可讀檔案 URL 的 API 是 `MPMediaItem.assetURL`；MusicKit 的 `MusicLibraryRequest<Song>` 雖也可用，但它不交出可解碼的本機檔案 URL，所以只適合純瀏覽/metadata，不滿足分析+播放對 `AVURLAsset`/`AVAudioPlayer` 的取樣需求）。WI-3 的 `#if` 守衛建議用 `#if canImport(MediaPlayer) && (os(visionOS) || os(iOS))`，`#else` 走框架缺席分支（回空 / `throw .unsupported`）。`assetURL` 是否「對某具體項目」非 nil 仍是執行期 DRM/下載狀態決定（保護/未下載 → nil → `throw .protected`），需實機驗（見 Caveats）。`Info.plist` 仍需 `NSAppleMusicUsageDescription`。

### WI-2 — Foundation-only seam（一個 agent；**納入 smoke 集**）
擁有：**新檔 `LumaStage/SongLibrary.swift`** + `Tests/LumaStageCoreSmokeTests.swift`（只加，不改既有測試）。
契約（釘死，跨檔靠這個對齊）：
```swift
struct SongLibraryItem: Identifiable, Equatable {
    let id: String          // 穩定識別（MusicKit/MediaPlayer 的 persistentID 字串）
    let title: String
    let artist: String
    let duration: Double     // 秒；未知為 0
    let isProtected: Bool    // true = 無 assetURL（DRM/未下載），不可分析
}

enum SongSourceError: Error { case unauthorized, protected, unsupported, resolveFailed(String) }

protocol SongLibraryBrowsing {                       // 注入 seam，平台無關
    func authorize() async -> Bool
    func recentSongs(limit: Int) async -> [SongLibraryItem]
    func search(_ query: String) async -> [SongLibraryItem]
    func resolvePlayableURL(for item: SongLibraryItem) async throws -> URL  // protected → throws .protected
}

struct LoopbackSongLibrary: SongLibraryBrowsing { … }  // 測試/預覽：吃固定 [SongLibraryItem]，
                                                        // 非保護回一個注入的 file URL、保護 throws .protected
```
Smoke（新增、註冊進 `main()`）：`songLibraryLoopbackBrowsesAndResolves`——loopback 列表/搜尋過濾正確、非保護項 `resolvePlayableURL` 回注入 URL、`isProtected` 項 throw `.protected`。
同時把 `LumaStage/SongLibrary.swift` 加進 README.md「smoke 編譯集」指令與根 `CLAUDE.md` 測試段（WI-2 agent 負責）。

### WI-3 — 平台實作（一個 agent；**不在 smoke 集**）
擁有：**新檔 `LumaStage/MusicKitSongLibrary.swift`**，`#if canImport(MusicKit) && (os(visionOS) || os(iOS))`（依 WI-1 結論可改 MediaPlayer）。
- `authorize()` 包 `MusicAuthorization.request()`（或 `MPMediaLibrary.requestAuthorization`）→ Bool。
- `recentSongs`/`search` 用 `MusicLibraryRequest<Song>`（或 `MPMediaQuery.songs()`）→ map 成 `SongLibraryItem`；以「能否取得 `assetURL`」判 `isProtected`。
- `resolvePlayableURL`：對非保護項回 `MPMediaItem.assetURL`；nil → `throw .protected`。框架缺席的 `#else` 分支：每個方法回空 / `throw .unsupported`（mirror `MusicUnderstandingService` 的框架缺席分支）。
- 任何錯誤對映成 `SongSourceError`，**不洩漏框架型別**到上層。

### WI-4 — AppModel 接線（一個 agent；**只此一個 agent 動 AppModel.swift**）
擁有：`LumaStage/AppModel.swift`。**全為 additive，generate/gate/分析/播放/cue 編輯一律不動。**
- 注入 `private let songLibrary: any SongLibraryBrowsing`，`init` 加 `songLibrary: (any SongLibraryBrowsing)? = nil`，預設 `MusicKitSongLibrary()`（mirror `songAnalyzer` 第 195–199 行那段）。
- `importSong` 加 additive 參數：`func importSong(url: URL, title: String? = nil) async`——`let title = title ?? url.deletingPathExtension().lastPathComponent`。其餘一字不動（既有呼叫端零改動）。
- 新 `func pickLibrarySong(_ item: SongLibraryItem) async`：`do { let url = try await songLibrary.resolvePlayableURL(for: item); await importSong(url: url, title: item.title) } catch { fail(<繁中錯誤，protected → "此曲受保護，無法在裝置端分析；請改用未受保護的本機檔案。">) }`。
- 把 `songLibrary` 暴露給 view 用的薄 helper（如 `func browseLibrary() async -> [SongLibraryItem]` / `searchLibrary(_:)` / `authorizeMusicLibrary()`），或直接讓 view 透過 AppModel 取得這些；不要讓 view 直接持有 `MusicKitSongLibrary`。

### WI-5 — UI（一個 agent；**只此一個 agent 動 VisionAIComposerBox.swift**）
擁有：`LumaStage/VisionAIComposerBox.swift`。
- `MusicShowSheet.sourceSection` 新增第三顆鈕「從音樂資料庫選曲」(`systemImage: "music.note.list"` 或 `"rectangle.stack"`，與既有兩顆風格一致、`.lumaGazeTarget()`、繁中 `help`/a11y)，打開新的 `SongLibraryPickerView` sheet。**前兩顆鈕不動。**
- 新 `private struct SongLibraryPickerView`：授權 → 列出 `recentSongs` + 搜尋框（`searchLibrary`）；每列顯示 title / artist / 時長；**`isProtected` 的列 disable 並標「受保護，無法分析」**；點選非保護列 → `await appModel.pickLibrarySong(item)` 後 `dismiss()`。授權被拒/平台不支援 → 顯示繁中說明 + 「改用匯入音檔」引導。全程套設計 token、Dynamic Type、Reduce Motion gate、≥60pt 注視目標、非顏色狀態指示。

## Constraints

- **不可動**：`SongAnalysis.swift`、`MusicUnderstandingService.swift`、`ShowPlan.swift`、`MusicShowBuilder.swift`、`MusicSyncEngine.swift`、`buildAndLoadShow`、`useBuiltInDemoSong`、設備檔隱藏旗標。
- **不可成為 demo 預設**：內建示範曲仍是零失敗路徑；資料庫選曲是額外來源。
- **平台守衛**：平台框架只在 `MusicKitSongLibrary.swift`（`#if canImport(MusicKit)…`）；`SongLibrary.swift` Foundation-only、進 smoke 集。
- **Info.plist**（`project.pbxproj`）：加 `NSAppleMusicUsageDescription`（繁中，說明「用於從你的音樂資料庫選曲做裝置端分析」）。WI-3 agent 負責，若用 MediaPlayer 同樣需要此鍵。
- 使用者字串繁中；注入/loopback/smoke 形狀照 `LightingLookGenerating`/`LumaSyncTransport`。

## Verification

- **Smoke**（加入 `SongLibrary.swift` 後）：
  ```
  swiftc Tests/LumaStageCoreSmokeTests.swift \
    LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
    LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
    LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift LumaStage/LightingPatchSheet.swift \
    LumaStage/LightEffect.swift LumaStage/MusicBeatClock.swift LumaStage/StageLightAccessibility.swift \
    LumaStage/LightControlCardPlacement.swift LumaStage/FixtureGroups.swift \
    LumaStage/OpenAILightingService.swift LumaStage/FallbackLightingService.swift LumaStage/OpenAIKeychain.swift \
    LumaStage/SongAnalysis.swift LumaStage/ShowPlan.swift LumaStage/RigConstraint.swift LumaStage/MusicShowBuilder.swift \
    LumaStage/SongLibrary.swift \
    -o /tmp/smoke && /tmp/smoke
  ```
  通過：印出 `LumaStageCoreSmokeTests passed`。
- **完整 build**：
  ```
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage \
    -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build
  ```
  通過：`** BUILD SUCCEEDED **`（既有 Multipeer Sendable 警告忽略）。

## Caveats（實機 / 刻意延後）

- **WI-1 結論（已驗，2026-07-01，對 Xcode 27 `XROS.sdk` v27.0）**：MusicKit 與 MediaPlayer **在 visionOS 27 皆原生可用**，**功能無需降級**。證據（SDK annotation 為準，勝過 web docs）：
  - MusicKit `swiftinterface`（`…/XROS.sdk/System/Library/Frameworks/MusicKit.framework/Modules/MusicKit.swiftmodule/arm64e-apple-xros.swiftinterface`）：`MusicAuthorization` 與 `Song` 標 `@available(iOS 15.0, …, visionOS 1.0, *)`；`MusicLibraryRequest<…>` 標 `@available(iOS 16.0, …, visionOS 1.0, …, *)`。三者皆**無** `@available(visionOS, unavailable)`。MusicKit 的 `.tbd` `targets: [ arm64e-xros ]`（原生，非 iPad 相容墊片）。
  - MediaPlayer：框架存在於 `…/XROS.sdk/System/Library/Frameworks/MediaPlayer.framework`；其 `MediaPlayer.tbd` `targets: [ arm64e-xros ]`，export list 含 `MPMediaQuery`/`MPMediaItem`/`MPMediaLibrary` 與 `MPMediaItemPropertyAssetURL`。`MPMediaItem.h:150` 宣告 `@property … NSURL *assetURL`。（注意：MediaPlayer 標頭的 `MP_API(...)` 巨集未逐一列 `visionos`，且 `MediaPlayer.apinotes` 只做 SwiftName 重命名、無 visionOS 不可用覆寫；實際以 `.tbd` 的 xros target + 成功編譯為準。）
  - 實證：對 visionOS 27 SDK（`-target arm64-apple-xros27.0`）以 `swiftc -emit-object` 同時編譯 `MPMediaQuery.songs()` / `MPMediaItem.assetURL` / `MPMediaLibrary.requestAuthorization` 與 `MusicAuthorization.request()` / `MusicLibraryRequest<Song>().response()`，**成功產出 object file**（僅一個無害 async 警告）。
  - **採用路徑**：MediaPlayer（取 `MPMediaItem.assetURL` 為可讀檔案 URL）；MusicKit 不交出可解碼本機檔 URL，故不用於分析來源。`assetURL` 對受保護/未下載項目於執行期回 nil → `throw .protected`（平台限制，非 bug）。
- **DRM**：Apple Music 串流/未下載曲目永遠無法分析（取樣不可讀）——這是平台限制不是 bug；UI 必須誠實標示，不可假裝可分析。
- 授權流程、`assetURL` 真能否餵進 `AVURLAsset` + `AVAudioPlayer`（兩者）、大資料庫列表效能、visionOS 上的選曲 UI 手感——需實機驗。
- 正式上架前：`NSAppleMusicUsageDescription` 文案、隱私說明、entitlement 配置。
