> Status: resolved — 維持幾何方案，不做粒子（#3 已關閉 2026-07-08）

# 取捨說明：Laser 光束改用粒子效果（issue #3）

這不是一份可直接分派的實作 SPEC，而是一份**決策備忘**。issue #3 要求把雷射空中光束改用粒子效果呈現，但這與程式碼中一項**刻意做出的既定決策**衝突，因此依 `AGENTS.md`「先問人」規則：先寫取捨、等使用者核可，**不實作**。

## 衝突點

`CLAUDE.md`（「Live light control / Shared stage geometry」）明確記載：雷射的逐束 additive `ParticleEmitterComponent` 霧氣**做過一次並被刻意移除**，原因：

1. **RealityKit 粒子不受場景光照**（unlit），與 rig 的打光不一致。
2. 在**真實 1:1 尺度**下，粒子呈現為偏離光軸的怪異斑點（off-axis speckle），不像空氣中的光。

目前雷射空中光束是**幾何方案**：白熱 `UnlitMaterial` 核心（core）+ 低 alpha 光暈外鞘（sheath）兩層同軸圓柱，數值由 Foundation-only、有 smoke test 的 `LaserScatterMath` / `LaserScatterConfig` 決定。這是那次移除後**刻意選定的替代方案**。

因此，直接實作 #3（把光束改回粒子）等於**回退一個已決定的設計**。

## 若仍要做，必須先回答（issue #3 自己也列出）

- 粒子顏色直接綁 cue hex（unlit 本來就是 laser 要的，不需場景光照——但要與 `LaserScatterMath` 的核心/外鞘色一致）。
- 發射器沿光束軸線分布（沿圓柱長度的 emitter shape 或多發射點），粒子尺寸/密度在 1:1 尺度重新調參，**證明能消除當初的 off-axis speckle**。
- 效能：多道光束 × 多顆 laser 的粒子開銷（Vision Pro 實機）。

## 與 #2 的方向一致性

issue #2（煙幕）的建議方向（見 SPEC 19）是把雷射的 **core+sheath 幾何**推廣到一般聚光燈光錐——即「幾何體積光」是專案選定的空中光路呈現路線。若雷射改回粒子，會與這個方向**分歧**（雷射走粒子、聚光燈走幾何），維護與視覺一致性都變差。

## 建議（待使用者裁決）

**建議：維持雷射現有的 core+sheath 幾何方案，不回退粒子**，除非在實機上明確指出幾何方案的具體視覺缺口（例如「顆粒感不足」）。理由：既有方案已解決當初粒子的兩個失敗點、且與 #2/SPEC 19 的幾何路線一致。

**若使用者仍要粒子**，建議的安全作法（而非取代）：
- 把粒子當**疊加層**（在既有 core+sheath 之上，flag 控制），而非移除幾何層——保留已驗證的空中光路，粒子只加顆粒感。
- 粒子外觀的可判定部分（顏色綁 cue hex、沿軸分布、密度/尺寸）進 Foundation-only（延伸 `LaserScatterMath`）+ smoke test，view 薄消費。
- 換色、亮度、`beamsVisible` 開關（beat gating）都要作用到粒子層。
- **必須實機驗證**：1:1 尺度下無 off-axis speckle、無明顯效能下降。

## 需使用者決定的問題

1. 是否接受回退/疊加粒子？（預設建議：不做，維持幾何方案。）
2. 若做，是「取代」還是「疊加於」core+sheath？（建議：疊加。）

核可前不動 `ImmersiveView.addLaserProjector` / `updateLaserProjector` / `LaserScatterMath`。
