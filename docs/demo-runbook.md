# LumaStage MVP Demo Runbook

## 追求目標

本週 Demo 的追求目標是展示一套可運作的端到端系統，而不是概念稿或靜態 mockup。

Demo 必須讓觀眾看到：

1. 使用者透過語音或 typed prompt 描述舞台燈光需求。
2. AI 將需求轉成 `Opening` / `Highlight` 兩個 cue 的 lighting look。
3. Apple Vision Pro 顯示 `standardNight` 夜間室外舞台，並依照 selected cue 呈現燈光。
4. 使用者切換 cue 時，舞台用 transition animation 過渡。
5. iPad-style 微調面板只 patch selected cue。
6. AI box 顯示 mic state、transcript、AI understood command、explanation 與 AI source。

## Demo 前設定

### Apple Foundation Models（Apple Intelligence）

AI 生成使用 Apple 裝置端 Foundation Models，**不需要 API key 或網路設定**。請以 Xcode 27 建置，並在 visionOS 27 / iOS 27 模擬器或實機的「設定」中啟用 Apple Intelligence。

若 Apple Intelligence 無法使用，AI 對話框會顯示無法使用的原因，並停用語音與送出，**不會生成燈光**（沒有本機 demo fallback）。詳見 `docs/foundation-models-setup.md`。

### Speech-to-text

第一次按下 mic 時，系統會要求 microphone / speech recognition 權限。若權限或語音辨識失敗，直接使用 typed prompt fallback。

建議語音測試句：

```text
做一個冷色的開場，front light dimmer 大概 60%，background wash 要藍一點
```

備援 typed prompt：

```text
做一個冷色 Highlight，front light dimmer 亮一點，background wash 改藍一點
```

## Demo Flow

### 1. 開啟主畫面

確認主畫面顯示：

- 左側 `LumaStage` 舞台預覽。
- 右側 floating AI conversation box。
- 右下 iPad-style 微調面板。
- 舞台 baseline 為 `standardNight`。
- 初始 selected cue 為 `Opening`。

### 2. 語音或文字生成 Lighting Look

優先使用 mic：

1. 按下 `Mic`。
2. 說出燈光需求。
3. 再按一次停止錄音。
4. 等待 AI box 進入 `explaining`。

若 speech-to-text 不穩定：

1. 在 typed prompt fallback 輸入需求。
2. 按 `Generate`。

驗收重點：

- `transcript` 顯示使用者輸入。
- `AI understood command` 顯示 AI 理解。
- `explanation` 顯示業界詞與白話說明。
- `AI source` 顯示 `Apple Foundation Models`（無法使用時改顯示原因）。

### 3. 切換 Cue

在 iPad-style panel 的 segmented control 切換：

- `Opening`
- `Highlight`

驗收重點：

- selected cue ID 更新。
- 舞台預覽跟著變化。
- transition animation 不應直接跳狀態。

### 4. iPad-style 微調

只調整 selected cue：

1. 拖曳 `front light dimmer` slider。
2. 點選 `background wash color` swatch。
3. 觀察 `selected cue patch` 數值。
4. 觀察舞台預覽即時更新。

驗收重點：

- `frontLight.intensity` 介於 `0.0...1.0`。
- `backgroundWash.color` 為 RGB hex。
- 調整 `Opening` 不會改到 `Highlight`。
- 調整 `Highlight` 不會改到 `Opening`。

### 5. Reset Selected Cue

按下 `Reset`。

驗收重點：

- 只還原目前 selected cue。
- 另一個 cue 保留自己的狀態。
- AI explanation 顯示 reset 只回復 cue baseline。

## MVP 驗收清單

- [ ] App 可在 visionOS Simulator 啟動。
- [ ] 主畫面有 stage preview、floating AI box、iPad-style panel。
- [ ] speech-to-text 可啟動，失敗時可用 typed prompt fallback。
- [ ] AI 生成固定輸出 `Opening` / `Highlight`。
- [ ] `ambient.preset` 固定為 `standardNight`。
- [ ] cue 切換有 transition animation。
- [ ] iPad-style panel 只能調整 selected cue。
- [ ] reset 只還原 selected cue。
- [ ] AI box 顯示 mic state、transcript、understood command、explanation、AI source。
- [ ] 無 `darkNight` / `brightSurroundings` / full cue timeline / lighting-console export。

## 目前不是本週 Demo 的內容

- 真 iPad companion app 與跨裝置同步。
- 真實舞台 AR 對位與真實場景打光。
- DMX / console export。
- 完整燈控台或完整 cue timeline editor。
- rigging、truss 承重與場地工程圖落差模擬。
