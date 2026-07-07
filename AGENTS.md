# AGENTS.md — LumaStage 自動修 issue 協定

給自動化 agent（Codex 等）。**開工前先讀本檔，再讀 `CLAUDE.md`**（架構、慣例、footgun 的單一事實來源）。本檔只講「怎麼一條一條修 issue 並自我驗證」。

## 專案背景（一分鐘版，細節在 CLAUDE.md）
- 平台 **visionOS 26 + iPadOS 26**，用 **Xcode 26.4** build。
- AI 燈光生成**只走 OpenAI 雲端**（`OpenAILightingService`，model `gpt-5.5`，金鑰存 Keychain）。裝置端 Foundation Models 已完整移除。
- 架構慣例：**可判定邏輯放 Foundation-only 檔 + smoke 測試**；view 只當薄消費者。

## 硬規則（違反即停，回報等指示）
1. **不使用三個 visionOS 27-only RealityKit API**（本版已移除）：`SpotLightComponent.SurroundingsLight`、軟陰影 `Shadow.lightSize`/`quality`、gobo `ProjectiveTexture`。
2. **不 `import FoundationModels`**；不重建裝置端生成或 `FallbackLightingService`。
3. 新邏輯放 **Foundation-only 檔 + 補 smoke 測試**（在 `main()` 註冊）；不要埋進 view。
4. **只改該 issue 需要的東西**；不順手重構無關程式；清掉自己造成的 unused import/變數。
5. **絕不對 `main` 用 `git push --force`。**
6. 動手前先 `gh issue view <N>` 讀完整內容——位置、期望行為、實作方向、驗收標準、footgun 都在裡面，一律遵守。

## 每條 issue 的工作流程
```bash
# 1) 同步最新 main（本地 main 追蹤 origin/main）
git fetch origin
git checkout main 2>/dev/null || git switch -c main origin/main
git pull --rebase origin main

# 2) gh issue view <N> 讀完整內容；先講一句話計畫
# 3) 最小改動；新邏輯進 Foundation-only 檔 + smoke 測試

# 4) 跑 smoke（必須印 "LumaStageCoreSmokeTests passed"）
swiftc \
  Tests/LumaStageCoreSmokeTests.swift \
  LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
  LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
  LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift LumaStage/LightEffect.swift \
  LumaStage/MusicBeatClock.swift LumaStage/StageLightAccessibility.swift LumaStage/FixtureGroups.swift \
  LumaStage/OpenAILightingService.swift LumaStage/OpenAIKeychain.swift LumaStage/SongAnalysis.swift \
  LumaStage/ShowPlan.swift LumaStage/RigConstraint.swift LumaStage/MusicShowBuilder.swift \
  LumaStage/SongLibrary.swift LumaStage/DemoTrackSynth.swift LumaStage/CuePlayback.swift \
  -o /tmp/LumaStageCoreSmokeTests && /tmp/LumaStageCoreSmokeTests

# 5) 若動到 view / RealityKit → 完整 build（必須 ** BUILD SUCCEEDED **；先確認 xcode-select 指 Xcode 26.4）
xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath /tmp/lumastage-dd build

# 6) commit（訊息結尾寫 Closes #<N> 讓 issue 自動關閉）
git add -A && git commit

# 7) 推前再 rebase 一次；若 rebase 帶進別人的改動，重跑步驟 4（和 5）
git pull --rebase origin main

# 8) 只有步驟 4（和 5，若適用）全綠時才推；被 reject → pull --rebase → 再推；永不 force
git push origin main
```
**若步驟 4 或 5 任一失敗：不要 push，停下來修好或回報。**

## 驗證與誠實回報（每條 issue 結束都要做）
把該 issue 的「驗收標準／期望行為」**逐條列出**，每條標註你怎麼驗的：
- `[smoke]` 可判定邏輯 → 已寫 smoke 測試涵蓋（附測試函式名）
- `[build]` 編譯／型別 → build 通過
- `[需實機]` 行為／視覺／效能／視窗生命週期 → **你無法驗**，明確列出來交人類在 Vision Pro 上確認

**誠實原則**：凡 `[需實機]` 的驗收條件，一律只說「已實作，待實機確認」，**不得宣稱已驗證／已完成**。回報時分兩份清單：「已驗（smoke/build）」與「待人類實機驗」。

## Issue 分類（決定怎麼處理）
- **不要碰**：**#28**（總覽／追蹤 issue，不是可修的工作）。
- **先問人、不要直接實作**：**#3**（雷射改粒子）——與 `CLAUDE.md`「per-beam 粒子／煙幕已刻意移除」的既定決策衝突。先寫取捨說明、等人核可。
- **SPEC-first（先只寫 `docs/specs/` 的 SPEC 文件、不改碼，等人核可再實作）**：**#2、#8、#9、#10、#24、#26**，以及任何 issue body 寫「先寫 SPEC」或屬架構級／多視圖／大量視覺調校的。
- **可直接修（有明確 `檔案:行號` + 驗收標準的獨立 bug/UX）**：**#4、#1、#7、#22、#5、#11、#16、#19、#20、#21、#23、#25、#27**。其中視窗／桌面／視覺類（#1、#7、#11、#20、#23…）預期會有 `[需實機]` 項，實作完交人類驗。

## 何時停下來問人（不要自作主張）
- 需違反任一硬規則才能達成 → 停、回報。
- issue 屬「SPEC-first」或「先問人」類 → 停、產出 SPEC 或取捨說明，等核可。
- smoke／build 修不綠、或不確定驗收怎麼算過 → 停、回報，**不要 push**。
- rebase 出現衝突且不確定如何解 → 停、回報。
