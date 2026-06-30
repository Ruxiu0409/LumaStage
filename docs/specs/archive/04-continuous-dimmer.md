# SPEC 04 — 連續調光 / 捏拉調暗（手動控燈延伸）

**Goal**：把手動控燈從「亮度檔位」升級成**連續控制**(滑桿 + 在空間中捏住燈上下拉調暗),手感即時。前置障礙是 relight 走 cue 的 ~2.5s 過場,連續控制會慢半拍——本 spec 先解這個,再加連續 UI。

## Ground truth
- `AppModel.setManualIntensity(light:_:)` 已存在(寫 `lightOverrides`,renderer 觀察後 relight)。`selectedLightNumber`/`selectedLightResolved`。
- `ImmersiveView.apply(_:overrides:to:)` → `updateSpotLight(...)` 在 `withAnimation(animation(for: cue.transition))` 內設 color/intensity/cone;`cue.transition` 預設 2.5s linear。`body` 已 eager-read `lightOverrides`。
- `lightpick_<n>` pick proxy(已有 collision + InputTarget)、`SelectedLightControlView`(目前是亮度檔位)。
- `CueTransition { duration, easing }`(`LightingModels.swift`)。

## Work items
### 1. `ImmersiveView.swift`（owner A）— 手動變更走短過場
讓「手動 override 變更」用短過場(snappy),而非 cue 的 2.5s 慢淡:
- `apply` 加參數 `manualTransition: CueTransition? = nil`;`updateSpotLight` 改用 `manualTransition ?? cue.transition`(只在這條 relight 影響淡入時間)。
- `body`/`update:` 呼叫 `apply` 時:當 `appModel.selectedLightNumber != nil`(正在手動控燈)傳 `manualTransition: CueTransition(duration: 0.12, easing: "easeOut")`,否則 nil(GO/生成維持原本的場景淡入)。`body` 已讀 `selectedLightNumber`(spec 已要求);確認有讀。
- (可選)空間捏拉:在 `lightpick_<n>` 上加 `DragGesture().targetedToAnyEntity()`,把垂直位移映射成該燈強度(上亮下暗),呼叫 `appModel.setManualIntensity(light:n, current ± delta)`。用既有 `lightNumber(forPickTarget:)` 取 n;clamp 0...1。位移→強度的係數放一個 `static let`,實機調。

### 2. `SelectedLightControlView.swift`（owner B）— 滑桿取代/補充檔位
在「亮度」段把 5 顆檔位換成(或並存)一個連續 `Slider(value:in: 0...1)`,`onEditingChanged`/binding set → `appModel.setManualIntensity(light:n, $0)`;顯示百分比。保留無障礙(`accessibilityValue` 報目前 %)、≥60pt 命中。可留檔位當快捷。

## Constraints / 並行
- owner A 動 `ImmersiveView`;owner B 動 `SelectedLightControlView`。介面靠 `setManualIntensity` 既有簽名,互不依賴。
- 不改 `cue.transition` 的預設(只是 apply 多一條 override 路徑)。

## Verification
- 完整 build → SUCCEEDED。smoke 不變(純 UI/renderer)。

## Caveats
- 短過場時長(0.12s)、捏拉係數、滑桿在 2.5s 與 0.12s 之間切換有無視覺跳動,**需實機調**。連續拖曳每 tick 觸發整個 `apply`(全 rig relight)——若多燈場景吃效能,可優化成「只 relight 被改的那盞」(進階,非本 spec 必須)。
