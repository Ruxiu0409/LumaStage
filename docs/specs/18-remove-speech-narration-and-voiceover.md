# SPEC 18 移除語音朗讀與 VoiceOver 標註

> Status: in-progress

## Goal

移除 AI 回饋的 TTS 朗讀輸出與 VoiceOver 專用標註,讓產品回到文字/視覺控制為主。語音輸入 `SpeechTranscriber` 保留;Reduce Motion、Dynamic Type、`LumaStageDesign.minGazeTarget = 60` 保留。

## Ground Truth

- GitHub issue #5 是完整 scope。
- `SpeechNarrator` 只負責輸出端朗讀,刪除後不得留下 speaker toggle、朗讀 command 或 `narrateIfEnabled` 呼叫。
- `StageLightAccessibility` 只負責 RealityKit 燈具 VoiceOver copy,刪除後 smoke 編譯清單不得再引用它。
- `AccessibilityComponent` 與 SwiftUI `.accessibilityLabel` / `.accessibilityValue` / `.accessibilityHint` 是本次刪除面;`.accessibilityReduceMotion` 與 `@ScaledMetric` 不是。

## Work Items

1. **Speech output removal**
   - 刪除 `LumaStage/SpeechNarrator.swift`。
   - `AppModel.swift` 移除 narrator state、toggle/read helper 與所有 `narrateIfEnabled` 呼叫。
   - `VisionAIComposerBox.swift` 移除語音朗讀 speaker toggle。
   - `StageVoiceCommand.swift` 移除 `.readExplanation` 與片語表。
   - `SpeechTranscriber.swift` 移除「念出說明」contextual string。

2. **VoiceOver removal**
   - 刪除 `LumaStage/StageLightAccessibility.swift`。
   - `ImmersiveView.swift` 移除 `lightpick_<n>` 的 `AccessibilityComponent` 建置與 relight value update。
   - 移除 issue #5 指定 view 檔中的 `.accessibilityLabel` / `.accessibilityValue` / `.accessibilityHint`。

3. **Docs and tests**
   - `Tests/LumaStageCoreSmokeTests.swift` 移除 `.readExplanation` assertion、`stageLightAccessibilityLabelsAreLocalized` body 與 `main()` 註冊。
   - `AGENTS.md`、`CLAUDE.md`、`docs/specs/README.md` 同步 smoke 編譯清單與現況基線。
   - `docs/social-value.md`、`docs/maic-strategy.md`、`docs/demo-runbook.md` 僅標註歷史文件中的 accessibility / voice-narration 敘述已下架。

## Constraints

- 不改語音輸入 `SpeechTranscriber` 的 mic-to-text 流程。
- 不移除 Reduce Motion gate、Dynamic Type 或 `minGazeTarget`。
- 不新增 visionOS 27-only RealityKit API,不 `import FoundationModels`。
- 只清理本次刪除造成的 unused imports/vars。

## Verification

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
  -o /tmp/LumaStageCoreSmokeTests && /tmp/LumaStageCoreSmokeTests
```

通過條件:印出 `LumaStageCoreSmokeTests passed`。

完整 build:

```bash
xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath /tmp/lumastage-dd build
```

通過條件:`** BUILD SUCCEEDED **`。

## Caveats

- Demo runbook 不再包含語音朗讀步驟;真人 demo 需確認流程口播不再依賴 TTS。
- 若文件仍保留 MAIC / social-value 歷史敘事,只能標註「已下架」,不得再作為現況功能宣稱。
