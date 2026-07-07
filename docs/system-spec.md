# LumaStage Apple Vision Pro / iPad MVP 系統規格書

> 註：目標平台為 **visionOS 26**（主 app，部署目標 26.0）＋ **iPadOS 26**（可選的「LumaStage Control」控制面板 companion target，透過 Multipeer Connectivity 即時遠端連線）。兩者皆需 **Xcode 26.4**（OS 26 SDK）。
>
> 註（2026-07，visionOS 26 港版）：本次降版把 AI 生成層**改回 OpenAI 雲端獨佔**——**Apple 裝置端 Foundation Models 已完整移除**（`FoundationModelsLightingService.swift`／`FallbackLightingService.swift` 皆刪除、無 `import FoundationModels`、無裝置端生成、無備援鏈、無「強制裝置端／隱私模式」開關）。下方所有提及「裝置端 Foundation Models」的歷史 註仍保留作紀錄，但**現況**一律以 OpenAI 雲端生成為準。此外三個 visionOS 27-only 的 RealityKit API 在 26 上不可用而移除：房間溢光的 `SpotLightComponent.SurroundingsLight`（房間溢光模式仍切透視 + `.preferredSurroundingsEffect(.dim)` + 隱藏不透明場景，但虛擬燈**無法**打亮真實房間）、軟陰影細部（`Shadow.lightSize` penumbra + per-role `quality`，改用基本 `SpotLightComponent.Shadow()`）、gobo 投影（`SpotLightComponent.ProjectiveTexture`，見下方 gobo 註）。
>
> 註：iPad 子系統（第 7 章）已從產品中移除，LumaStage 現為 **visionOS 單一 app**（外加可選 iPad 控制面板）。原 iPad 微調控制（cue 切換、front light dimmer、background wash color、reset）目前未在任何 visionOS 介面提供。以下章節保留作為歷史規格紀錄。
>
> 註：燈具現以真實 RealityKit `SpotLight` 渲染。gobo（breakup／stripes／stars／grid）資料仍由 AI 在雲端生成時選擇、經 `validate()` 保存於專案中，但在 **visionOS 26 上僅為資料、不再投影**（`SpotLightComponent.ProjectiveTexture` 為 27-only 已移除）；`resetSelectedCue` 會還原 AI 基準的 gobo 欄位，而非清除它。

## 1. 文件目的

本文件定義 `LumaStage` 本週 MVP 的 Apple Vision Pro 與 iPad 系統規格，供工程實作、Demo 準備與功能驗收使用。

本文件以 `docs/brainstorming.md` 內已定案的 MVP 決策為準，將討論內容整理成可執行的系統規格。原始 brainstorming 文件保留作為產品討論紀錄，本文件只描述本週 MVP 必須完成的功能與資料邊界。

## 2. MVP 目標

`LumaStage` 是一個 Apple Vision Pro + iPad 的 AI 舞台燈光設計 Demo。使用者在 Apple Vision Pro 中進入一個 1:1 夜間室外舞台數位分身，透過語音和 AI 對話生成 cue-based 舞台燈光，再用 iPad 做少量精準微調，並在 Vision Pro 中立即看到變化。

### 2.1 追求目標

本週 MVP 的追求目標是完成一套可運作的端到端系統，而不只是概念稿或靜態展示。系統必須能串起 Apple Vision Pro 沉浸預覽、speech-to-text 或 typed prompt、OpenAI cue-based 生成、shared stage state、iPad 微調與 Vision Pro 即時更新。

完成系統的最低標準是：使用者能從語音或文字輸入開始，生成兩個 cue 的 lighting look，在 Vision Pro 中切換 cue 並看到 transition animation，再用 iPad 修改 selected cue 的 dimmer 或 background wash color，最後看到 AI explanation。

本週 MVP 要展示一條可信的 Core Experience：

```text
進入 standardNight 夜間室外舞台
-> 使用 speech-to-text 說出燈光需求
-> AI 解析中英混講 transcript
-> OpenAI API 產生 cue-based 燈光配置
-> Apple Vision Pro 套用 selected cue
-> cue 切換時以 transition animation 過渡
-> iPad 微調 selected cue 的 dimmer 或 wash color
-> AI 用業界詞加白話解釋這次調整
```

## 3. MVP 範圍

### 3.1 本週必做

- Apple Vision Pro 顯示 1:1-style 夜間室外舞台數位分身。
- 舞台環境固定使用 `standardNight` baseline。
- Vision Pro 顯示單一 floating AI conversation box。
- 使用真實 speech-to-text 作為主要輸入方式。
- 支援中文句子中穿插英文燈光詞彙，例如 `front light dimmer`、`background wash`。
- OpenAI API 產生 cue-based lighting look JSON。
- MVP lighting look 固定包含兩個 cue：`Opening` 與 `Highlight`。
- cue 切換時依照 transition 設定做 intensity / color animation。
- iPad 提供輕量微調面板。
- iPad 只提供三個控制：`front light dimmer`、`background wash color`、`reset`。
- iPad 所有微調只作用在目前的 `selectedCueId`。
- AI 回傳一段簡短解釋，保留業界詞並搭配初學者聽得懂的說明。

### 3.2 本週不做

- 不把虛擬燈光投射到真實舞台。
- 不做完整 iPad 編輯器。
- 不做完整 cue timeline editor。
- 不做 lighting-console export。
- 不做 DMX universe / address / patch 資料。
- 不做 rigging、truss、承重或工程圖落差模擬。
- 不做室內窗戶日光模擬。
- 不做白天、黃昏或多種夜間環境光切換。
- 不做 `darkNight` / `brightSurroundings` preset。
- 不做 `PAR`、`moving head`、`side light`、`ambient fill` 等進階燈具詞彙。
- 不做 MIDI、音樂反應、多使用者或錄製輸出。

## 4. 目標使用者與 Demo 情境

### 4.1 主要使用者

- 學生活動與初學者：需要在沒有完整設備和場地資源的情況下練習舞台燈光設計。
- 初階燈光設計學習者：需要知道基本燈具名稱、顏色、dimmer / intensity，才能更精準地和 AI 溝通。
- 未來延伸對象：專業燈光師可用於進場前 previs，但本週 MVP 不承諾專業級燈控輸出。

### 4.2 Demo 場景

- 場景為夜間室外學生舞台。
- 不假設 LED 螢幕。
- 不處理吊掛點、承重或現場 rigging 問題。
- 舞台環境光固定為 `standardNight`。
- Demo 重點是 AI 生成燈光、cue 切換動畫、iPad 微調與 AI 解釋。

## 5. 系統總覽

### 5.1 子系統

| 子系統 | 主要職責 |
| --- | --- |
| Apple Vision Pro App | 顯示沉浸式舞台、floating AI conversation box、selected cue 預覽與 cue transition animation。 |
| iPad Control Panel | 提供 selected cue 的少量精準微調控制。 |
| Speech-to-text Pipeline | 將使用者語音轉成 transcript，保留中英混講內容。 |
| AI Command Parser | 將 transcript 或 typed prompt 轉成結構化 lighting look 或 patch intent。 |
| Cloud Generation Layer | 以 OpenAI 雲端（Responses API + strict `json_schema`，model `gpt-5.5`）產生 Lighting Look 與 explanation。〔歷史上曾改用 Apple 裝置端 Foundation Models，visionOS 26 港版已改回 OpenAI 雲端獨佔。〕 |
| Shared Stage State | 保存目前 lighting look、selected cue、fixture group 狀態與 UI 狀態。 |
| RealityKit Stage Renderer | 根據 selected cue 渲染燈光狀態，並在 cue 切換時做 transition animation。 |

### 5.2 基本資料流

```text
User voice
-> Speech-to-text
-> transcript
-> AI command parsing / OpenAI structured output
-> LightingLook schema
-> Shared Stage State
-> Vision Pro RealityKit renderer
-> iPad selected cue controls
-> patch selected cue
-> Shared Stage State
-> Vision Pro immediate preview
```

typed prompt fallback 使用同一條資料流，只是跳過 speech-to-text：

```text
Typed prompt
-> AI command parsing / OpenAI structured output
-> LightingLook schema
-> Shared Stage State
```

## 6. Apple Vision Pro 子系統規格

### 6.1 沉浸式舞台

Apple Vision Pro 必須顯示一個 1:1-style 夜間室外舞台數位分身。MVP 不要求 photorealistic，但視覺必須可信、穩定、能清楚看出燈光變化。

舞台環境固定為：

- `ambient.preset = "standardNight"`
- `ambient.level = 0.35`
- `ambient.colorTemperature = 4200`

上述環境光欄位可以存在於 schema 中，但 MVP 不提供 UI 控制，也不做 preset 切換。

### 6.2 Floating AI Conversation Box

Vision Pro 介面只顯示一個 floating AI conversation box，不做完整控制台。最小內容固定為四項：

| 顯示項目 | 說明 |
| --- | --- |
| `mic state` | 顯示目前是 idle、listening、transcribing、interpreting、applying、explaining 或 error。 |
| `transcript` | 顯示 speech-to-text 取得的原始使用者語句。中英混講必須保留。 |
| `AI understood command` | 顯示 AI 對 transcript 的理解，例如「把 front light dimmer 降到 60%」。 |
| `explanation` | 顯示一段業界詞 + 白話說明，例如 dimmer / intensity 是燈的亮度。 |

### 6.3 Cue 預覽與切換

Vision Pro renderer 必須以 `selectedCueId` 決定目前顯示的 cue。

MVP 固定兩個 cue：

- `Opening`
- `Highlight`

當 `selectedCueId` 改變時，舞台不可直接跳狀態，必須依照目標 cue 的 transition 設定做動畫。

MVP transition 規則：

- `duration` 預設 `1.2` 秒。
- `easing` 預設 `easeInOut`。
- 至少要對 fixture group 的 `intensity` 與 RGB `color.value` 做過渡。

### 6.4 Vision Pro 狀態

Vision Pro 至少需要管理下列狀態：

| 狀態 | 說明 |
| --- | --- |
| immersive space state | 目前沉浸空間是否 closed、inTransition 或 open。 |
| conversation state | AI 對話框目前狀態。 |
| current transcript | 最近一次 speech-to-text 結果。 |
| understood command | AI 解析後的指令摘要。 |
| lighting look | 最新完整 `LightingLook`。 |
| selected cue id | 目前正在顯示或被 iPad 編輯的 cue。 |
| last error | speech-to-text、OpenAI 或 schema 套用錯誤。 |

## 7. iPad 子系統規格

### 7.1 角色定位

iPad 是微調面板，不是完整燈控台。它只負責讓使用者在 AI 生成後做少量、穩定、可預期的精準調整。

### 7.2 MVP 控制項

iPad MVP 只提供三個控制：

| 控制 | 作用目標 | 行為 |
| --- | --- | --- |
| `front light dimmer` | selected cue 的 `front_wash` 或 role 為 `frontLight` 的 fixture group | 調整 `intensity`，範圍 `0.0...1.0`，UI 可顯示為 0% 到 100%。 |
| `background wash color` | selected cue 的 `background_wash` 或 role 為 `backgroundWash` 的 fixture group | 調整 RGB hex color。 |
| `reset` | selected cue | 將 selected cue 還原為 AI 生成後的 baseline 狀態，不重置整份 lighting look。 |

### 7.3 Patch 規則

- iPad 操作不得直接覆蓋整份 `LightingLook`。
- iPad 操作必須產生 selected cue patch。
- patch 只可改動目前 `selectedCueId` 對應 cue 內的 fixture group。
- patch 後 Vision Pro 必須立即更新預覽。
- reset 只還原 selected cue，不影響另一個 cue。

### 7.4 iPad 不做項目

- 不提供 fixture placement。
- 不提供 cue timeline editor。
- 不提供設備表。
- 不提供環境光 preset 切換。
- 不提供 DMX / console export。

> 註（歷史）：曾一度將 AI 生成層由雲端 OpenAI API 改為 Apple 裝置端 Foundation Models（Apple Intelligence），透過 `@Generable` 結構化輸出產生。
>
> 註（2026-07，現況，visionOS 26 港版）：上述裝置端 Foundation Models 改動**已完全逆轉**——AI 生成層**改回 OpenAI 雲端獨佔**（Responses API + strict `json_schema`，model `gpt-5.5`，金鑰存 Keychain、經 `ProjectSelectionView` 齒輪 → `OpenAISettingsView` 設定，有非空金鑰才可用，失敗一律 `.generationFailed(<繁中>)`）。以下「結構化輸出」與「驗證」規格不變。

## 8. Speech-to-text 與 OpenAI 雲端生成規格

### 8.1 Speech-to-text

MVP 必須使用真實 speech-to-text 作為主要輸入。使用者可以使用中文、英文，或中英混講。

範例語句：

- 「做一個溫暖的開場燈光。」
- 「把 front light dimmer 降到 60%。」
- 「background wash 改冷一點。」
- 「這盞燈是做什麼的？」

transcription prompt 應包含 MVP 燈光詞彙，降低專業詞被誤聽的機率：

- `wash`
- `spot`
- `front light`
- `background wash`
- `dimmer`
- `intensity`
- `電門`
- `亮度`

### 8.2 Typed Prompt Fallback

若 speech-to-text 在 Demo 當天失敗，系統使用 typed prompt 作為備援。typed prompt 不應走另一套邏輯，必須接續相同的 AI parsing 與 OpenAI structured output 流程。

觸發 fallback 的情境：

- 麥克風權限失敗。
- speech-to-text timeout。
- transcription 回傳空字串。
- transcription 內容明顯不可用。

### 8.3 OpenAI Structured Output

OpenAI 回傳內容必須符合 MVP Lighting Look Schema。MVP 需要兩種 AI 結果：

| 結果類型 | 說明 |
| --- | --- |
| full generation | 根據使用者 prompt 建立完整 `LightingLook`，包含兩個 cue。 |
| local edit | 根據使用者命令或 iPad patch 更新 selected cue 的部分欄位。 |

OpenAI 回傳不得作為自由文字直接套用。系統必須先通過 schema parse / validation，再更新 Shared Stage State。

### 8.4 AI Explanation

每次生成或修改後，AI 至少回傳一段 explanation。格式固定包含：

- `term`
- `plainText`
- `actionSummary`

explanation 必須和實際變更的 fixture、cue、color 或 intensity 有關，不應生成泛用課程文字。

## 9. MVP Lighting Look Schema

### 9.1 JSON 範例

```json
{
  "schemaVersion": "1.0",
  "intent": "generateLook",
  "lookName": "Warm Opening Look",
  "mood": "warm, welcoming, student event",
  "ambient": {
    "preset": "standardNight",
    "level": 0.35,
    "colorTemperature": 4200
  },
  "selectedCueId": "cue_opening",
  "cues": [
    {
      "id": "cue_opening",
      "name": "Opening",
      "transition": {
        "duration": 1.2,
        "easing": "easeInOut"
      },
      "fixtureGroups": [
        {
          "id": "front_wash",
          "name": "Front Wash",
          "role": "frontLight",
          "zone": "stageFront",
          "enabled": true,
          "intensity": 0.6,
          "color": {
            "mode": "rgb",
            "value": "#FFD1A3"
          }
        },
        {
          "id": "background_wash",
          "name": "Background Wash",
          "role": "backgroundWash",
          "zone": "stageBack",
          "enabled": true,
          "intensity": 0.75,
          "color": {
            "mode": "rgb",
            "value": "#4FA8FF"
          }
        }
      ]
    },
    {
      "id": "cue_highlight",
      "name": "Highlight",
      "transition": {
        "duration": 1.2,
        "easing": "easeInOut"
      },
      "fixtureGroups": [
        {
          "id": "front_wash",
          "name": "Front Wash",
          "role": "frontLight",
          "zone": "stageFront",
          "enabled": true,
          "intensity": 0.75,
          "color": {
            "mode": "rgb",
            "value": "#FFE0B8"
          }
        },
        {
          "id": "background_wash",
          "name": "Background Wash",
          "role": "backgroundWash",
          "zone": "stageBack",
          "enabled": true,
          "intensity": 0.9,
          "color": {
            "mode": "rgb",
            "value": "#2F6BFF"
          }
        }
      ]
    }
  ],
  "explanation": {
    "term": "Dimmer / intensity",
    "plainText": "Dimmer means how bright the light is. 60% keeps the performer visible without making the front light overpower the background.",
    "actionSummary": "Generated Opening and Highlight cues with a brighter cool background for contrast."
  }
}
```

### 9.2 欄位規格

| 欄位 | 型別 / 範例 | 規格 |
| --- | --- | --- |
| `schemaVersion` | `"1.0"` | schema 版本。MVP 固定為 `"1.0"`。 |
| `intent` | `generateLook` | 操作意圖。MVP 支援 `generateLook`、`localEdit`、`explainOnly`、`resetLook`。 |
| `lookName` | `"Warm Opening Look"` | 給人看的燈光 look 名稱。 |
| `mood` | `"warm, welcoming, student event"` | 使用者需求的情緒摘要。 |
| `ambient.preset` | `"standardNight"` | MVP 固定值。 |
| `ambient.level` | `0.35` | MVP 固定值，不提供 iPad 控制。 |
| `ambient.colorTemperature` | `4200` | MVP 固定值，不提供 iPad 控制。 |
| `selectedCueId` | `"cue_opening"` | 目前顯示與編輯的 cue。 |
| `cues` | array | MVP 固定兩個 cue：`Opening` 與 `Highlight`。 |
| `cues[].id` | `"cue_opening"` | cue 穩定 ID。 |
| `cues[].name` | `"Opening"` | cue 顯示名稱。 |
| `cues[].transition.duration` | `1.2` | 切換到該 cue 的動畫秒數。 |
| `cues[].transition.easing` | `"easeInOut"` | 切換到該 cue 的 easing。 |
| `cues[].fixtureGroups[].id` | `"front_wash"` | fixture group 穩定 ID。 |
| `cues[].fixtureGroups[].name` | `"Front Wash"` | fixture group 顯示名稱。 |
| `cues[].fixtureGroups[].role` | `"frontLight"` | MVP 支援 `wash`、`spot`、`frontLight`、`backgroundWash`。 |
| `cues[].fixtureGroups[].zone` | `"stageFront"` | MVP 支援 `stageFront`、`stageBack`、`stageLeft`、`stageRight`、`fullStage`。 |
| `cues[].fixtureGroups[].enabled` | `true` | 該 fixture group 在該 cue 是否啟用。 |
| `cues[].fixtureGroups[].intensity` | `0.6` | dimmer / intensity，範圍 `0.0...1.0`。 |
| `cues[].fixtureGroups[].color.mode` | `"rgb"` | MVP 固定使用 `rgb`。 |
| `cues[].fixtureGroups[].color.value` | `"#FFD1A3"` | RGB hex color。 |
| `explanation.term` | `"Dimmer / intensity"` | 這次要教或強化的業界詞。 |
| `explanation.plainText` | string | 初學者聽得懂的短解釋。 |
| `explanation.actionSummary` | string | AI 對這次生成或修改的摘要。 |

## 10. Shared State 與資料更新規則

### 10.1 Shared Stage State

系統必須有一份 shared stage state，讓 Apple Vision Pro、iPad、OpenAI 結果與 speech-to-text 流程操作同一份資料。

最小 shared state：

```text
LightingLook?
selectedCueId
conversationState
transcript
aiUnderstoodCommand
lastExplanation
lastError
```

### 10.2 更新來源

| 來源 | 可更新資料 |
| --- | --- |
| OpenAI full generation | 可替換整份 `LightingLook`。 |
| OpenAI local edit | 可 patch selected cue 或指定 cue。 |
| iPad micro-control | 只可 patch selected cue 的指定 fixture group 欄位。 |
| reset | 只可還原 selected cue 到 AI 生成 baseline。 |
| cue selector | 只可更新 `selectedCueId`，並觸發 transition animation。 |

### 10.3 Validation 規則

套用任何 OpenAI 或 iPad patch 前，必須檢查：

- `selectedCueId` 必須存在於 `cues`。
- `cues` 必須至少包含 `cue_opening` 與 `cue_highlight`。
- `ambient.preset` 必須為 `standardNight`。
- `intensity` 必須在 `0.0...1.0`。
- `color.mode` 必須為 `rgb`。
- `color.value` 必須是六位數 hex color。
- `role` 必須屬於 MVP fixture vocabulary。

Validation 失敗時，不得更新舞台狀態，必須進入 error / retry 狀態。

## 11. 錯誤狀態與復原流程

| 錯誤 | 使用者可見狀態 | 復原方式 |
| --- | --- | --- |
| 麥克風權限失敗 | AI box 顯示 microphone error。 | 切換到 typed prompt fallback。 |
| speech-to-text timeout | AI box 顯示 transcription failed。 | 允許重新錄音或 typed prompt。 |
| transcript 不可用 | AI box 顯示沒有聽清楚。 | 允許重新錄音或 typed prompt。 |
| OpenAI API 失敗 | AI box 顯示 generation failed。 | 保留目前 lighting look，允許 retry。 |
| schema parse 失敗 | AI box 顯示 AI result invalid。 | 不套用新結果，允許 retry。 |
| iPad patch target 不存在 | iPad 顯示 selected cue unavailable。 | 保留目前狀態，要求重新選 cue 或 reset。 |
| cue transition 失敗 | 舞台回到目前 selected cue 的穩定狀態。 | 停止動畫，不破壞 shared state。 |

## 12. 驗收標準

### 12.1 Core Flow

- 使用者可以進入 Vision Pro 沉浸式夜間室外舞台。
- floating AI conversation box 可顯示 mic state、transcript、AI understood command、explanation。
- 使用者可透過 speech-to-text 輸入燈光需求。
- speech-to-text 失敗時可改用 typed prompt。
- OpenAI 回傳符合 MVP Lighting Look Schema 的 cue-based lighting look。
- Vision Pro 可顯示 selected cue。
- 切換 `Opening` / `Highlight` 時會以 transition animation 過渡。
- iPad 可調整 selected cue 的 front light dimmer。
- iPad 可調整 selected cue 的 background wash color。
- iPad reset 只還原 selected cue。
- 每次生成或修改後，AI 提供一段與實際改動相關的 explanation。

### 12.2 Schema

- JSON 範例可讀且欄位一致。
- `ambient.preset` 只允許 `standardNight`。
- `cues` 固定使用 `Opening` 與 `Highlight` 作為 MVP demo cue。
- fixture vocabulary 限制在 `wash`、`spot`、`frontLight`、`backgroundWash`。
- `intensity` 使用 `0.0...1.0`。
- `color.value` 使用 RGB hex。

### 12.3 非 MVP 防線

驗收時必須確認系統沒有把下列功能做成本週必做：

- `darkNight` / `brightSurroundings` 切換。
- `PAR` / `moving head` 等進階燈具詞彙。
- 完整 cue timeline editor。
- lighting-console export。
- real-world AR lighting。
- rigging / truss / load capacity 模擬。

## 13. 未來範圍

以下項目只作為未來展望，不屬於本週 MVP：

- 完整 iPad 精準編輯器。
- 完整 cue timeline editor。
- timeline scrubbing 與 production-grade cue sequencing。
- `darkNight` / `brightSurroundings` 等夜間環境光切換。
- 白天、黃昏、室內窗戶日光模擬。
- `PAR`、`moving head`、`side light`、`ambient fill` 等進階燈具詞彙。
- DMX / lighting-console export。
- MIDI、音樂反應、多使用者。
- 真實場地 AR 對齊與真實舞台打光。
- rigging、truss、承重與工程圖落差模擬。
- Realtime API speech-to-speech 對話。
