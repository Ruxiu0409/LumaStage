# iPad 3D Stage Builder Feature Spec

## 1. Feature Summary

`iPad Stage Builder` 是 LumaStage 的下一階段功能，讓學生使用者可以在 iPad 上用 3D 積木式互動快速搭建戶外活動常見舞台。使用者可以放置不同大小的舞台平台、1m / 2m truss segment，並組成常見的 ㄇ字型 truss 結構，再透過旋轉視角、平移畫面與縮放檢查不同角度的舞台狀態。

這個功能的重點是「快速建立可信的舞台空間」，作為後續燈光設計、AI cue generation、Vision Pro 預覽的場景基礎。它不是工程繪圖工具，也不提供結構安全、吊掛承重或法規驗算。

## 2. Product Goal

讓沒有專業 CAD / stage plot 經驗的學生，在 3D 環境中用像搭積木一樣的方式完成一個戶外學生舞台配置。

最低可用體驗：

```text
建立專案
-> 進入 iPad Stage Builder
-> 選擇舞台平台尺寸
-> 放置 1m / 2m truss
-> 透過 snap 組出 ㄇ字型 truss
-> 旋轉 / 平移 / 縮放檢查舞台
-> 儲存為 project stage layout
-> 後續燈光 cue 在這個舞台配置上預覽
```

## 3. Target Users

- 學生活動主辦人：需要先規劃戶外活動舞台的大致大小與視覺配置。
- 初學舞台技術學生：需要理解平台、truss、燈光位置之間的空間關係。
- LumaStage demo 使用者：需要快速建立一個場景，讓 AI 燈光設計不再只套用固定舞台。

## 4. Scope

### 4.1 In Scope

- iPad 上的 3D stage-building mode。
- 3D viewport 支援 orbit、pan、zoom。
- 可放置舞台平台 modules。
- 可放置 1m 與 2m truss segment。
- 支援水平與垂直 truss segment。
- 支援 snap-to-grid 與 snap-to-connector。
- 支援常見 ㄇ字型 truss preset。
- 支援手動組裝 ㄇ字型 truss。
- 支援選取、移動、旋轉、複製、刪除物件。
- 支援 undo / redo。
- 支援儲存 stage layout 到 project state。
- stage layout 可供 Vision Pro / RealityKit renderer 顯示。

### 4.2 Out Of Scope

- 不做承重計算。
- 不做吊掛點安全驗算。
- 不做法規或結構工程判斷。
- 不做真實 truss 品牌規格庫。
- 不做 DMX patch、燈具地址或 console export。
- 不做多人同步編輯。
- 不做完整 CAD 尺寸標註工具。
- 不做 AR 掃描現場尺寸。

## 5. Core Objects

### 5.1 Stage Platform

舞台平台是使用者建立舞台地面的主要單位。MVP 建議提供 modules 與 presets 兩層選擇。

Modules:

| ID | 顯示名稱 | 尺寸 | 用途 |
| --- | --- | --- | --- |
| `stage_deck_1x1` | 1m x 1m Deck | 1m x 1m | 小型補位、延伸區。 |
| `stage_deck_2x1` | 2m x 1m Deck | 2m x 1m | 常見平台拼接單位。 |
| `stage_deck_2x2` | 2m x 2m Deck | 2m x 2m | 快速建立主舞台面。 |

Presets:

| ID | 顯示名稱 | 尺寸 | 組成 |
| --- | --- | --- | --- |
| `stage_preset_4x2` | Small Student Stage | 4m x 2m | 2 個 2m x 2m deck。 |
| `stage_preset_6x3` | Medium Outdoor Stage | 6m x 3m | 依 2m / 1m modules 拼接。 |
| `stage_preset_8x4` | Large Club Stage | 8m x 4m | 8 個 2m x 2m deck。 |

平台高度先提供三個視覺 preset：

- `low`: 0.4m
- `standard`: 0.8m
- `high`: 1.0m

高度只影響視覺預覽與燈光相對位置，不代表工程安全建議。

### 5.2 Truss Segment

Truss segment 是固定長度的積木單位。

| ID | 顯示名稱 | 長度 | 用途 |
| --- | --- | --- | --- |
| `truss_1m` | 1m Truss | 1m | 補足高度或寬度。 |
| `truss_2m` | 2m Truss | 2m | 主要 ㄇ字型結構單位。 |

視覺設定：

- 預設 truss 外框寬度使用 0.29m。
- 連接點在 segment 兩端。
- segment 可水平或垂直放置。
- segment 可以沿 X / Y / Z 軸以 90 度為單位旋轉。

### 5.3 Truss Portal Preset

ㄇ字型 truss 是學生戶外舞台最常見的起始配置，應該作為一鍵 preset。

Presets:

| ID | 顯示名稱 | 寬度 | 高度 | 組成 |
| --- | --- | --- | --- | --- |
| `portal_4x3` | 4m x 3m Portal | 4m | 3m | 左右各 3m 垂直柱，上方 4m 橫樑。 |
| `portal_6x3` | 6m x 3m Portal | 6m | 3m | 左右各 3m 垂直柱，上方 6m 橫樑。 |
| `portal_8x4` | 8m x 4m Portal | 8m | 4m | 左右各 4m 垂直柱，上方 8m 橫樑。 |

Preset 產生後仍然是一般 truss segment 組合，使用者可以拆開、移動或刪除個別 segment。

## 6. Interaction Model

### 6.1 Screen Layout

iPad Stage Builder 使用單一工作畫面，不做 landing page。

主要區域：

- 左側 asset library：Stage、Truss、Presets 三個 tabs。
- 中央 3D viewport：顯示舞台、truss、grid、選取狀態。
- 右側 inspector：顯示目前選取物件的尺寸、位置、旋轉、高度。
- 下方 action bar：undo、redo、duplicate、delete、snap toggle、camera presets。

### 6.2 3D Navigation

手勢：

| 手勢 | 行為 |
| --- | --- |
| 單指拖曳空白處 | Orbit camera。 |
| 雙指拖曳 | Pan camera。 |
| 雙指 pinch | Zoom camera。 |
| 點選物件 | Select object。 |
| 拖曳選取物件 | Move object on current plane。 |
| 長按物件 | 開啟 context menu。 |

Camera presets:

- Front
- Top
- Left
- Right
- Isometric

### 6.3 Placement

使用者從 asset library 點選物件後，系統進入 placement mode。

Placement rules:

- 新物件跟隨指標在 grid 上預覽。
- 預覽物件使用半透明材質。
- 可放置位置顯示正常顏色。
- 不可放置位置顯示紅色 outline。
- 點一下確認放置。
- 兩指旋轉或 inspector rotate button 可改變方向。

### 6.4 Snapping

MVP 需要兩種 snapping：

Grid snapping:

- 預設 grid size 為 0.5m。
- 舞台平台以 0.5m 對齊。
- truss segment 端點以 0.5m 對齊。

Connector snapping:

- truss segment 端點接近另一個 truss 端點時自動吸附。
- 吸附距離 threshold 為 0.15m。
- 成功吸附時顯示 connector highlight。
- connector snapping 優先於 grid snapping。

### 6.5 Selection And Transform

選取物件後顯示 transform gizmo。MVP 不需要專業 3D editor 的完整 gizmo，但至少要支援：

- Move X / Z on ground plane。
- Move Y for vertical height adjustment。
- Rotate 90 degrees around X / Y / Z。
- Duplicate selected object。
- Delete selected object。

Inspector 顯示：

- Object name
- Position X / Y / Z in meters
- Rotation X / Y / Z in degrees
- Length or size
- Lock toggle

## 7. Data Model

Stage Builder 不應直接寫進 lighting cue schema。它應該是 project-level stage layout，lighting look 只引用它。

```json
{
  "schemaVersion": "1.0",
  "stageLayoutId": "layout_student_outdoor_001",
  "name": "Student Outdoor Stage",
  "units": "meters",
  "gridSize": 0.5,
  "objects": [
    {
      "id": "deck_001",
      "type": "stageDeck",
      "assetId": "stage_deck_2x2",
      "displayName": "2m x 2m Deck",
      "position": { "x": 0, "y": 0.4, "z": 0 },
      "rotation": { "x": 0, "y": 0, "z": 0 },
      "size": { "width": 2, "depth": 2, "height": 0.8 },
      "locked": false
    },
    {
      "id": "truss_001",
      "type": "trussSegment",
      "assetId": "truss_2m",
      "displayName": "2m Truss",
      "position": { "x": -2, "y": 1.5, "z": -1 },
      "rotation": { "x": 0, "y": 0, "z": 90 },
      "length": 2,
      "connectorIds": ["truss_001_a", "truss_001_b"],
      "locked": false
    }
  ],
  "metadata": {
    "createdFromPreset": "portal_4x3",
    "updatedAt": "2026-05-31T00:00:00Z"
  }
}
```

### 7.1 Required Types

`StageLayout`:

- `schemaVersion`
- `stageLayoutId`
- `name`
- `units`
- `gridSize`
- `objects`
- `metadata`

`StageObject`:

- `id`
- `type`
- `assetId`
- `displayName`
- `position`
- `rotation`
- `locked`

`StageObjectType`:

- `stageDeck`
- `trussSegment`

`Vector3Meters`:

- `x`
- `y`
- `z`

## 8. Integration With LumaStage

### 8.1 Project Model

每個 LumaStage project 應該可以有一個 active stage layout。

Project state 建議新增：

```text
Project
- id
- name
- stageLayout
- lightingLook
- selectedCueId
```

如果 project 沒有 `stageLayout`，系統使用目前固定的 default outdoor stage。

### 8.2 Vision Pro Preview

Vision Pro renderer 讀取 project 的 `stageLayout` 後，生成對應的 stage decks 與 truss segments。

Renderer priority:

1. 如果有 saved `stageLayout`，顯示使用者搭建的舞台。
2. 如果沒有 `stageLayout`，顯示 default outdoor stage。
3. Lighting cue schema 繼續只控制燈光狀態，不負責建立 stage geometry。

### 8.3 AI Lighting Generation

AI lighting prompt 可以讀取 stage layout 的摘要，但不需要知道所有 mesh 細節。

傳給 AI 的 stage summary 範例：

```json
{
  "stageSize": { "width": 6, "depth": 3, "height": 0.8 },
  "trussPortals": [
    { "width": 6, "height": 3, "position": "upstage" }
  ],
  "availableLightingPositions": ["frontTruss", "topTruss", "stageLeft", "stageRight"]
}
```

AI 只使用這些摘要來生成更合理的 lighting look，例如把 background wash 放在 upstage truss，而不是直接修改 truss geometry。

## 9. Validation Rules

MVP 只做視覺與資料一致性驗證。

Required validations:

- Stage deck 不可低於地面。
- Truss segment 不可低於地面。
- Object ID 必須唯一。
- `assetId` 必須存在於 asset library。
- `position` 必須是有限數字。
- `rotation` 必須是 90 度倍數。
- Truss connector 若宣告連接，兩端距離必須小於 0.15m。

Warnings:

- Truss 沒有連接到任何其他 truss。
- ㄇ字型 truss 左右高度不一致。
- Truss portal 寬度小於 stage width。
- Stage deck 之間有明顯縫隙。

Warnings 不阻止儲存，只在 inspector 或 validation panel 顯示。

## 10. Visual Design Direction

整體視覺要像專業但容易上手的 3D 搭建工具，不要做成玩具風格。

Guidelines:

- 舞台平台使用深灰色防滑材質。
- truss 使用鋁合金銀色材質。
- grid 使用低對比細線。
- selected object 使用 LumaStage accent outline。
- connector highlight 使用小型發光點。
- invalid placement 使用紅色 outline，不要整個物件變成刺眼紅色。
- UI 控制保持安靜、密集、可掃描，符合 iPad productivity app。

## 11. Acceptance Criteria

### 11.1 Basic Stage Assembly

- 使用者可以建立 4m x 2m 舞台平台。
- 使用者可以加入 4m x 3m ㄇ字型 truss preset。
- 使用者可以旋轉視角查看 front、top、isometric view。
- 使用者可以儲存 layout。
- 重新開啟 project 後 layout 仍然存在。

### 11.2 Manual Truss Assembly

- 使用者可以放置 1m truss。
- 使用者可以放置 2m truss。
- 使用者可以把 truss 旋轉成垂直或水平。
- truss 端點接近時會自動吸附。
- 使用者可以手動組成 ㄇ字型 truss。

### 11.3 Editing

- 使用者可以選取任一 stage deck 或 truss segment。
- 使用者可以移動、旋轉、複製、刪除選取物件。
- undo / redo 可以復原 placement、move、rotate、delete。
- locked object 不可被拖曳或刪除。

### 11.4 Renderer Integration

- iPad 儲存的 stage layout 可以在 Vision Pro / RealityKit preview 顯示。
- lighting cue 切換仍然正常運作。
- 如果 stage layout 不存在，系統會 fallback 到 default outdoor stage。

## 12. Future Extensions

- 匯入場地平面圖或 stage plot。
- 以 Apple Pencil 標註尺寸。
- AR 掃描實際現場，建立 rough floor plan。
- 燈具掛載到 truss connector。
- 以 AI 根據活動類型自動建議 stage + truss layout。
- 多層 truss、side wing、FOH tower。
- 安全與承重資料作為教育提示，但仍不取代專業工程判斷。

## 13. Open Questions

- 舞台平台是否需要支援不規則拼接，或第一版只支援矩形舞台？
- truss ㄇ字型是否只需要 upstage 一組，還是要支援 front truss / back truss 兩組？
- 3D 搭建功能是否要先只在 iPad 做，Vision Pro 只負責讀取結果？
- 學生使用者是否會需要輸出一張簡單 stage plot 圖給活動企劃使用？
