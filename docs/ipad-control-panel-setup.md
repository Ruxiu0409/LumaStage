# iPad Control Panel — Xcode target setup

The iPad companion ("LumaStage Control") is a **separate iOS app target** that talks to the Apple
Vision Pro host over Multipeer Connectivity in real time. The Swift sources are already written; this
doc covers the one part the code can't do for itself — creating the target and setting file
membership. (The project uses Xcode **synchronized folder groups**, so files in `LumaStage/` already
belong to the visionOS target automatically; the iPad target needs membership set explicitly.)

Requires Xcode 26.4 (see the root `CLAUDE.md`).

## What's already in the repo

Shared, transport-agnostic core (Foundation-only, smoke-tested):
- `LumaStage/LumaSyncProtocol.swift` — the wire schema (`LumaSyncMessage`, `LumaHostState`,
  `LumaConversationState`, `LumaChatMessage`, `LumaControlCommand`, `LumaPeerRole`).
- `LumaStage/LumaSyncTransport.swift` — the transport protocol + JSON codec + `LoopbackSyncTransport`.
- `LumaStage/MultipeerSyncTransport.swift` — the real Multipeer Connectivity transport (host + panel).

Host side (visionOS target only — **do not** add to the iPad target):
- `LumaStage/LumaSyncCoordinator.swift` — mirrors `AppModel` state to the panel, applies its edits.
- `AppModel.startIPadSync()` is called from `LumaStageApp`'s main window `.task`.

iPad side (`LumaStage/iPadPanel/`, all `#if os(iOS)`):
- `LumaPanelApp.swift` (`@main`), `LumaPanelModel.swift`, `PanelRootView.swift`,
  `PanelChatView.swift`, `PanelLightingView.swift`.

## 1. Add the iOS app target

1. Open `LumaStage.xcodeproj` in Xcode 26.4.
2. Menu bar: **File ▸ New ▸ Target…**. (Equivalent: click the blue **LumaStage** project icon at the
   top of the Project navigator → in the editor select the **project** row → at the bottom of the
   **TARGETS** list click the **＋** button.)
3. In the template sheet, pick the **iOS** tab → **App** → **Next**.
4. Fill in: **Product Name** `LumaStageControl`; **Team** your team; **Interface** SwiftUI;
   **Language** Swift; **Storage** None; **Testing System** None. → **Finish**.
5. If Xcode asks "Activate scheme?", click **Activate**. Xcode creates a `LumaStageControl/` folder
   (its own synchronized group) and a `LumaStageControl` target + scheme.

## 2. Remove the auto-generated entry files

The panel's `@main` is the existing `LumaPanelApp`, so delete the ones Xcode just generated:

1. In the **Project navigator** (left sidebar, ⌘1) expand the new **LumaStageControl** folder.
2. Cmd-click `LumaStageControlApp.swift` **and** `ContentView.swift` → right-click → **Delete** →
   **Move to Trash**. (Keep `Assets.xcassets`.)

## 3. Add the shared + panel files to the iPad target

This is done with the **File Inspector → Target Membership** checkboxes (Xcode records them as
membership exceptions for the synchronized folder).

1. In the Project navigator, expand the **LumaStage** folder (and its **iPadPanel** subfolder).
2. Select all of these (Cmd-click each to multi-select):
   - **iPadPanel/** → `LumaPanelApp.swift`, `LumaPanelModel.swift`, `PanelRootView.swift`,
     `PanelChatView.swift`, `PanelLightingView.swift`
   - `LumaSyncProtocol.swift`, `LumaSyncTransport.swift`, `MultipeerSyncTransport.swift`
   - `LightingModels.swift`, `LightingAIService.swift`, `StageBuilderModels.swift`,
     `LightingFixtureCatalog.swift`, `LumaStageDesign.swift`
3. Open the **File Inspector**: the right-hand inspector panel — click the **inspector toggle** at the
   top-right of the window, or **View ▸ Inspectors ▸ File** (⌥⌘1).
4. In the **Target Membership** section, tick **LumaStageControl** so it is checked for every selected
   file (leave **LumaStage** as it is — these files already belong to it). If a box shows a dash
   (mixed), click until it is a solid check.

> Why those domain files: the schema reuses `LightingLook` / `FixtureFineControl` (in
> `LightingModels.swift`), which pull in `StageBuilderModels.swift`, `LightingFixtureCatalog.swift`,
> and `LightingAIService.swift`. `LumaStageDesign.swift` is the same Foundation/SwiftUI token set the
> headless smoke tests compile — known to build without UIKit / RealityKit.

**Do NOT add these to the iPad target** (they are visionOS- or host-only; the new target does not
include them by default, so simply leave them unchecked for LumaStageControl): `LumaStageApp.swift`,
`AppModel.swift`, `LumaSyncCoordinator.swift`, `ImmersiveView.swift`, `ContentView.swift`,
`VisionAIComposerBox.swift`, `FixtureObservatoryView.swift`, `FixtureSpatialScene.swift`,
`TabletopStageEditorView.swift`, `ProjectSelectionView.swift`, `LightingFixtureIntroView.swift`,
`SpeechTranscriber*`. (The `iPadPanel/` files stay in the
visionOS target too — harmless, they are `#if os(iOS)`-guarded to empty there.)

## 4. Local-network permission — for BOTH targets

Multipeer needs local-network access plus a declared Bonjour service. Do this twice — once for
**LumaStage**, once for **LumaStageControl**:

1. Click the blue **LumaStage** project icon → in the editor's **TARGETS** list select the target →
   open the **Info** tab.
2. In **Custom … Target Properties**, hover any row and click **＋** to add:
   - Key **Privacy - Local Network Usage Description** (`NSLocalNetworkUsageDescription`), Type
     String, Value: `LumaStage uses the local network to link the iPad control panel with the Apple Vision Pro.`
   - Key **Bonjour services** (`NSBonjourServices`), Type **Array**. Expand it and add two String
     items: `_lumastage-sync._tcp` and `_lumastage-sync._udp`.
3. Repeat steps 1–2 for the **LumaStageControl** target.

> The service name must match `MultipeerSyncTransport.serviceType` (`lumastage-sync`). The visionOS
> host already calls `startIPadSync()` from `LumaStageApp`, so it advertises on launch automatically.

## 5. (Optional) Confirm iPad target settings

Project icon → **TARGETS ▸ LumaStageControl ▸ General**: **Supported Destinations** includes **iPad**;
**Minimum Deployments** iOS 18 (or later). Confirm there is exactly one `@main` (`LumaPanelApp`) — i.e.
the auto-generated app file from step 2 is gone.

## 6. Build & run

1. **Scheme selector** (top-left of the toolbar, left of the Run ▶ button): choose **LumaStage** + an
   Apple Vision Pro destination → **Run** (⌘R).
2. Change the scheme to **LumaStageControl** + an iPad destination (simulator or device) on the **same
   Wi-Fi / local network** → **Run**.
3. On first launch each device shows a **local-network permission** prompt — tap **Allow**.
4. The panel's top pill turns green ("Connected"); the **Chat** tab mirrors the AVP conversation and
   the **Lighting** tab edits the live look in real time.

> Two simulators on one Mac discover each other over Multipeer, so you can test without hardware.

## Notes & future work

- The host currently publishes the full `LumaHostState` on every change (simple and robust on a local
  link); the `.conversation` / `.lighting` delta cases exist in the schema for a future optimization.
- The Lighting tab drives the existing cue API (`setFixtureIntensity` / `setFixtureColor` /
  `selectCue` / `resetSelectedCue`). The newer deterministic per-light overrides (`AppModel.lightOverrides`)
  are not yet exposed on the panel — a natural next addition (`LumaControlCommand` would gain cases).
- Two simulators on one Mac can discover each other over Multipeer, so the link is testable without
  hardware (local-network permission still applies).
