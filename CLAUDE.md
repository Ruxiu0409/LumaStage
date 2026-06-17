# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LumaStage is an AI stage-lighting design app shipped as **two targets from one source folder**:

- **`LumaStage`** — visionOS app. Opens an immersive 1:1 night-outdoor stage digital twin (`ImmersiveView`, RealityKit), with a floating AI conversation box. Voice/typed prompt → on-device Apple Foundation Models → cue-based lighting look applied with animated transitions.
- **`LumaStage iPad`** — iOS/iPad app. Companion that adds a 3D stage builder (`StageBuilderView`) and lightweight per-cue lighting micro-controls.

Both targets compile the same files in `LumaStage/`, split by `#if os(iOS)` / `#if os(visionOS)` / `#if canImport(...)`. **Any new file must compile (or be guarded) for both platforms.**

The product spec and MVP scope live in `docs/` (Traditional Chinese): `system-spec.md`, `ipad-stage-builder-spec.md`, `demo-runbook.md`, `foundation-models-setup.md`. Code identifiers and user-facing strings are English; voice input supports mixed Chinese/English.

## Commands

### Build / run the apps (requires Xcode 27)

The app uses on-device Apple Foundation Models and deploys to **visionOS 27 / iOS 27**, so it needs **Xcode 27** (FoundationModels macro plugin + OS 27 SDK). `xcodebuild` is not available with Command Line Tools alone; point a build at an Xcode 27 install via `xcode-select` or a one-off `DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # an Xcode 27 install
```

Schemes/targets: `LumaStage` (visionOS, deploy 27.0) and `LumaStage iPad` (iOS, deploy 27.0). Both link the local SwiftPM package `Packages/RealityKitContent`.

```bash
# Pick a concrete destination from: xcodebuild -showdestinations -scheme LumaStage
xcodebuild -scheme "LumaStage"      -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=27.0' build
xcodebuild -scheme "LumaStage iPad" -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=27.0' build
```

Day to day, building/running in the Xcode GUI is the normal path. The visionOS scene is a small plain window (`ContentView`) plus a full `ImmersiveSpace`; the iPad app launches into `IPadRootView`. On-device generation only runs where Apple Intelligence is enabled; otherwise the AI box shows an unavailable state and generation is blocked.

### Tests (no Xcode needed)

Tests are a **custom `@main` smoke-test harness**, not XCTest, and **not part of the Xcode project**. There is no committed runner — compile it with the Foundation-only core sources and run the binary **from the repo root** (it reads `LumaStage/Info-iPad.plist` via a relative path):

```bash
swiftc \
  Tests/LumaStageCoreSmokeTests.swift \
  LumaStage/LightingModels.swift \
  LumaStage/LightingAIService.swift \
  LumaStage/StageBuilderModels.swift \
  LumaStage/LightingFixtureCatalog.swift \
  LumaStage/LumaStageDesign.swift \
  -o /tmp/LumaStageCoreSmokeTests && /tmp/LumaStageCoreSmokeTests
# prints "LumaStageCoreSmokeTests passed" and exits 0 on success
```

`Tests/LumaStageCoreSmokeTests.swift` runs every check sequentially from `static func main()` using `expect` / `expectThrows` (failures call `fatalError`). To add a test: write a `private static func` and **register the call in `main()`** — there is no auto-discovery. To run one test, temporarily comment out the others in `main()`.

**Keep FoundationModels out of the smoke-test compile set.** `canImport(FoundationModels)` is true even under Command Line Tools, so all FoundationModels references live in `FoundationModelsLightingService.swift` and `AppModel.swift` (which the harness does **not** compile). `LightingAIService.swift` stays Foundation-only; the smoke tests cover the AI→domain boundary via `LightingLookDraft`, not the model call.

### Apple Foundation Models (on-device, no key)

AI generation runs entirely on-device via Apple Foundation Models — **no API key, no network**. It requires Apple Intelligence to be available (supported device/simulator, enabled in Settings, model downloaded). When unavailable, the AI box surfaces the reason and Send/mic are disabled — there is **no local fallback**. See `docs/foundation-models-setup.md`.

## Architecture

### Layering: testable core vs. thin views

The defining convention: **all pure logic — data models, validation, geometry, render order, layout math, AI parsing — lives in `Foundation`-only files**, and SwiftUI views are thin consumers. This is what lets the smoke tests run headlessly without a simulator.

- **`LightingModels.swift`** — `LightingLook` / `LightingCue` / `FixtureGroup` / `FixtureColor` / `FixtureFineControl`, the `CuePatch` enum, `StageState`, `LumaStageProject`, and `ValidationError`.
- **`LightingAIService.swift`** — Foundation-only generation contract (`LightingLookGenerating`, `LightingModelAvailability`, `LightingGenerationResult`) and the testable AI→domain assembler `LightingLookDraft.makeValidatedLook()`. No FoundationModels import.
- **`FoundationModelsLightingService.swift`** — on-device implementation: an `@Generable GeneratedLightingLook` filled by `LanguageModelSession`, mapped into `LightingLookDraft`. Guarded by `#if canImport(FoundationModels)`.
- **`StageBuilderModels.swift`** (largest file) — `StageLayout` / `StageObject` / truss geometry / presets, **plus** the pure helpers the iPad views render from and the tests assert on: `StageBuilderPanelLayout`, `IPadRootLayout`, `StageBuilderZoom`, `StageBuilderToolbarLayout`, `StageBuilderViewportGround`, `StageBuilderRenderOrder`, `StageBuilderInspectorPolicy`, `StageBuilderSelectionPolicy`, `StageBuilderDropPlanner`, and `ImmersiveStageGeometryPlan`.
- **`LightingFixtureCatalog.swift`** — fixture vocabulary metadata.

When adding behavior to a view, **extract the decidable part into one of these model files and add a smoke test for it** rather than burying it in the view.

### State flow

`AppModel` (`@MainActor @Observable`) is the single source of truth, injected via `.environment(appModel)` from `LumaStageApp`. Views never mutate lighting state directly — they call `AppModel` methods, which delegate to `StageState`, which **re-validates on every mutation**. `SpeechTranscriber` (also `@Observable`) feeds transcripts in.

```
voice/typed prompt → AppModel.generate → FoundationModelsLightingService → LightingLook
  → StageState.replaceLightingLook (validates) → AppModel (Observable) → views re-render
iPad control → AppModel.set… → StageState.patchSelectedCue (validates) → views/RealityKit update
```

### Lighting look invariants (enforced in `LightingLook.validate()`)

The `@Generable GeneratedLightingLook` schema constrains the model, and `LightingLookDraft.makeValidatedLook()` runs `validate()` on the result — keep the two in sync if you touch either:

- `schemaVersion == "1.0"`, `ambient.preset == standardNight`.
- Both cues `cue_opening` (**Opening**) and `cue_highlight` (**Highlight**) must be present and `selectedCueId` must resolve (`validate()`); the AI schema additionally caps the look at exactly those two.
- `intensity` in `0.0...1.0`; `color.mode == rgb`; color is `#RRGGBB` hex.
- Fixture roles limited to `wash`, `spot`, `frontLight`, `backgroundWash`.

### Editing model: cue patches, not look replacement

iPad edits go through `CuePatch` + `StageState.patchSelectedCue` and **only ever mutate the currently selected cue** — never the whole look, never the other cue. `StageState` keeps a `baselineLook`; `resetSelectedCue()` restores **only** the selected cue from that baseline. Full-look replacement happens solely via AI generation (`replaceLightingLook`).

### AI service shape

`AppModel` holds a `LightingLookGenerating` (default `FoundationModelsLightingService`, injectable for tests/previews). Before generating, `AppModel.generate` refreshes `modelAvailability` from `SystemLanguageModel.default.availability`; if unavailable it surfaces the reason and **does not generate** (no fallback). The service runs a `LanguageModelSession` with `@Generable` structured output (`GenerationOptions(samplingMode: .greedy, …)`), maps the result through `LightingLookDraft.makeValidatedLook()`, and presents user-facing errors via the OS 27 `LanguageModelError` cases. On-device generation can't run headlessly, so the smoke tests cover the `LightingLookDraft` assembler/validation boundary instead of the model call.

### Shared stage geometry

`ImmersiveStageGeometryPlan.make(from: StageLayout)` is the **single geometry source consumed by both** the iPad `StageBuilderView` and the visionOS `ImmersiveView`. A smoke test (`visionStageUsesIPadStageLayoutGeometry`) pins this equivalence — changing how truss/decks are generated must keep both renderers consistent. `ImmersiveView` then applies the selected cue with animated `entity.move(to:duration:timingFunction:)` transitions and embeds the AI box as a SwiftUI `Attachment`.

## Conventions

- Design tokens (colors, radii, glass panel modifiers) live in `LumaStageDesign.swift` / `LumaPanel`; the UI targets native iOS 26 "liquid glass" styling. Reuse these rather than hardcoding colors.
- visionOS-only code (`RealityKit`, immersive views) and iOS-only code (`StageBuilderView`, `IPadRootView`, UIKit) are mutually guarded; `SpeechTranscriber` is guarded by `canImport(Speech)/canImport(AVFoundation)`.
- New projects start from `ProjectCreationTemplate`; the project list starts empty by default (`LumaStageProject.defaultProjects()` returns `[]`).
