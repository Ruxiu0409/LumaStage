# SPEC 06 — 社會價值支柱 + 全面無障礙（S1 完成）

**Goal**：把產品從「酷工具」重新定位為「**讓沒器材、沒場地、甚至視/行動受限的學生劇團與獨立創作者,只靠一台 Vision Pro 就能設計專業舞台燈光**」,並把無障礙做到位。這是 MAIC 啟航**社會價值 20 分(60% 單項淘汰硬門檻)**的保命項——**只有真做出來才講**(評委會抓造假)。

## 現況（已部分完成,勿重做）
- 全語音閉環:`StageVoiceCommand`(下一個/上一個/新增場景/念出說明,中英)、`SpeechNarrator`(zh-TW 朗讀)、`AppModel.toggleVoiceNarration`/`applyVoiceCommand`/`readCurrentExplanationAloud`、語音辨識 zh-TW 優先 + 中文 contextualStrings。`VisionAIComposerBox` 多數無障礙已補(60pt、Reduce Motion、非顏色狀態、Dynamic Type 輸入框、cue chip `.isSelected`+`accessibilityAction`)。

## Work items
### 1. 無障礙 sweep（owner A,跨多檔——可再拆給數個 agent,一檔一人）
對**尚未補的 view** 做一致處理:`ProjectSelectionView`、`LightingFixtureIntroView`、`FixtureObservatoryView`/`FixtureInfoCardWindow`、`TabletopStageEditorView`、`ContentView`、`PatchSheetExportView`、iPad `PanelChatView`/`PanelRootView`。每檔:
- 每個互動元件 `accessibilityLabel`(必要時 hint/value);圖示鈕補非顏色狀態。
- 取代寫死字級 → 語意樣式 / `@ScaledMetric`(Dynamic Type)。
- 所有 `.animation`/`symbolEffect`/`transition` gate 在 `@Environment(\.accessibilityReduceMotion)`。
- ≥60pt(visionOS)/≥44pt(iPad)注視/觸控目標(用 `lumaGazeTarget`)。
- 高對比變體(`@Environment(\.colorSchemeContrast)`)用於 over-glass 品牌色。
- 建議用 `swiftui-accessibility-auditor` / `ios-accessibility` skill 導引,逐檔產出可套用修正。

### 2. RealityKit 場景進無障礙樹（owner B,`ImmersiveView.swift`）
給每盞燈的 `lightpick_<n>`(或燈具容器)加 `AccessibilityComponent`,label 例:「第 3 盞燈,藍色,60%,搖頭光束燈」(用 cue fixture + override 解析);讓 VoiceOver 能聚焦並朗讀場上的燈。可重用 `RelightDebugSnapshot` 的資料。

### 3. 社會價值敘事文件（owner C,新檔 `docs/social-value.md`,非程式碼）
寫給決賽用的敘事:問題(學燈控台要先有燈控台 / 視障/行動受限者被排除)→ 對象(學生劇團、偏鄉、獨立創作者、身障創作者)→ 我們怎麼解(端側 AI + 全語音 + 1:1 空間,門檻降到一台頭戴)→ 真實場景與限制(誠實:不誇大)。對齊根 `docs/maic-strategy.md` §5 與「誠實底線」。

## Constraints / 並行
- sweep 天然可並行(一檔一 agent)。owner B 只動 `ImmersiveView`;owner C 只寫 doc。
- **誠實底線**:文件只描述真的做出來的能力。

## Verification
- 完整 build → SUCCEEDED;smoke 不變。
- 實機:用 VoiceOver 走過主流程(選專案→進場→語音生成→走 cue→唸說明),確認可達、可操作。

## Caveats
- VoiceOver 走 RealityKit 場景的實際體驗需實機。Dynamic Type 極大字級下的版面破圖需實機檢查。
