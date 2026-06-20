# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LumaStage is a **visionOS** AI stage-lighting design app (single target). It opens an immersive 1:1 night-outdoor stage digital twin (`ImmersiveView`, RealityKit) with a floating AI conversation box: a voice/typed prompt → on-device Apple Foundation Models → a cue-based lighting look applied with animated transitions.

The immersive scene has **two modes** (`StageImmersionMode`): `.fullStage` (default — `.full` immersion, opaque night-stage venue) and `.roomSpill` (`.mixed` passthrough, where the virtual spotlights illuminate the user's real room). See "Dual immersion modes" below.

> A former `LumaStage iPad` companion target (3D stage builder + per-cue micro-controls) was removed, so the cue-switching and dimmer/color controls — which lived only on iPad — are no longer surfaced in any view. `AppModel` still exposes those mutation methods (and `StageBuilderModels` still holds the builder's Foundation-only helpers), covered by the smoke tests, as reusable logic. New views use `#if os(visionOS)` / `#if canImport(...)` where platform-specific.

The product spec and MVP scope live in `docs/` (Traditional Chinese): `system-spec.md`, `demo-runbook.md`, `foundation-models-setup.md`. Code identifiers and user-facing strings are English; voice input supports mixed Chinese/English.

## Commands

### Build / run the app (requires Xcode 27)

The app uses on-device Apple Foundation Models and deploys to **visionOS 27**, so it needs **Xcode 27** (FoundationModels macro plugin + OS 27 SDK). `xcodebuild` is not available with Command Line Tools alone; point a build at an Xcode 27 install via `xcode-select` or a one-off `DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # an Xcode 27 install
```

Single scheme/target: `LumaStage` (visionOS, deploy 27.0). It links the local SwiftPM package `Packages/RealityKitContent`.

```bash
# Pick a concrete destination from: xcodebuild -showdestinations -scheme LumaStage
xcodebuild -scheme "LumaStage" -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=27.0' build
```

Day to day, building/running in the Xcode GUI is the normal path. The scene is a small plain window (`ContentView`) plus a full `ImmersiveSpace` (`ImmersiveView`). On-device generation only runs where Apple Intelligence is enabled; otherwise the AI box shows an unavailable state and generation is blocked.

### Tests (no Xcode needed)

Tests are a **custom `@main` smoke-test harness**, not XCTest, and **not part of the Xcode project**. There is no committed runner — compile it with the Foundation-only core sources and run the binary **from the repo root**:

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
- **`StageBuilderModels.swift`** (largest file) — the shared stage geometry the visionOS renderer consumes: `StageLayout` / `StageObject` / truss geometry / presets / `ImmersiveStageGeometryPlan`. Also holds the immersion-mode policy: `StageImmersionMode` and the Foundation-only `SurroundingsLightPolicy` (pinned by `surroundingsLightPolicyGatesOpaqueVenue`). It also still holds the pure-logic layout/policy helpers from the removed iPad stage builder (`StageBuilderPanelLayout`, `IPadRootLayout`, `StageBuilderZoom`, `StageBuilderToolbarLayout`, `StageBuilderViewportGround`, `StageBuilderRenderOrder`, `StageBuilderInspectorPolicy`, `StageBuilderSelectionPolicy`, `StageBuilderDropPlanner`) — no view consumes them now, but the smoke tests still pin them, so they remain as tested, reusable logic.
- **`LightingFixtureCatalog.swift`** — fixture vocabulary metadata.

When adding behavior to a view, **extract the decidable part into one of these model files and add a smoke test for it** rather than burying it in the view.

### State flow

`AppModel` (`@MainActor @Observable`) is the single source of truth, injected via `.environment(appModel)` from `LumaStageApp`. Views never mutate lighting state directly — they call `AppModel` methods, which delegate to `StageState`, which **re-validates on every mutation**. `SpeechTranscriber` (also `@Observable`) feeds transcripts in.

```
voice/typed prompt → AppModel.generate → FoundationModelsLightingService → LightingLook
  → StageState.replaceLightingLook (validates) → AppModel (Observable) → views re-render
cue edit (AppModel.set…/selectCue) → StageState.patchSelectedCue (validates) → AppModel → ImmersiveView update
```

### Lighting look invariants (enforced in `LightingLook.validate()`)

The `@Generable GeneratedLightingLook` schema constrains the model, and `LightingLookDraft.makeValidatedLook()` runs `validate()` on the result — keep the two in sync if you touch either:

- `schemaVersion == "1.0"`, `ambient.preset == standardNight`.
- Both cues `cue_opening` (**Opening**) and `cue_highlight` (**Highlight**) must be present and `selectedCueId` must resolve (`validate()`); the AI schema additionally caps the look at exactly those two.
- `intensity` in `0.0...1.0`; `color.mode == rgb`; color is `#RRGGBB` hex.
- Fixture roles limited to `wash`, `spot`, `frontLight`, `backgroundWash`.

### Editing model: cue patches, not look replacement

Cue edits go through `CuePatch` + `StageState.patchSelectedCue` and **only ever mutate the currently selected cue** — never the whole look, never the other cue. `StageState` keeps a `baselineLook`; `resetSelectedCue()` restores **only** the selected cue from that baseline. Full-look replacement happens solely via AI generation (`replaceLightingLook`).

### AI service shape

`AppModel` holds a `LightingLookGenerating` (default `FoundationModelsLightingService`, injectable for tests/previews). Before generating, `AppModel.generate` refreshes `modelAvailability` from `SystemLanguageModel.default.availability`; if unavailable it surfaces the reason and **does not generate** (no fallback). The service runs a `LanguageModelSession` with `@Generable` structured output (`GenerationOptions(samplingMode: .greedy, …)`), maps the result through `LightingLookDraft.makeValidatedLook()`, and presents user-facing errors via the OS 27 `LanguageModelError` cases. On-device generation can't run headlessly, so the smoke tests cover the `LightingLookDraft` assembler/validation boundary instead of the model call.

### Shared stage geometry

`ImmersiveStageGeometryPlan.make(from: StageLayout)` builds the visionOS stage geometry that `ImmersiveView` renders; a smoke test (`visionStageUsesIPadStageLayoutGeometry`) still pins it against the `StageLayout` model. The lit fixtures are **real RealityKit `SpotLight` entities** (visionOS 27), not translucent boxes: `addStageSpotLight` aims each spotlight's `-Z` at a stage target, and `apply(_:to:)` → `updateSpotLight` drives color/intensity/cone/soft-shadow/gobo per cue by role. The Foundation-only `SpotLightRenderMath` (pinned by `spotLightRenderMathMapsIntensityAndBeamAngle`) maps the cue's 0...1 intensity → photometric lumens, beam angle → cone degrees, and beam angle → `SpotLightComponent.Shadow.lightSize` (penumbra; quality is `.high` for front, `.medium` for wash). Soft shadows only render because structural meshes (truss, connectors, fixtures, deck, legs) opt into casting via `markShadowCaster` → `DynamicLightShadowComponent(castsShadow: true)` — a light's `Shadow` config alone is inert without casters; lit surfaces receive automatically. An optional per-fixture `GoboPattern` is projected via `SpotLightComponent.ProjectiveTexture` from a procedurally drawn, cached `TextureResource` — `LightingLookDraft` clears gobos on non-rendering roles (`FixtureRole.rendersProjectedGobo`). Only `frontLight`/`backgroundWash` roles are rendered as spotlights. The per-cue relight cross-fades over `cue.transition.duration` by mutating the light inside a SwiftUI `withAnimation` transaction (`SpotLightComponent` is an `_ImplicitlyAnimatableBuiltinComponent`; `Shadow`/`ProjectiveTexture` are plain components, so they hard-cut). **Footgun:** `apply(_:to:)` runs only inside the `RealityView` `update:` closure, which re-runs only when `ImmersiveView.body` re-evaluates — a `RealityView` update closure does **not** form its own Observation dependencies (WWDC25 "Better together: SwiftUI and RealityKit": treat the update closure as an extension of the view's body). So `body` must eagerly read `appModel.lightingLook` (a throwaway `let _ =`); without that read, AI generation mutates `stageState` but the scene never relights (the AI box text still updates, because `VisionAIComposerBox` reads `conversationState` directly during its own body eval). Any `@Observable` state the `update:` closure must react to has to be read at `body` level too — same footgun as the Scene-level `stageImmersionMode` read in `LumaStageApp`. The AI box embeds as a SwiftUI `Attachment`. Projects with no saved layout fall back to `StageLayout.defaultStudentOutdoor()`.

### Dual immersion modes (full stage ↔ room spill)

`AppModel.stageImmersionMode` is the source of truth; `toggleStageImmersion()` flips it (the sun icon in `VisionAIComposerBox`). The full↔mixed transition is wired across three files and is easy to break:

- **`LumaStageApp`** drives it with `.immersionStyle(selection: immersionStyleSelection, in: .full, .mixed)`. The selection is a **two-way `Binding`** (not `.constant`) so the system can write user-initiated immersion changes back into the model. The Scene body **eagerly reads `appModel.stageImmersionMode`** (a throwaway `let _ =`) so SwiftUI re-evaluates the Scene when the in-space toggle flips it — a property read only inside the lazy binding closure would not be observed.
- **`ImmersiveView`** reacts in its `update:` closure: it hides the opaque venue container (named `opaqueVenueName`, grouping floor + backdrop) per `SurroundingsLightPolicy.includesOpaqueVenue(in:)` so passthrough shows through, and applies `.preferredSurroundingsEffect(.dim(...))` in room-spill.
- Spotlights tag themselves with `SpotLightComponent.SurroundingsLight()` (visionOS 27) so they illuminate the real room in passthrough; it's inert in full immersion, so it's always set.

The opaque-venue gating decision lives in `SurroundingsLightPolicy` (Foundation-only, smoke-tested) rather than in the view — extend that enum, not the view, when adding mode-dependent geometry.

## Conventions

- Design tokens (colors, radii, glass panel modifiers) live in `LumaStageDesign.swift` / `LumaPanel`; the UI targets native "liquid glass" styling. Reuse these rather than hardcoding colors.
- visionOS/RealityKit views use `#if os(visionOS)`; `SpeechTranscriber` is guarded by `canImport(Speech)/canImport(AVFoundation)`, and `LightingFixtureIntroView` (SceneKit fixture previews) by `canImport(SceneKit) && canImport(UIKit)`.
- New projects start from `ProjectCreationTemplate`; the project list starts empty by default (`LumaStageProject.defaultProjects()` returns `[]`).
