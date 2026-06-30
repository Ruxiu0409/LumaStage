# SPEC 10 — OpenAI 雲端燈光生成後端（OpenAI 優先 + FM 備援，保留 FM 架構）

> Status: done（已實作、完整 build 綠、smoke 綠；live OpenAI endpoint 需實機/真 key 補驗）

**Goal**：在現有 `LightingLookGenerating` seam 後面新增 `OpenAILightingService`（OpenAI Responses API + strict `json_schema`），並用一個 Foundation-only 的組合器 `FallbackLightingService` 表達**「OpenAI 優先、失敗自動退回裝置端 FM」**。所有結果都灌進**完全相同**的 `LightingLookDraft` → `LightingLook.validate()` 路徑。`AppModel` 的生成流程、可用性 gate、繁中錯誤呈現、cue 編輯、views **一律不動**。對應 MAIC：給 demo 一條「裝置不支援 Apple Intelligence 或要更強模型時」的雲端路徑，同時用 `FallbackLightingService` 把**裝置端、離線、隱私**保留為備援底線（誠實敘事，見 `maic-strategy.md` §社會價值 / `docs/social-value.md`）。

## 本 spec 的前提（使用者已拍板）

- **後端策略 = OpenAI 預設、FM 備援**。用 `FallbackLightingService(primary: OpenAI, secondary: FM)` 表達；`AppModel` 只是換掉注入的 `aiClient`，**不是** FM 預設 + 手動切換。
- **交付 = 本 spec**，之後派 subagent 實作（一檔一 agent，見 `README.md` 並行守則）。

> ⚠️ **檔案擁有權**：本 spec 新增 `OpenAILightingService.swift`、`FallbackLightingService.swift`、`OpenAIKeychain.swift`（**皆 Foundation-only，禁止 import FoundationModels**）、一個極小的設定 UI 檔（key 輸入）。改 `LightingAIService.swift`（+1 個 `LightingGenerationSource` case、+1 個可注入網路邊界型別）、`AppModel.swift`（只動 `makeDefaultLightingClient`）、`project.pbxproj`（隱私字串，視需要）、`Tests/LumaStageCoreSmokeTests.swift`（新測試 + `main()` 註冊）、`docs/specs/README.md` + 根 `CLAUDE.md`（smoke 編譯集）。

## 核心原則（不可違反）

1. **驗證器是唯一權威**。`LightingLook.validate()`（`LightingModels.swift:785`）與 `LightingLookDraft.makeValidatedLook(lookName:mood:cues:…)`（`LightingAIService.swift:157`，多 cue 版）是 count / range / hex / schema 的單一真相來源，FM 路徑與 OpenAI 路徑**共用**。OpenAI 後端**不得**自行重寫任何 range/count/hex 檢查——只負責「網路 → JSON → 既有 draft 型別」的解碼。
2. **新檔 Foundation-only**。`OpenAILightingService` / `FallbackLightingService` / `OpenAIKeychain` 不 import FoundationModels（與 `FoundationModelsLightingService.swift` 的 `#if canImport` 對稱）；用 `URLSession` / `Security`。如此三檔都能進 smoke 編譯集，比照 `LoopbackSyncTransport` / `UnavailableLightingLookService` 的可注入測試法。
3. **不改 AppModel 的生成/gate 邏輯**。`AppModel.generate`（`AppModel.swift:502`）已 `refreshModelAvailability()` → 對 `modelAvailability.isAvailable` 把關（`:520-524`）→ `catch { fail(error.localizedDescription) }`（`:549-550`）走繁中面板。後端只要正確實作 `availability` 與丟出 `LightingGenerationError`，這套原封不動運作。
4. **🔴 OpenAI 錯誤一律走 `.generationFailed(...)`（訊息原樣顯示），絕不用 `.modelUnavailable(...)`。** 因為 `LightingGenerationError.modelUnavailable` 的 `errorDescription` **寫死前綴**「`Apple Intelligence 無法使用：`」（`LightingAIService.swift:65`）——對 OpenAI 後端用它會顯示成「Apple Intelligence 無法使用：OpenAI 金鑰無效」這種自相矛盾的字。**唯一**用 `.unavailable(reason:)`（無前綴）的地方是 `availability` 屬性本身（金鑰未設定時），它由 gate 經 `unavailableReason` 直接顯示，沒有前綴問題。

## Ground truth（呼叫/沿用，勿重寫；附 `file:符號`）

### seam 與型別
- **協定**：`LightingLookGenerating`（`LightingAIService.swift:11`）= `var availability: LightingModelAvailability { get }` + `func generateLook(from:) async throws -> LightingGenerationResult`。`AppModel.aiClient: any LightingLookGenerating` 已可注入（`init(aiClient:)` `AppModel.swift:139`）。
- **可用性**：`LightingModelAvailability`（`.available` / `.unavailable(reason:)`，`:21`），`isAvailable` / `unavailableReason` 已備好給 gate（`AppModel.swift:520`）與 `generationStatus`（`AppModel.swift:211`）。
- **錯誤**：`LightingGenerationError`（`.modelUnavailable` / `.emptyPrompt` / `.generationFailed`，`:57`）。注意 `.modelUnavailable` 有 Apple Intelligence 前綴（見原則 4）。
- **結果 + source**：`LightingGenerationResult{look, source}`（`:52`）、`LightingGenerationSource: String`（`:41`）。對 source 的**唯一** exhaustive switch 是它自己的 `displayName`（`:44-49`）——加 case 只需補這一處。`AppModel.generationSource` 預設 `.foundationModels`（`AppModel.swift:119`），在 `generate` 成功後設為 `result.source`（`:544`）；`generationStatus` 在 `.available` 時顯示 `generationSource.displayName`（`:214`）。
- **draft 組裝器（共用，勿重寫）**：`static LightingLookDraft.makeValidatedLook(lookName:mood:cues:explanationTerm:…)`（`LightingAIService.swift:157`）——**這就是 FM 路徑 `GeneratedLightingLook.makeValidatedLook()`（`FoundationModelsLightingService.swift:290`）所走的多 cue 組裝器**：pin `schemaVersion "1.0"` / `.standardNight` ambient / `.mvpDefault` 過場、`selectedCueId = cues.first.id`、跑 `validate()`。OpenAI 後端把 DTO 映成同樣的 `[LightingLookDraft.Cue]` 後呼叫它，零重複。
- **hex 自癒**：`FixtureColor.normalizedHex(_)`（`LightingModels.swift:94`）——吞掉模型噪音（`#FFD1A3,`、色名、prose），只接受 6 位 `#RRGGBB` 否則 `nil`。draft 沿用「壞色 → `#FFFFFF`」（`FoundationModelsLightingService.swift:340`）。
- **enabled 權威化**：`fixtureGroup(from:)`（`LightingAIService.swift:212`）已把 `enabled:false` → `intensity:0`。沿用、勿在 OpenAI 端重做。

### `validate()` 真相（**CLAUDE.md 的「exactly two cues / 4–12 fixtures」已過時，以程式碼為準**）
- `validate()`（`LightingModels.swift:785`）**已不再硬綁** `cue_opening` / `cue_highlight`——程式碼註解（`:795`）明說舊的硬綁已移除，現在只要 `!cues.isEmpty`（`:799`）且 `cues.contains{ $0.id == selectedCueId }`（`:803`）。所以 OpenAI 後端比照 FM 指派 `cue_0/cue_1/…` 即合法。
- 每盞 fixture：`intensity ∈ 0.0...1.0`、`color.mode == .rgb`、`normalizedHex(color.value) != nil`（`validate(_ fixture:)` `:814`）。

### FM 實際 schema（OpenAI 要鏡像的「真值」）
`@Generable GeneratedLightingLook`（`FoundationModelsLightingService.swift:179`）的實際 `@Guide` 約束：
- `cues: [GeneratedCue]` `.count(2...4)`（每個只有 `name`）。
- `fixtures: [GeneratedFixture]` `.count(4...8)`。
- `GeneratedFixture`：`name`、`type`（enum 10 種）、`zone`（enum 5 種）、`states: [GeneratedFixtureState]` `.count(2...4)`（**每 cue 一個，依 cue 順序對齊**）。
- `GeneratedFixtureState`：`enabled: Bool`、`intensity: Double .range(0...1)`、`colorHex: String`（6 位 hex）、`beamAngleDegrees: Double .range(5...120)`、`gobo`（enum 5 種）。
- `explanation`：`term` / `plainText` / `actionSummary`（皆 String）。

### 下游組裝規則（**逐字比照** `FoundationModelsLightingService.swift:290-345`）
- `cueCount = max(cues.count, 1)`；對每個 `cueIndex` 建 `LightingLookDraft.Cue(id: "cue_\(cueIndex)", name: <model name 去空白後；空則 "Cue \(i+1)">, fixtures: …)`。
- 每盞 fixture 取 `states[min(max(cueIndex,0), states.count-1)]`（**states 比 cue 短就重用最後一筆**；空 states → enabled:false/intensity:0/`#000000` 的保底）。fixture `id = "fixture_\(index)"`（rig identity 跨 cue 穩定）。
- `Fixture.role = visualModel.derivedRole`（`LightingModels.swift:1287`）、`model = visualModel`、`beamAngleDegrees = state.beamAngleDegrees`、`colorHex = normalizedHex(state.colorHex) ?? "#FFFFFF"`。

### 列舉映射表（FM 端 `:348-388`；OpenAI 端在自己檔內**重寫**，映到相同的 Foundation-only domain 型別）
domain 型別位置：`FixtureRole`/`StageZone`/`GoboPattern`（`LightingModels.swift:14/35/47`）、`LightingFixtureVisualModel`（`LightingFixtureCatalog.swift:8`）——皆 Foundation-only、皆已在 smoke 集，可直接用。

- **type → `LightingFixtureVisualModel`（10 種，名稱 1:1）**：`frontFresnel/ledFresnel/spotBarrel/washBar/backgroundBatten/movingHeadBeam/ledStrobeBar/ledPar/audienceBlinder/laser` → 同名 case。role 由 `.derivedRole` 推導，不另傳。
- **zone → `StageZone`（5 種）**：`frontOfHouse→.stageFront`、`upstageTruss→.stageBack`、`sideStageLeft→.stageLeft`、`sideStageRight→.stageRight`、`floor→.fullStage`。
- **gobo → `GoboPattern?`（5 種）**：`none→nil`、`breakup→.breakup`、`stripes→.stripes`、`stars→.stars`、`grid→.grid`。

### 安全/網路（已查證 2026-06）
- 金鑰存 Keychain：`kSecClass=kSecClassGenericPassword`、`kSecAttrAccessible=kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（最緊合理等級：僅解鎖後可讀、不進備份、不跨裝置）。**絕不**寫死進 binary，**絕不**用 UserDefaults。
- ATS 預設即允許 `https://api.openai.com`（TLS1.2+、ECDHE PFS、SHA-256+），**不需** `NSAppTransportSecurity` 例外。
- visionOS **不需**任何 networking entitlement（`com.apple.security.network.client` 只屬 macOS App Sandbox，對 visionOS/iOS 不適用——對抗式驗證已更正此點）。

## OpenAI API 契約（已查證，2026-06）

- **端點**：`POST https://api.openai.com/v1/responses`（**Responses API**，非舊 Chat Completions）。Header：`Authorization: Bearer <key>`、`Content-Type: application/json`。
- **請求**（注意 Responses 把 `name`/`strict`/`schema` **平鋪**在 `text.format` 下；Chat Completions 才包在 `response_format.json_schema`——**別抄錯，會 400**）：
  ```jsonc
  {
    "model": "gpt-5.5",
    "instructions": "<英文系統指令，見 work item 3>",
    "input": "<使用者 prompt，可中英混>",
    "text": { "format": { "type": "json_schema", "name": "lighting_look", "strict": true, "schema": { /* 見 jsonSchemaDesign */ } } },
    "temperature": 0.9
  }
  ```
  `temperature 0.9` 比照 FM `.random(probabilityThreshold:0.9)` 讓輸出多樣。**不 streaming**（單一結構化物件，validate-then-apply 原子化，串流只增解析複雜度無 UX 好處）。
- **回應信封**：top-level `output` 是**陣列**。先檢查 `status == "completed"` 與 `incomplete_details`（如 `max_output_tokens` 截斷 → 視為失敗）。找 `type == "message"` 的項（**跳過 `reasoning` 項**，gpt-5.x 可能先吐 reasoning），其 `content` 陣列：
  - `type == "refusal"` → 取 `.refusal` 當拒絕原因，**直接走錯誤路徑，不要 JSON-decode**。
  - `type == "output_text"` → 其 `.text` 是**一個 JSON 字串**，要自己再 `JSONDecode` 一次成 DTO。
- **strict 模式保證 vs 不保證**：`enum` 一定 enforced（型別/zone/gobo 不可能吐列舉外的值——消滅一整類 parse 錯誤）；`additionalProperties:false` + 每物件所有 key 進 `required` 是硬性需求（否則 400）；root 不可 `anyOf`；optional 用 `["type","null"]` union。
  - **⚠️ 驗證矛盾（誠實記錄）**：兩條對抗式驗證 agent 對「`minItems/maxItems/minimum/maximum/pattern` 在 strict 模式是否 enforced」**結論相反**——一條引 OpenAI changelog（2025-05-20）說自 2025-05 起**已支援**（Azure 的「不支援」表過時）；另一條引 Azure 2026 矩陣說**仍不支援**。**結論一致且不受矛盾影響**：count / range / hex **一律以我方 `validate()` 為權威**（穩定度因 model/path 而異，且符合本專案「Foundation-only 驗證器單一真相、FM 與雲端共用」慣例）。可在 schema 寫上界**當輔助提示**，但**絕不**移除 post-parse 檢查。
- **模型**：`gpt-5.5`（使用者指定；當前旗艦、1M context）。model id 設成可注入/可設定的字串，預設 `"gpt-5.5"`。出 demo 前的 live 測試順手確認 `gpt-5.5` 在 Responses API 接受 `text.format` strict structured outputs（GPT-5.x 旗艦均支援，但本環境無法實測）。

來源：
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/docs/changelog （2025-05-20）
- https://community.openai.com/t/structured-outputs-gets-nifty-improvements/1266968
- https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client

## Work items

### 1. `LightingAIService.swift` — seam 擴充（最小改動，單一 agent 擁有此檔）
- `LightingGenerationSource` 加 `case openAI`；在 `displayName`（`:44`）補 `case .openAI: return "OpenAI（雲端）"`（**唯一**需改的 switch）。
- 新增可注入網路邊界（比照 `LightingLookGenerating` / `LumaSyncTransport` 的注入法，保持 Foundation-only、讓 smoke 能塞 stub）：
  ```swift
  typealias HTTPSend = @Sendable (URLRequest) async throws -> (Data, URLResponse)
  ```
  （或 `protocol HTTPClient { func send(_:) async throws -> (Data, URLResponse) }` + 預設 `URLSession` 實作；二選一，能注入即可。）
- **不在此檔放 OpenAI JSON 解析或 networking**——進 `OpenAILightingService.swift`。此檔只提供 enum case 與注入型別。

### 2. `OpenAIKeychain.swift`（新檔，Foundation-only）
- 極小 `Security` 包裝：`static func store(_ key: String)` / `static func load() -> String?` / `static func delete()`，service 字串 `"tw.iosclub.LumaStage.openai-key"`，`kSecClassGenericPassword` + `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`。
- 純 `Security.framework`（Foundation-only）。SecItem 在 headless 不可靠，故 smoke **不**直接測 Keychain——`OpenAILightingService` 的 key 來源用注入的 `apiKeyProvider: () -> String?`（預設 `OpenAIKeychain.load`），測試塞固定字串。**禁 import FoundationModels。**

### 3. `OpenAILightingService.swift`（新檔，Foundation-only，禁 FoundationModels import）
- `struct OpenAILightingService: LightingLookGenerating`，持有 `httpSend: HTTPSend`（預設包 `URLSession.shared.data(for:)`）、`apiKeyProvider: () -> String?`（預設 `OpenAIKeychain.load`）、`model: String = "gpt-5.5"`。
- `var availability`：`apiKeyProvider()` 為 nil/空 → `.unavailable(reason: "尚未設定 OpenAI API 金鑰。請在設定中輸入。")`；否則 `.available`。**不**做網路 reachability 探測（同步屬性不可阻塞；連不上在 `generateLook` 丟 `.generationFailed`）。
- `generateLook(from:)`：
  1. trim、空字串 → `.emptyPrompt`（比照 FM）。
  2. `apiKeyProvider()` 缺 → `.generationFailed("尚未設定 OpenAI API 金鑰。請在設定中輸入。")`（**不用 `.modelUnavailable`**，見原則 4；正常情況 gate 已先擋）。
  3. 組 Responses 請求（hand-author 或程式化產 schema，見 jsonSchemaDesign），`httpSend`。
  4. 非 2xx → 映 HTTP status → 繁中 `.generationFailed`（見 errorMapping）。
  5. 解信封：跳過 `reasoning`、找 `message`；`refusal` → `.generationFailed("模型拒絕生成燈光效果。請嘗試換個說法。")`；`output_text` → 取 `.text` 字串。
  6. `JSONDecode` 該字串成本檔內的 **Foundation-only DTO**（鏡像 `GeneratedLightingLook` 結構，但**無 `@Generable`**、定義在本檔）。
  7. 把 DTO 依「下游組裝規則」（見 Ground truth）映成 `[LightingLookDraft.Cue]`（`cue_<i>` / `fixture_<i>`、states 重用最後一筆、`derivedRole`、列舉映射表、`normalizedHex` 自癒），呼叫 `LightingLookDraft.makeValidatedLook(...)`（**同一驗證器**）。
  8. 回 `LightingGenerationResult(look: look, source: .openAI)`。
  9. catch 順序：`catch let e as LightingGenerationError { throw e }` → `catch let e as ValidationError { throw .generationFailed(e.errorDescription ?? "生成的燈光效果無效。") }` → `catch is DecodingError { throw .generationFailed("無法解讀模型回應。請再試一次。") }` → `catch let e as URLError { … 映繁中 }`。
- **系統指令用英文**（比照 FM `instructions` `FoundationModelsLightingService.swift:94`，描述同一個 SHOW：2–4 cues、4–8 fixtures、每 fixture 一 state/cue 依序、hex 6 位、beam 5–120、gobo 選用；OpenAI context 大，可比 FM 版略長）。使用者 prompt 可中英混。

### 4. `FallbackLightingService.swift`（新檔，Foundation-only）— OpenAI 優先 + FM 備援的組合器
- `struct FallbackLightingService: LightingLookGenerating { let primary: any LightingLookGenerating; let secondary: any LightingLookGenerating }`。
- `var availability`：`primary.availability.isAvailable || secondary.availability.isAvailable` → `.available`；兩者皆不可用 → `.unavailable(reason:)`，reason 串接（如「尚未設定 OpenAI 金鑰；裝置端 Apple Intelligence 亦無法使用。」優先給 secondary 的 reason 當主因）。
- `generateLook(from:)`：
  - `primary.availability.isAvailable` 為真 → 先 `try primary.generateLook(...)`；**丟錯則退回** `secondary`（若 `secondary.availability.isAvailable`）。兩者皆失敗 → rethrow **primary 的錯誤**（使用者設的是 OpenAI，給他 OpenAI 的失敗訊息較可行動）。
  - `primary` 不可用 → 直接走 `secondary`（若可用）；否則丟 primary 的 `.generationFailed/…`。
  - `result.source` 自然反映**實際生成者**（OpenAI 成功 → `.openAI`；退回 → `.foundationModels`），所以 `generationStatus` / iPad panel 顯示正確、無須額外處理。
- **退回觸發策略（預設＝任何錯誤都退）**：為 demo 韌性，primary 丟任何 `LightingGenerationError` 都試 secondary。實作者若不希望「內容拒絕/驗證失敗也靜默換引擎」，可改成只在 transport/availability 類（`URLError`、401/403/429/5xx、金鑰缺）退回——在本檔以一個 `shouldFallback(on:)` 判斷集中，附註說明。`.emptyPrompt` 不必退（兩者都會拒）。
- Foundation-only → **可進 smoke**：注入兩個 stub（primary 丟錯、secondary 回固定 look）斷言退回行為。

### 5. `AppModel.swift` — 只動注入（不碰 generate/gate/fail/cue 編輯/views）
- 改 `makeDefaultLightingClient()`（`:145`）：
  ```swift
  private static func makeDefaultLightingClient() -> any LightingLookGenerating {
      let openAI = OpenAILightingService()
  #if canImport(FoundationModels)
      return FallbackLightingService(primary: openAI, secondary: FoundationModelsLightingService())
  #else
      return FallbackLightingService(primary: openAI, secondary: UnavailableLightingLookService())
  #endif
  }
  ```
- （可選、cosmetic）把 `generationSource` 預設改 `.openAI`，或在 `init` 後依預設後端設定，讓尚未生成時的 `generationStatus` 顯示「OpenAI（雲端）」而非殘留的 FM。生成後 `result.source`（`:544`）自會校正。
- **`generate(...)` / gate / `fail(...)` / `generationStatus` / cue 編輯一律不改。**

### 6. 設定 UI（新極小檔）— API key 輸入
- `SecureField` 寫入 `OpenAIKeychain.store`、清除鈕 `delete`、（可選）「強制裝置端（隱私模式）」`Toggle`（開啟時改注入「primary=FM、secondary=Unavailable」或單 FM，供 demo 切換隱私敘事）。
- 繁中標籤、`LumaStageDesign` token（`lumaFloatingPanel`/`lumaGazeTarget`）、≥60pt 注視目標、`accessibilityLabel`。明示「金鑰只存本機 Keychain；demo 直連，正式版應走自家 proxy」。

### 7. `project.pbxproj` — 隱私敘述（最小）
- **不加** ATS 例外、**不加** networking entitlement（已查證）。若工具/審查要求說明資料蒐集（prompt 送第三方 LLM），於隱私清單/Nutrition Label 標示，並可加一條繁中說明字串（沿用 `INFOPLIST_KEY_NS…` 樣式）。

### 8. smoke test + 文件
- `Tests/LumaStageCoreSmokeTests.swift` 加並在 `main()` 註冊（無自動發現）：
  1. `openAIServiceDecodesAndValidates()`：注入回固定「合法 Responses 信封（`output_text` 內含合法 lighting JSON）」的 `HTTPSend` stub + 固定 key provider → `try result.look.validate()` 通過、`result.source == .openAI`。
  2. `openAIServiceSurfacesRefusal()`：stub 回 `type:"refusal"` 內容項 → 斷言丟 `.generationFailed`（且**未**嘗試 decode refusal）。
  3. `openAIServiceRejectsOutOfRangeViaValidator()`：stub 回 `intensity > 1.0` 或壞色或超量 fixtures 的 JSON → 斷言被 `validate()` 擋下（丟 `.generationFailed` 包 `ValidationError`），證明 schema **不**被信任於 count/range/hex。
  4. `fallbackServiceFallsBackWhenPrimaryThrows()`：primary stub 丟錯、secondary stub 回固定 look → 斷言回傳 secondary 的 `source`；primary 成功時不呼叫 secondary。
- 把 `OpenAILightingService.swift`、`FallbackLightingService.swift`（及測到的 `OpenAIKeychain.swift`，若有）加進 `docs/specs/README.md` 與根 `CLAUDE.md` 的 swiftc smoke 指令。保持印出 `LumaStageCoreSmokeTests passed`。

## jsonSchemaDesign（strict `json_schema` 鏡像 `GeneratedLightingLook`）

程式化產生（避免漏掉 `additionalProperties:false` / `required`）。鏡像 FM 實際結構：

- **root**：`lookName`(str)、`mood`(str)、`cues`(array of `{name:str}`)、`fixtures`(array of fixture)、`explanation`(`{term,plainText,actionSummary}` 皆 str)。每物件 `additionalProperties:false` + 所有 key 進 `required`。
- **fixture**：`name`(str)、`type`(**enum 10 種** 鏡像 type 映射表)、`zone`(**enum 5 種** 鏡像 zone)、`states`(array of state)。
- **state**：`enabled`(bool)、`intensity`(number)、`colorHex`(str)、`beamAngleDegrees`(number)、`gobo`(**enum 5 種**：`none/breakup/stripes/stars/grid`)。

**schema 能 enforce（放心交給它）**：物件結構、欄位存在性、`type`/`zone`/`gobo` 的 **enum 成員**。

**schema 不可靠 / 由 `validate()` 把關（權威）**：
- `cues` 2–4、`fixtures` 4–8（`minItems`/`maxItems`）→ 下游 `makeValidatedLook` 的「非空 + selectedCueId resolve」+ states 重用容錯守住（生成數量略偏仍能組裝）。
- `intensity` 0…1（`minimum`/`maximum`）→ `validate(_ fixture:)`（`:814`）的 `(0.0...1.0).contains` 擋下。
- `colorHex` `#RRGGBB`（`pattern`）→ `normalizedHex` 自癒 + `validate` 的 `normalizedHex != nil` 擋下。
- 「每 fixture 一 state/cue」**不靠 array 長度約束**：照下游規則「states 比 cue 短就重用最後一筆」。

> 可在 schema 寫上界當輔助，但**絕不**移除 post-parse 檢查（理由見「OpenAI API 契約」的驗證矛盾段）。

## errorMapping（全部收斂成 `.generationFailed`，由 AppModel `catch` 原樣顯示繁中）

| 來源 | 映成 |
|---|---|
| HTTP 401 / 403 | `.generationFailed("OpenAI API 金鑰無效或未授權。")` |
| HTTP 429 | `.generationFailed("OpenAI 請求過於頻繁，請稍候再試。")` |
| HTTP 5xx | `.generationFailed("OpenAI 服務暫時無法使用，請稍後再試。")` |
| `URLError`（離線） | `.generationFailed("無法連線到 OpenAI（請檢查網路）。")` |
| `URLError`（逾時） | `.generationFailed("請求逾時，請再試一次。")` |
| `refusal` 內容項 | `.generationFailed("模型拒絕生成燈光效果。請嘗試換個說法。")` |
| `DecodingError` / 空 output / `incomplete` 截斷 | `.generationFailed("無法解讀模型回應。請再試一次。")` |
| `ValidationError`（共用驗證器丟出） | `.generationFailed(validationError.errorDescription ?? "生成的燈光效果無效。")` |
| 金鑰未設定（availability 層） | `availability = .unavailable(reason: "尚未設定 OpenAI API 金鑰。請在設定中輸入。")`（**無**前綴，由 gate 顯示） |

> **不要**對任何 OpenAI 失敗用 `.modelUnavailable`（會冠「Apple Intelligence 無法使用：」前綴）。

## Constraints

- `OpenAILightingService.swift` / `FallbackLightingService.swift` / `OpenAIKeychain.swift` **禁止 import FoundationModels**（保證進 smoke 編譯集）。
- **不重寫驗證**：count/range/hex/schema 一律走既有 `validate()` / `makeValidatedLook()`。
- 不改 `AppModel.generate` 控制流，不改 `LightingLook`/`LightingCue`/`FixtureGroup`/`ValidationError`，不改 views（除新設定 UI）。
- 金鑰：Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`；**不**寫死、**不**入 UserDefaults。
- 使用者字串繁中；OpenAI 系統指令 + JSON Schema 的 enum 值維持英文（模型環境 + 鏡像 FM 詞彙）。
- OpenAI 錯誤一律 `.generationFailed`（原則 4）。

## Verification

- **smoke**：把三個新 Foundation-only 檔加進編譯集後仍 `LumaStageCoreSmokeTests passed`（含上述 4 測）。
  ```
  swiftc Tests/LumaStageCoreSmokeTests.swift \
    LumaStage/LightingModels.swift LumaStage/LightingAIService.swift LumaStage/StageBuilderModels.swift \
    LumaStage/LightingFixtureCatalog.swift LumaStage/LumaSyncProtocol.swift LumaStage/LumaSyncTransport.swift \
    LumaStage/LumaStageDesign.swift LumaStage/StageVoiceCommand.swift LumaStage/LightingPatchSheet.swift \
    LumaStage/LightEffect.swift LumaStage/StageLightAccessibility.swift LumaStage/LightControlCardPlacement.swift \
    LumaStage/OpenAILightingService.swift LumaStage/FallbackLightingService.swift \
    -o /tmp/smoke && /tmp/smoke
  ```
- **完整 build**：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme LumaStage -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/lumastage-dd build` → `** BUILD SUCCEEDED **`。
- 注入 stub 的測試**不需**真 API key 或網路。

## Caveats

- **無法在此環境實測 live endpoint**（無 key/網路）。`output`/`content`/`output_text`/`refusal` 欄位穩定但 API 會演進——**出 demo 前對 live endpoint 跑一次真實請求**校正信封解析；smoke 只覆蓋 decode/validate 邊界（stub）。
- 模型固定 `gpt-5.5`（使用者指定）；仍把 model id 設成可設定字串，方便日後切換。
- 直連 key（無 backend proxy）是 demo 取捨；正式上架前應改走自家 proxy（金鑰不入 binary）。設定 UI 與本 spec 誠實標示。
- 加入雲端路徑會稀釋「完全裝置端/離線/隱私」敘事——`FallbackLightingService` + 「強制裝置端」開關把 FM 保留為備援底線，敘事上守住隱私故事（MAIC §社會價值）。
- **未動的既有過時敘述**：根 `CLAUDE.md` 仍寫「4–12 fixtures / exactly two cues」，與實際 `@Guide`（4–8 / 2–4）不符——本 spec 以程式碼為準；可另開小修同步 doc（不在本 spec 範圍）。
