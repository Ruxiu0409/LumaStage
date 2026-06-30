# SPEC 08 — 編組推桿與現場控制模型（Group Submasters + Live Control）

> Status: todo. 由「逐燈點選對現場操作太慢、現場要推桿」這個設計問題導出(四視角設計 panel 一致收斂)。

**Goal**：確立**編組(group)為唯一的「快速控制單位」**,並把控制**按時間切**(設計時 vs 現場),而非按裝置切。填補 `docs/maic-strategy.md §2` 的「編組/Groups 🔴」缺口,用「少數群組 submaster + GO + 語音」交付控台級現場速度——**而不去跟 grandMA2 拚逐通道 fader riding**(§5.4 護欄:我們是設計/previz 層,餵控台,不取代其現場執行)。命中 MAIC 商業前景/創新 + 決賽 Q6「把 iPad 遞給評委」的 beat。

## 控制面分工（surface map,釘死）
- **頭顯(gaze+pinch)**:設計畫布 + 現場監看。設計時——語音生成 rig+cue、走 1:1 舞台、**用看的把燈圈成命名群組**(頭顯獨有強項:看得出哪盞是哪盞)、逐燈精修。現場——看著光在 1:1/房間溢光落定、按一個常駐 **GO**;可選 gaze 選**整組**(不是單燈)做 nudge。**頭顯永不 ride 推桿。**
- **iPad(多點觸控)**:現場觸覺主場——**4–6 支大型直立群組 submaster 推桿**,可多指同時 ride,每支帶 bump/flash + solo;常駐 GO footer + 目前/下一個 cue 條。逐燈詳情頁保留為設計時 drill-in。
- **語音**:即時零星抓燈(全域 `blackout`/`all on`/`GO`/`回開場` + 群組 `前光調暗一半`/`movers to blue`/`kill the blinders`/`只留主光`)。走既有 deterministic `LightCommand.parse`,**絕不進 AI**(延遲+不確定)。
- **GO(cue stack)**:現場主原語(~80–90% 跑秀),**已實作**——只需把它升成各面最大、最易達的常駐目標。

## 載重不變式（MUST smoke-test）
解析改為:`final intensity = override.isOff ? 0 : (override.intensity ?? (cueIntensity × groupMaster))`。
- 群組 master(0...1,比例縮放)只影響**沒有**逐燈明確強度覆寫的燈;
- **逐燈明確覆寫贏過群組 master**(channel 壓過 submaster,真控台行為);
- 顏色覆寫照舊套用,不受 master 影響;
- 一盞燈屬多組時,其有效 master 取各組 master 的 **HTP(取最大)**,預設 1.0。

## Ground truth（沿用,附 file 參考——agent 請以實際程式碼為準）
- `FixtureGroup.role: FixtureRole` + `.zone: StageZone`(`LightingModels.swift`,enums 在同檔)——免費的分組軸,**不需動 @Generable**。
- `LightOverride` + `resolved(cueColor:cueIntensity:)`(`LightingModels.swift`)——要擴充的 transient-layer 與解析點。
- `AppModel.lightOverrides: [Int: LightOverride]`、`applyLightCommand`、逐燈 setter、在 `openProject`/`generate` 清空——要一般化的層;群組 master 沿用同語義(清除時機相同、跨 AI 生成保留)。
- GO 已備:`StageState.goToNextCue/goToPreviousCue`、`AppModel.goToNextCue/goToPreviousCue`、`LumaControlCommand.goToNextCue/goToPreviousCue`。
- `LumaControlCommand`(`LumaSyncProtocol.swift`)+ `lumaSyncProtocolRoundTrips`——加 case 要同步更新 host receiver(`LumaSyncCoordinator`)與 round-trip 測試。
- `LightCommand.parse` + `colorNames`(`LightingModels.swift`)——擴群組名詞。
- iPad `PanelLightingView`(`iPadPanel/`)、頭顯 `SelectedLightControlView`、`ImmersiveView.apply`(解析發生處,要把 groupMaster 折入)、`RelightDebugSnapshot`(讀數要一致)。
- 渲染端 `ImmersiveView.apply` 目前 `let resolved = override.resolved(cueColor:..., cueIntensity:...)`——改為先算該 fixture 的有效 groupMaster,再傳入新的 resolved。**SPEC 04 已在 `apply` 加了 `manualTransition`(0.12s 短過場);群組 master 變更沿用它,讓 iPad 推桿即時回應、不被 2.5s cue 過場拖慢。**

## Work items（一檔一 agent;契約釘死,介面靠本 spec 對齊)
- **A — `LightingModels.swift`**:新增 Foundation-only `FixtureGroupMask`(id、name、`members: [String]` 或 role/zone predicate;auto-seed:前光/背景洗/上舞台/動態/全部,從每個 `FixtureGroup` 既有 role/zone 推導)。擴解析:新增 `LightOverride.resolved(cueColor:cueIntensity:groupMaster:)`(或一個純函式),實作上面的載重不變式;舊的兩參數版可保留轉呼叫(groupMaster=1)。**純邏輯,無 @Generable 變更。**
- **B — `Tests/LumaStageCoreSmokeTests.swift`**:`groupAutoSeedFromRoleZone`(從 role/zone 自動編組正確)+ `groupMasterResolutionAndPrecedence`(master 縮放、單燈覆寫壓過 master、isOff、顏色不受影響、多組 HTP),註冊進 `main()`。同步把任何新 Foundation 檔加進編譯集(見 specs/README)。
- **C — `AppModel.swift`**:`groups: [FixtureGroupMask]` + `groupMasters: [String: Double]`;`setGroupMaster(id:level:)`/`bumpGroup(id:on:)`/`clearGroupMaster(id:)`(安靜地動 transient 層,不洗 conversationState);`generate`/`openProject` 時 auto-derive 預設群組並清空 masters(沿用 lightOverrides 清除點)。提供 renderer 取「某 fixture 的有效 groupMaster」的查詢。
- **D — `LumaSyncProtocol.swift`(+ `LumaSyncCoordinator` 接收端)**:加 `LumaControlCommand.setGroupMaster(groupId:level:)` / `bumpGroup(groupId:on:)`(1:1 對 C 的方法),host receiver 同步映射,擴 `lumaSyncProtocolRoundTrips`。
- **E — `iPadPanel/PanelFaderBankView.swift`(新)+ `PanelLightingView` 重構**:4–6 支高直立群組推桿(每支 ≥60pt 寬、全高 throw、即時 %、組名、bump+solo),可多指同時 ride(非互斥手勢);常駐 GO footer + cue 條。逐燈詳情頁保留設計時 drill-in。
- **F — `ImmersiveView.swift`**:`apply` 折入 groupMaster(每 fixture 算有效 master → 傳入新 resolved);把 GO 升成 composer 內常駐按鈕。(注意 Observation footgun:body 需 eager-read 任何新 @Observable 狀態如 `groupMasters`。)
- **G — `SelectedLightControlView.swift`(重定位)+ 語音**:把卡片**重新定位為「設計微調 / programmer」**(明確移出現場路徑);加「加入群組 / 新群組」(設計時空間化編組)與可選「控制群組」master nudge。語音:擴 `LightCommand.parse` 群組名詞 + solo(走 `applyLightCommand`/group master 路徑)。

## 重定位（已存在功能）
頭顯逐燈點選卡 **從「現場單燈操作面(慢、錯位)」重新定位為「設計時 programmer + 空間化編組工具」**——保留它真正擅長的兩件事:(1) 編曲時逐燈精修(慢沒關係,你在創作不是跑秀;**單燈**連續滑桿+捏拉調暗已由 SPEC 04 實作,且走 0.12s 短過場、不再跟 2.5s cue 過場打架);(2) **空間化編組**(看著三盞燈→圈成一組),這是頭顯獨有優勢。頭顯不放的是**多組同時 ride**——gaze+pinch 無法同時 ride 多支推桿,那是 iPad 群組推桿的事。淨效果:頭顯不再跟 iPad 搶,而是**餵** iPad——頭顯定義群組與單燈精修,iPad 同時 ride 群組。

## Constraints / 並行
- A 先成立型別與解析(B/C/D/F 的前置);其餘對契約寫,最後一起編譯。一檔一 agent(D 的 host receiver 與 C 協調)。
- 不開第二套 override 狀態——群組 master 必須**折入既有** cue→override 解析,不另起平行 state。

## 明確不做（護欄）
- 逐通道虛擬推桿牆(頭顯 or iPad)、**頭顯多支同時 ride 推桿**(gaze 做不到;單燈精修滑桿已由 04 提供,OK)、AI 進現場路徑、timecode/SMPTE/MIDI、sound-to-light 現場引擎、賽前即時 Art-Net/sACN、新的任意分組 schema 或 @Generable 變更、取代/複雜化 GO。

## Verification
- smoke(A 的型別/解析 + B 的測試)→ `LumaStageCoreSmokeTests passed`。
- 完整 build → `** BUILD SUCCEEDED **`。
- 實機:iPad 同時 ride 3 支群組推桿 → 頭顯鏡像即時 relight;確認單燈覆寫壓過群組 master;Q6「把 iPad 遞給評委、三指推三組過副歌」的 beat 成立。
