# 後續待修分析（Fable 5 覆核）

> **狀態更新（2026-07-08，commit 5ff3086）**：本報告中 Fable 覆核找到的 **E-1、E-2、E-5（程式）與 E-3、E-4（文件）已修正**並重跑 smoke + build 綠。下方 E 節與 D 節仍保留原始描述供追溯；尚待處理者為 A 節（你的決策）、B 節（延後實作）、C 節（實機驗收）、D 節部分殘口、E-6/E-7/E-8（P3 邊角）、F 節（既有問題）。

> 覆核範圍：`codex-issue-sweep` 分支（未推送）對 `main` 的全部程式碼 diff（9 個已修 issue + iPad target 修復）、5 份新 SPEC（19–23）、#3 取捨備忘（24）、掃雷報告（issue-*.md / spec-first.md）。
> 我獨立重跑驗證：**smoke `LumaStageCoreSmokeTests passed`**、**visionOS full build `** BUILD SUCCEEDED **`**（皆在該分支工作樹親自執行，非轉述）。
> 結論先講：整體品質良好、架構慣例遵守到位（Foundation-only + smoke、單一 placement 入口、視窗單例修法）。但 diff 覆核找到 **2 個 CONFIRMED 的新問題**（見 E-1、E-2）與數個文件過期，建議在實機驗收前先修。

---

## A. 需要你拍板的決定（P0 — 擋住所有後續實作）

| # | 決定 | 選項與建議 |
|---|------|-----------|
| A-1 | **#3 雷射粒子**（`docs/specs/24`） | 是否回退/疊加粒子？備忘建議**維持 core+sheath 幾何、不做粒子**；若堅持要顆粒感 → 疊加層（保留幾何）而非取代。與既定決策（CLAUDE.md「勿重加 per-beam 粒子」）衝突，故必須由你裁決。 |
| A-2 | **SPEC 20（#8/#9/#10 三階段工作流）核可** + 兩個內嵌設計題 | (1) 預設落地階段：**編程**（spec 建議，保留既有 openProject→stage）還是**架設**（決賽敘事「先架燈」）？(2) 燈具角度：spec 只能做 **rig-identity（跨所有 cue）**；issue #9 文案的「各 cue 角度」需要新資料欄位，spec 明確不做——接受與否？ |
| A-3 | **SPEC 22（#26 表演者人偶）核可** | 產品範圍決定（#28 明標「待決定」）：人偶要不要進 aim 推導？spec 的方案是**部分混成**（`performerAimNudgeFraction=0.5`、僅前/側光、nil=no-op），影響面 M–L。 |
| A-4 | **SPEC 23（#27 舞台結構詞彙）核可** | (a) 建議 **DELETE 未接線的「i-min」deck 資產**（含 1 條 smoke 調整）；(b) 側塔/地面 boom/中段桁架用既有 `.trussSegment` 組合實作（L 級）。issue 本文的「補完伸展台 vs 直接刪」由 (a) 的 DELETE 建議回答——同意否？ |
| A-5 | **SPEC 19（#2 光束煙幕）與 SPEC 21（#24 diorama 預覽）核可** | 兩者都是純視覺增強、幾何路線（禁粒子）一致；主要成本是實機調參。可一起核可、分開排程。 |
| A-6 | **分支合併與推送** | `codex-issue-sweep` 尚未推送；commit 訊息的 `Closes #N` 要**合進預設分支**才會自動關 issue。合併前建議先做 E-1/E-2 修復＋C 節實機驗收（至少視窗生命週期組）。推送依你的全域規則需你明示核可。合併後記得同步更新 **#28 總覽 issue** 的狀態。 |

---

## B. 已核可後的延後實作（依 SPEC，附規模/風險）

| SPEC | 對應 issue | 規模 | 主要風險 |
|------|-----------|------|---------|
| 19 光束煙幕（volumetric spot beams） | #2 | **M**（1 個 Foundation-only `SpotBeamScatterMath` + renderer 掛錐 + 1 smoke） | 12 盞同時的 overdraw／效能；全視覺調參 [需實機] |
| 20 三階段工作流（架設/編程/播放） | #8/#9/#10 | **L**（3 個子頁、`WorkflowPhase`+`CueTimeline` 兩個新共用檔、iPad 鏡射、5+ 新 smoke） | space-swap 相依最深；iPad v1 不支援「架設」；播放游標平滑度；**注意：spec 的 smoke 指令有過期檔名，見 E-3** |
| 21 diorama 迷你燈光預覽 | #24 | **M**（`PreviewBeamCone` + syncFixtures 掛錐 + smoke） | 0.07 尺度下的視覺可讀性全靠實機調；與 E-2（proxy 朝向過期）同一片程式碼，建議**先修 E-2 再做** |
| 22 表演者人偶 | #26 | **M–L**（additive `performerPosition` + 拖曳代理 + aim 混成 + 2 smoke） | aim 混成改 `resolvedPlacement` 共用入口，回歸面最大；等 A-3 |
| 23 結構詞彙 + deck 清理 | #27 | (a) **S**；(b) **L**（`StageStructurePreset` + group-add + 選單 + smoke） | (a) 幾乎零風險可先行；(b) 是純組合既有 truss，風險中等 |

依賴備註：SPEC 21 疊在桌面編輯器 proxy 系統上（先修 E-1/E-2）；SPEC 20 若核可，實作時順手把它 Verification 區塊的 smoke 清單修正（E-3）。

---

## C. 實機驗收待辦（[需實機]，約 21 項，依主題彙整）

掃雷者已誠實標註「已實作、未驗證」。建議一次戴上 Vision Pro 按主題掃完：

1. **視窗生命週期（#1/#7/#11）— 最優先，故障即「使用者被困」**
   - 燈具指南 → 觀星連續進出 ≥5 次（含移動/轉頭）：資訊卡每次落在模型旁或視野內（DEBUG log 會印走哪個 placement 分支）。
   - 舞台開啟時用系統 X 關掉 AI 對話框 → 應回專案列表；反向：按「返回專案」「關閉舞台」「編輯舞台」都**不得**誤觸 returnToProjects（`expectedComposerDismiss` 的 onDisappear 時序只能實機驗，見 E-6）。
   - 反覆關舞台（專案仍開）/ Digital Crown 退出 / 進出桌面編輯器：不再出現兩個 AI 對話框（`Window` 單例 + 兩道 re-dismiss 防線）。
2. **桌面編輯器互動與視覺（#17/#19/#20/#25）**
   - ±X/±Z 微調鍵排版、每按 0.25m 可見步進、座標讀數即時更新（拖曳時也要跟）。
   - 拖曳跨 truss footprint 邊界：升上桁架吊掛（stand 消失）/ 拖離落地，手感自然；**落地架高 deckTop+1.0m 是否合適（掃雷者自己標了可能要調）**。
   - 吊掛區半透明體積：`UnlitMaterial` alpha 0.14 **實機可能呈實心**（報告已預警，若實心要補 blending 設定）；與 seated diorama 對齊；Reduce Motion 下即時顯示；放手乾淨隱藏；truss/deck 拖曳時不出現。
   - 型號專屬迷你幾何：`targetHeight` 尺度、`fixture_lens` 在橫長型（wash bar/strobe bar）上的落點、per-mesh 碰撞抓取穩定度、雷射桌面外型。
3. **燈光 aim（#23）**
   - 「瞄準舞台中心」後 1:1 舞台燈頭+光束轉回台中（aimOffset 在 syncRig 簽名內、硬切）；pan 視覺左右方向；`topY+0.4` 是否讀作瞄準表演者。**注意：diorama 上目前不會有任何視覺回饋（E-2），驗收時別誤判為「按鈕沒作用」。**
4. **流程回歸（#5）**
   - Demo runbook 全程走一遍：無語音朗讀殘留步驟；VoiceOver 掃 rig 不再朗讀（確認是刻意移除，非回歸）。

---

## D. 掃雷明示留下的殘口（sweep 自己標註未處理）

| 項目 | 內容 | 優先級 |
|------|------|-------|
| #11 情境 3 | 主視窗（`mainWindowID`）仍是 `WindowGroup`，一次切換中兩次 `openWindow` 理論上可疊兩個主視窗 | P1（實機重現後再修；修法可比照 composer 換 `Window` 單例，但主視窗語義需確認） |
| #11 情境 4 | `fixtureInfoCardWindowID` 資訊卡同屬 `WindowGroup` 重複風險（#1 只改落點未改單例性） | P2 |
| #17 | stageobj/truss 的微調鍵刻意略過（會與節點吸附打架） | P3（另議） |
| #19 | 方案 B ±Y 微調鍵未做（方案 A 已滿足二選一）；落地架高度待實機調 | P2 |
| #20 | UnlitMaterial 半透明呈現風險（若實心需補 blending） | P2（實機驗後） |
| #23 | 完整版「可拖目標球」略過——每幀寫 aimOffset 會觸發全驗證+syncRig 重建，需節流/放手才 commit 的另行設計 | P3 |
| SPEC 20 caveat | space-swap 耗盡放棄時 `workflowPhase` 可能 stranded（僅在 SPEC 20 實作時要記得加那一行硬化） | 併入 SPEC 20 |

---

## E. 我的 diff 覆核新發現（原掃雷未提）

### CONFIRMED（讀碼即可確定，非臆測）

- **E-1（P1，邏輯洞）#17 微調鍵與 #19 拖曳的 Y 政策不一致 → 可造出「浮空燈」，破壞「no fixture ever floats」不變式。**
  `TabletopStageEditorView.swift:542-546` 的 `nudgeSelectedFixture` 提交 `moveFixture(..., y: position.y, ...)`（**保留 Y**），而 #19 的拖曳走 `RigPlacement.resolvedDragPosition`（XZ 決定 Y）。重現：把燈拖出 truss footprint（提交 Y = deckTop+1.0 = 1.8m），再用 +X/−Z 微調鍵推回 footprint 內 → `support`（`LightingModels.swift:2081`，門檻正是 `y >= deckTop+1.0`，邊界取等）判成 `.hangFromTruss` → 不畫落地柱，但燈仍在 1.8m、桁架頂在 5m → **燈懸浮半空**（1:1 舞台與 diorama 都會浮）。#17 先落地、#19 後落地，後者沒回頭統一前者。
  **建議修法**：`nudgeSelectedFixture` 一樣走 `resolvedDragPosition` 再 `moveFixture`（1–2 行），並補一條 smoke（nudge 跨界後 `support` 分類與 Y 一致）。
- **E-2（P1，UX 缺陷）桌面 proxy 的朝向只在建立時烘焙，之後永不更新 → #23 的「瞄準舞台中心」在它所在的編輯器裡看不到任何變化。**
  `TabletopStageEditorView.swift:869+` 的 `syncFixtures` 對既有 proxy 只更新 position/lens 顏色/標籤/stand（`makeFixtureProxy` 的 aim 於建立時算一次）；`aimOffset` 改變（瞄準鈕、語音 rotate）或拖曳改變 zone-derived 方向後，迷你模型與 lens 都維持舊朝向，直到 assembly 因 layout 變更整組重建。#25 之前的通用錐永遠朝下所以看不出來；換成有明確朝向的型號幾何後，過期朝向會直接可見。
  **建議修法**：比照 `syncRig` 的簽名思路——每 pass 重算 aim，變了就更新 body/lens orientation（或重建該 proxy）。
- **E-3（P2，文件錯誤）SPEC 20 的 Verification smoke 指令仍列已刪除的 `LumaStage/StageLightAccessibility.swift`**（`docs/specs/20-workflow-three-stage-pages.md` Verification 區塊）。照抄必編譯失敗。同批 #5 已正確更新根 CLAUDE.md / AGENTS.md / README 的清單，唯獨這份新 SPEC 漏了。
- **E-4（P2，文件過期）`CLAUDE.md:180` 仍寫「a fixture drag is free XZ (Y preserved, no node-snap)」**——#19 之後 Y 已由 XZ 決定（吊掛/落地吸附）。另外 CLAUDE.md 未記載本批新機制：`expectedComposerDismiss`（#7 的一次性旗標，是新的視窗生命週期 footgun）、`FixtureAimMath`/`setFixtureAim`、`TabletopNudge`、`resolvedDragPosition`、吊掛區可視化、#25 的 proxy 幾何替換。CLAUDE.md 是本 repo 的單一事實來源，建議合併前補。

### PLAUSIBLE（合理懷疑，需實機或特定時序才會現形）

- **E-5（P2）取消的拖曳會讓吊掛區體積殘留顯示。** `moveDrag` 只在 `.onEnded` 隱藏 hang zone；SwiftUI 手勢被系統**取消**（非正常結束）時 `@GestureState` 會重置但 `.onEnded` 不保證觸發 → 半透明體積留在場上，直到下一次拖曳結束。（proxy 位置本身會被下個 sync pass 重新就位，自癒；殘留的只有體積。）修法：在 drag 序列開始時或 `syncFixtures` pass 加一道「無拖曳進行中即隱藏」。
- **E-6（P3）composer 遲到的 onDisappear 可能誤判為使用者關窗。** 若前一次程式化 dismiss 的 onDisappear 延遲到下一個舞台 session 的 `onAppear` 重置旗標之後才觸發（旗標已被清成 false、舞台又是 open/desired）→ 誤跑 `returnToProjects`。純時序競態、機率低，掃雷報告的 [需實機] 已涵蓋「onDisappear 時序」，此處補上具體失效路徑供驗收時針對性測（快速關開專案、快速進出編輯器）。
- **E-7（P3，數學邊角）`FixtureAimMath.offset`（`LightEffect.swift:169`）近垂直 base 的退化處理可能瞄反方向。** base 幾乎垂直時 pan 強制 0、tilt 軸退回世界 X → 可達方向被鎖在單一垂直平面；若某燈被拖到正好在其 zone aim 點正上方（base≈鉛直）且 x≠0，「瞄準舞台中心」可能明顯偏差甚至反向。發生機率低（zone aim 通常斜向），但值得在退化分支改用「先解 tilt 到水平再解 pan」或直接以 desired 的 azimuth 當 pan。
- **E-8（P3，一致性）`setFixtureAim` 有 undo snapshot、既有 `rotateFixture` 沒有**（`AppModel.swift:545` vs `rotateFixture`）——編輯器內「瞄準」可撤銷、語音旋轉不可，行為不一致（rotate 缺 undo 是既有債，非本批引入）。

### 覆核為乾淨的部分（明說，免重查）

- #23 aim 數學：正逆推導正確（pan 保 elevation、tilt 在垂直面、+tilt 朝下），round-trip smoke 5 案例 + 真實 FOH 幾何釘住；`LightEffectSystem.aim` 委派消除漂移 ✓。走 `aimOffset` 而非 `fineControl`，避開 tilt 疊加陷阱 ✓。
- #19：`support` 重構為行為保留（既有回歸測試把關）、`resolvedDragPosition` 冪等且重用同組門檻常數、預覽=提交、雷射由 `moveFixture` re-clamp 保住桁架 ✓。
- #7/#11 主路徑：`Window` 單例修法正確（比照燈控卡先例）；`returnToProjects` 維持 closeProject 先於 dismissImmersiveSpace（CLAUDE.md footgun 2）；`openStageEditor` 先設 desired scene 再 dismiss，三重防護對已知程式化路徑都擋得住 ✓。
- #5 移除：全 repo grep 零殘留（Swift/pbxproj），保留項（Reduce Motion、Dynamic Type、minGazeTarget、語音輸入）都在，smoke/文件同步 ✓。
- iPad target：`CuePlayback.swift` 已入 membership、新增的 `FixtureAimMath`/`TabletopNudge`/`RigPlacement` 擴充都落在既有共用檔，不需改 membership ✓。

---

## F. 其他既有問題（非本批引入）

- **記憶檔與現實矛盾**：`~/.claude/projects/.../memory/visionos-26-downgrade.md` 寫「FM 仍在（API 名稱有差）」，但 repo 現況（CLAUDE.md + 全碼 grep）是 FM **完全移除**、OpenAI 獨佔。記憶檔已過期，建議更新以免未來 session 誤判。
- `docs/foundation-models-setup.md` 檔名與內容不符（實為 OpenAI 金鑰設定）——CLAUDE.md 已註記，屬已知待改名。
- `rotateFixture` 無 undo snapshot（見 E-8）。
- 無消費者但被 smoke 釘住的舊 iPad builder helpers、`AIComposerPlacement` 等——已知、刻意保留，不動。

---

## 優先序總表

| 級別 | 項目 |
|------|------|
| **P0** | A-1〜A-6 決策（特別是 A-6 合併/推送策略）；C-1 視窗生命週期實機驗收（被困級 UX） |
| **P1** | 修 E-1（微調鍵浮空燈）＋ E-2（proxy 朝向過期）——兩者都小、都該在合併前修；D 的 #11 情境 3 實機重現確認 |
| **P2** | E-3/E-4 文件修正；C-2/C-3 其餘實機驗收；#19 落地架高度調參；#20 半透明 fallback；E-5 取消拖曳殘留 |
| **P3** | E-6/E-7/E-8 邊角；#17 truss 微調、#23 拖曳目標球、#19 ±Y 鍵（皆另議）；F 節文件衛生 |

*覆核者：Fable 5，2026-07-08。驗證證據：smoke passed / BUILD SUCCEEDED 皆親自重跑於 `codex-issue-sweep` 工作樹。*
