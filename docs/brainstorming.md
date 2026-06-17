# LumaStage Brainstorming

## Project Snapshot

- Project: LumaStage
- Platform direction: visionOS / SwiftUI / RealityKit
- Current app shape:
  - Main window shows a `Model3D` scene preview.
  - A button toggles a full immersive space.
  - Immersive content is loaded from `RealityKitContent`.
- Current stage: early prototype / concept exploration.

## North Star

> Let users design stage lighting with AI, step into a 1:1 outdoor stage digital twin, and use iPad micro-controls to fine-tune the result while seeing changes immediately in Apple Vision Pro.

## This Week MVP Core Experience

### One Sentence

`LumaStage` is an Apple Vision Pro + iPad demo where users talk to AI to generate lighting on a 1:1 outdoor stage digital twin, then use iPad micro-controls to fine-tune the result.

### Core User Flow

1. The user enters a 1:1 outdoor stage digital twin in Apple Vision Pro.
2. A single floating AI conversation box appears in Vision Pro; a lightweight iPad panel is available for precise micro-adjustments.
3. The user speaks a lighting-design request, such as: "Create a warm opening look for this outdoor student event."
4. OpenAI API generates a simple structured lighting look using basic fixtures, color, dimmer / intensity, and a fixed `standardNight` ambient baseline.
5. The user uses iPad micro-controls to adjust one or two parameters, such as front light dimmer or wash color.
6. The Apple Vision Pro stage updates immediately.
7. AI gives one short explanation using industry language plus plain wording, such as: "Dimmer means how bright the light is; 60% makes the front light softer without hiding the performer."

### Demo Goal

Show one believable loop: **voice prompt -> AI lighting design -> immersive outdoor stage preview -> iPad micro-adjustment -> beginner-friendly professional explanation**.

### In Scope This Week

- 1:1-style outdoor stage digital twin.
- Fixed `standardNight` outdoor ambient-light baseline.
- One floating AI conversation UI in Vision Pro.
- Lightweight iPad micro-adjustment controls: front light dimmer, background wash color, and reset.
- Real speech-to-text as the primary input, with typed fallback only if microphone transcription fails during the demo.
- Mixed Mandarin / English speech support, especially for lighting terms such as `wash`, `spot`, `front light`, `background wash`, `dimmer`, and `intensity`.
- OpenAI API call for structured lighting design and explanation generation.
- Basic lighting concepts: fixture names, color, dimmer / intensity.
- Targeted iPad adjustments for front light dimmer and background wash color, plus reset.
- One short AI explanation after a change.

### Out Of Scope For This Week

- Real-world AR lighting cast onto a physical stage.
- Full iPad editor beyond MVP micro-adjustment.
- Lighting-console export.
- Rigging / load-capacity simulation.
- Indoor venue and window-daylight simulation.
- Daytime / sunset outdoor-light simulation.
- Full cue timeline editor, playback automation, MIDI, audio reactivity, or multi-user sessions.

## Problem Framing

- For lighting designers, a common pain point is that computer-based previsualization does not fully match the real result after cues are written to physical fixtures.
- Because the simulated look and the real on-site look diverge, the team still needs to spend time re-adjusting the lighting after load-in.
- The intended value of `LumaStage` is to use Apple Vision Pro as a more spatially convincing previsualization environment, so the result after writing to lights is close enough that major on-site rework is no longer necessary.
- This means the core problem is not just "having a simulator," but improving the trustworthiness of previsualization before entering the venue.
- A lighting designer pointed out that the pain often starts even earlier: the team may not be able to fully see, inspect, or understand the stage before planning begins.
- This is especially common in student events, where venue documents or stage plots may exist, but planning still cannot keep up with real-world changes.
- Rigging uncertainty is real: rigging points may differ from engineering drawings, and the team may need to improvise on site. However, this is currently too broad for the first product focus and should be deferred.
- For `v1`, the first simulation target should be an outdoor stage, because student events often use outdoor stages and this environment is easier to inspect completely than indoor venues.
- The focused environmental problem is that a nighttime outdoor stage still needs a believable ambient baseline before designed stage lights can be judged. For the MVP, this should be fixed as `standardNight` rather than comparing multiple night environments.
- Indoor window daylight can remain a future extension after the outdoor-stage case is clear.
- For students and beginners, another pain point is that meaningful practice or testing often requires setting up a full lighting environment with real equipment.
- Because fixtures, controllers, and venue access often require rental cost or institutional resources, the learning cost is too high for people who are still learning the basics.
- In an AI-first workflow, beginners also need enough lighting vocabulary to communicate intent. If they do not know fixture names, color concepts, or dimmer / intensity language, they can only ask AI in vague mood words.
- The intended value of `LumaStage` for this user group is to become an AI lighting-design tool that also teaches just enough fundamentals to help users make better requests and understand generated results.
- This means `LumaStage` may have two related problem tracks: a professional previs accuracy track and an education / accessibility track for learners.

## Competition Framing

- For competition positioning, the current recommended framing is `AI-assisted stage lighting design first, learning support second`.
- The primary story is that `LumaStage` lets users generate and revise stage lighting through conversation with AI, then immediately preview the result spatially in Apple Vision Pro.
- The education value still matters, but it should support the AI design workflow rather than replace it. Beginners learn enough lighting vocabulary and concepts to communicate better with AI.
- For example, knowing fixture names and roles helps a user ask for more precise results: "use a wash for the background", "make the spot softer", or "lower the front light dimmer".
- The professional extension is that the same AI-assisted spatial preview can later support more reliable previs before load-in, especially around outdoor lighting conditions, stage scale, viewing angles, and venue-specific constraints.

## Draft Problem Statement

- `LumaStage` aims to solve the fact that stage-lighting design currently depends heavily on physical equipment, real venues, specialist vocabulary, and incomplete on-site information, making it difficult for beginners to express design intent and leaving professionals without a sufficiently trustworthy spatial preview before entering the venue.
- For the first version, the most focused production problem is that a nighttime outdoor stage is not visually neutral, but the demo should not simulate every possible night condition. `standardNight` provides one credible baseline so the user can judge the AI-generated lighting look without spending MVP effort on ambient-light variations.
- Rigging-point mismatch and load-capacity uncertainty are real field problems, but they should be treated as future scope rather than the first demo focus.
- By using Apple Vision Pro to build a voice-first AI lighting-design environment, `LumaStage` helps users describe, generate, revise, and understand stage lighting while also creating a future path toward more reliable professional stage-light previsualization.

## AI Generation Direction

- A key product direction is to let users describe the desired stage result instead of manually building every lighting detail from scratch.
- The intended input can include a natural-language prompt, outdoor stage photos, stage plots or venue documents when available, the list of available equipment, and the target atmosphere or effect. MVP should assume the environment is `standardNight`.
- The intended output is an AI-generated cue-based stage concept that translates those constraints into a coherent visual result inside `LumaStage`.
- This means `LumaStage` is not only a simulator, but also an AI-assisted stage-generation tool built on top of a structured scene representation.
- A likely long-term architecture is: user intent -> structured stage schema -> generated scene / cues / visual states.
- For `v1`, the recommended output level is an editable generated stage configuration: strong enough to demo and useful for learning, but not yet framed as export-ready lighting-console data.
- The MVP should start with two cues only: `Opening` and `Highlight`. This gives the demo visible motion and cue switching without becoming a full timeline editor.
- For this week's MVP, use the OpenAI API to turn a prompt into structured stage-lighting JSON plus one short explanation. The app should not depend on a full agentic backend yet.
- The most important output is not free-form prose; it is a predictable cue-based scene patch: selected cue, fixture groups, color, dimmer / intensity, animated cue transition, fixed `standardNight` ambient baseline, and explanation text.

## MVP Lighting Look Schema

### Overall Purpose

The first OpenAI structured output should describe a small cue-based lighting look for the stage, not a full lighting-console project. Its job is to give Vision Pro, iPad micro-controls, cue transitions, and AI explanations one shared data shape:

- OpenAI generates a lighting look from a voice transcript or typed prompt.
- Vision Pro applies the selected cue's fixture-group settings to the immersive stage.
- iPad controls update the currently selected cue as small patch operations.
- MVP uses two cues, `Opening` and `Highlight`; moving between them animates from the previous cue state into the next cue state.
- The explanation stays tied to the actual fixture groups, colors, dimmer / intensity values, and the fixed `standardNight` ambient baseline.

This schema is intentionally small. It should be strong enough for the MVP demo while leaving full cue timeline editing, DMX patching, rigging, fixture photometrics, and console export for future versions.

### Example JSON Format

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
    "actionSummary": "Set the front wash to a softer warm look and added a cooler background wash for contrast."
  }
}
```

### Field Reference

| Field | Type / Example | Description |
| --- | --- | --- |
| `schemaVersion` | String, for example `"1.0"` | Version of the lighting-look schema. Keep this explicit so future app versions can migrate older generated looks safely. |
| `intent` | String enum, for example `"generateLook"` | The user's operation intent after AI parsing. MVP values can include `generateLook`, `localEdit`, `explainOnly`, and `resetLook`. This helps the app distinguish full generation from targeted changes. |
| `lookName` | String, for example `"Warm Opening Look"` | Human-readable name for the generated look. It can appear in the AI conversation box or iPad panel. |
| `mood` | String, for example `"warm, welcoming, student event"` | Short natural-language summary of the requested atmosphere. This is useful for the UI and for explaining why the generated settings were chosen. |
| `ambient` | Object | Nighttime outdoor ambient-light baseline. MVP should keep this fixed so the demo focuses on AI lighting generation and fixture-level edits. |
| `ambient.preset` | Fixed string `"standardNight"` | The only MVP ambient preset. `darkNight` and `brightSurroundings` can become future comparison modes after the core loop works. |
| `ambient.level` | Fixed number, for example `0.35` | Overall ambient brightness baseline for `standardNight`. Keep fixed in MVP rather than exposing it as an iPad control. |
| `ambient.colorTemperature` | Fixed number in Kelvin, for example `4200` | Approximate color temperature of the surrounding light for `standardNight`. Keep fixed in MVP. |
| `selectedCueId` | Stable string ID, for example `"cue_opening"` | The cue currently shown or edited. iPad micro-controls should apply to this cue unless the user explicitly selects another cue. |
| `cues` | Array of cue objects | The ordered cue list for the generated look. MVP should use two cues, `Opening` and `Highlight`, not a full timeline editor. |
| `cues[].id` | Stable string ID, for example `"cue_opening"` | Machine-readable cue identifier used for cue selection, targeted edits, and animated transitions. |
| `cues[].name` | String, for example `"Opening"` | Human-readable cue name for the Vision Pro conversation UI or iPad cue selector. |
| `cues[].transition` | Object | Animation instruction for moving into this cue from another cue. |
| `cues[].transition.duration` | Number in seconds, for example `1.2` | How long the transition animation should take. MVP can use a fixed default such as `1.2`. |
| `cues[].transition.easing` | String enum, for example `"easeInOut"` | Easing curve for the cue transition. MVP should use `easeInOut` unless a specific cue needs a different feel. |
| `cues[].fixtureGroups` | Array of fixture-group objects | The fixture states for this cue. Vision Pro renders the selected cue's fixture groups; iPad edits patch the selected cue's fixture groups. |
| `cues[].fixtureGroups[].id` | Stable string ID, for example `"front_wash"` | Machine-readable fixture-group identifier used by Vision Pro, iPad controls, and targeted AI edits. This should not change when the display name changes. |
| `cues[].fixtureGroups[].name` | String, for example `"Front Wash"` | Human-readable fixture-group name for UI labels and explanations. |
| `cues[].fixtureGroups[].role` | String enum, for example `"frontLight"` | Lighting role of the group. MVP values are `wash`, `spot`, `frontLight`, and `backgroundWash`. |
| `cues[].fixtureGroups[].zone` | String enum, for example `"stageFront"` | Stage area affected by the group. MVP values can include `stageFront`, `stageBack`, `stageLeft`, `stageRight`, and `fullStage`. |
| `cues[].fixtureGroups[].enabled` | Boolean, for example `true` | Whether this fixture group should be active in this cue. This lets AI or iPad controls turn a group off without deleting it from the schema. |
| `cues[].fixtureGroups[].intensity` | Number from `0.0` to `1.0`, for example `0.6` | Dimmer / intensity value for this cue. `0.6` means 60% brightness. This should map directly to the beginner-facing dimmer control. |
| `cues[].fixtureGroups[].color` | Object | Color instruction for the fixture group in this cue. MVP can use RGB hex first because it is easy to store and preview. |
| `cues[].fixtureGroups[].color.mode` | String enum, for example `"rgb"` | Color format. MVP should use `rgb`; later versions can add `colorTemperature`, `gel`, or fixture-native color modes. |
| `cues[].fixtureGroups[].color.value` | String, for example `"#FFD1A3"` | Color value in the selected mode. For `rgb`, use a six-digit hex color string. |
| `explanation` | Object | Short educational feedback tied to the generated or modified look. This is part of the product experience, not optional free-form prose. |
| `explanation.term` | String, for example `"Dimmer / intensity"` | The professional lighting term being taught or reinforced. |
| `explanation.plainText` | String | Beginner-friendly explanation of the term or change. It should be short enough to fit in the floating AI box. |
| `explanation.actionSummary` | String | One-sentence summary of what the AI changed in the stage look. |

### MVP Enum Guidance

- `intent`: `generateLook`, `localEdit`, `explainOnly`, `resetLook`.
- `ambient.preset`: `standardNight` only for MVP.
- `cues[].transition.easing`: `easeInOut`.
- `cues[].fixtureGroups[].role`: `wash`, `spot`, `frontLight`, `backgroundWash`.
- `cues[].fixtureGroups[].zone`: `stageFront`, `stageBack`, `stageLeft`, `stageRight`, `fullStage`.
- `cues[].fixtureGroups[].color.mode`: `rgb`.

### Not In The MVP Schema

- Full cue timeline editing, timeline scrubbing, and production-grade cue sequencing.
- DMX addresses, universe numbers, and console export data.
- Fixture physical specifications, beam angle, photometric accuracy, and lens behavior.
- Advanced fixture vocabulary such as `PAR`, `movingHead`, `sideLight`, and `ambientFill`.
- Truss, rigging points, load capacity, and engineering drawing mismatch.
- Alternate ambient presets such as `darkNight` and `brightSurroundings`.
- Full venue simulation such as house lights, signage, reflective materials, daytime sunlight, or indoor window daylight.

## Interaction Model

- For `v1`, the interface should stay simple: Vision Pro shows the immersive stage plus a single floating AI conversation box, while iPad provides a lightweight micro-adjustment panel.
- Voice should be the primary input method. Users speak what they want to see, change, or learn, instead of manipulating a dense lighting console-style interface.
- The floating conversation box should minimally show mic state, transcript, AI understood command, and one explanation.
- Speech-to-text should preserve the user's mixed Mandarin / English phrasing. A second AI parsing step should convert the transcript into structured lighting commands before the stage changes.
- The user should be able to say commands such as changing color, adjusting dimmer / intensity, asking what a fixture does, or generating a new look.
- iPad micro-adjustment is part of the Core Experience, but it should stay narrow: front light dimmer, background wash color, and reset.
- iPad micro-adjustments apply to the currently selected cue. Reset should restore the selected cue to its generated baseline rather than resetting the whole design.
- Cue selection should animate the stage from the previous cue state to the selected cue state using the cue's transition settings.
- A full iPad editor with fixture placement, timeline editing, equipment tables, and scene management can remain future scope.
- This creates a focused workflow: enter the immersive stage -> speak to the floating AI box -> preview the generated lighting -> fine-tune on iPad -> hear or read a lightweight explanation.

## Targeted AI Editing

- Voice editing in Apple Vision Pro should support both targeted local edits and full stage generation.
- Targeted editing should behave more like a design-assistant workflow than a full regeneration workflow.
- The user should be able to target a specific part of the design, such as one lighting zone, one fixture group, one cue, one color palette, or one timing segment.
- The AI should apply a localized change to the selected target while preserving unrelated parts of the stage configuration.
- This avoids the problem where every prompt accidentally changes the entire design or breaks parts that the user already approved.
- Example voice requests: "make only the back lights cooler", "keep the front wash unchanged", "slow down the second cue", "only adjust the left side beams", or "make this chorus section brighter without changing the verse".
- Full voice-driven generation should also be available when the user clearly asks for it, such as "create a whole new opening look", "generate a concert-style version from this equipment list", or "redesign the entire lighting plan for a dramatic finale".
- The important product distinction is intent: local edit commands should preserve unrelated content, while explicit full-generation commands may rewrite the complete stage configuration.
- This implies the stage schema needs stable IDs, grouped elements, editable cue segments, and a way to express patch-style changes instead of replacing the whole scene.

## AI Communication Guidance

- `LumaStage` should not become a separate lighting course. Its education value should help users communicate better with AI during stage-lighting design.
- For beginners, the first support layer should be practical vocabulary and concepts: what common fixture types are called, what each fixture is usually used for, how color changes the scene, and how dimmer / intensity control changes visibility and mood.
- Industry terms should be taught directly, but always paired with beginner-friendly explanations. For example, teach "dimmer / intensity" as the professional term, then explain it as how bright the light is or how much the light is being pushed.
- After generating or modifying a stage, the AI can provide lightweight explanations that connect the result back to better prompting and design control.
- This turns learning into an AI-collaboration aid: users experiment, see results, learn the words and concepts, then make better follow-up requests.
- Useful guidance examples include explaining which fixture name to use for a desired effect, which lights create the main visual focus, why a color palette fits the requested mood, what happens when dimmer values change, or how to ask for a softer, more dramatic, or easier-to-read scene.
- For the competition story, this strengthens the AI-design positioning because `LumaStage` is not only generating results; it is teaching users how to ask for better results.

## Background Idea Pool

- Spatial stage for light, visuals, and atmosphere.
- Immersive scene that can shift mood through lighting, scale, color, and movement.
- A simple floating AI conversation surface, with the immersive world as the output.
- Possible use cases:
  - Performance / music visualization
  - Personal creative stage
  - Ambient room transformation
  - Presentation or storytelling space
  - Interactive installation prototype

## Core Questions For Later

- Who is the first target user?
- Is LumaStage primarily a creative tool, an experience, or a performance system?
- Should users build scenes, perform with scenes, or simply enter curated scenes?
- What is the smallest impressive demo?
- What interaction should feel native to visionOS instead of copied from desktop/mobile?
- What assets are needed first: stage, lights, particles, audio, timeline, controls?

## Possible Future Directions

### Ambient Stage

A calm immersive environment where users select moods and lighting presets.

Strengths:
- Small scope for a first prototype.
- Fits visionOS immersion well.
- Can be visually compelling without complex authoring tools.

Risks:
- May feel like a screensaver if interaction is too thin.

### Live Visual Performance Tool

A spatial VJ-style stage where users trigger scenes, lights, effects, and transitions.

Strengths:
- Strong identity.
- Clear relationship between "stage" and "control surface".

Risks:
- Requires careful input design and timing.
- Audio/MIDI integration could expand scope quickly.

### Storytelling Space

Users move through immersive stage scenes that reveal narrative moments.

Strengths:
- Good fit for crafted visual moments.
- Easier to control quality than an open-ended editor.

Risks:
- Needs stronger content direction.

### Spatial Scene Editor

A tool for arranging lights, props, effects, and stage states in 3D.

Strengths:
- Powerful long-term product path.
- Can grow into a serious creative tool.

Risks:
- Large scope.
- Needs robust manipulation, persistence, undo, and asset management.

## MVP For This Week

### Outdoor Stage AI Lighting Demo

- Main visible Vision Pro UI is a single floating AI conversation box.
- iPad provides a lightweight micro-adjustment panel.
- Immersive space contains a 1:1-style outdoor stage digital twin.
- User speaks one initial lighting-design request.
- AI applies one generated cue-based lighting look with basic fixtures, color, dimmer / intensity, animated cue transitions, and fixed `standardNight` ambient light.
- User fine-tunes the selected cue on iPad, such as front light dimmer or background wash color.
- The stage updates immediately, and switching cues animates between cue states.
- AI explains one professional term in plain language so the user can communicate better with AI next time.

### Demo Script Draft

1. Start in an outdoor student-event stage.
2. Say: "Create a warm opening look for this outdoor stage."
3. Show AI generating a small cue-based lighting look.
4. Switch to the opening cue and show the stage animating into that cue.
5. On iPad, lower the selected cue's front light dimmer to 60%.
6. Show the front light becoming softer while the performer remains visible.
7. On iPad, make the selected cue's background wash cooler.
8. Switch cues and show the change animating rather than jumping.
9. AI explains: "Dimmer / intensity controls how bright the fixture is. 60% means the front light is softer, so the performer is still visible without overpowering the background."

## Product Principles

- Make the immersive world the main event.
- Keep the control UI quiet, clear, and fast: one floating AI conversation box plus one lightweight iPad micro-adjustment panel should be enough for `v1`.
- Prefer a few beautiful interactions over many unfinished controls.
- Let light, scale, and motion communicate value immediately.
- Avoid building a generic 3D editor too early.
- Make AI guidance educational but lightweight; the product should teach users how to communicate better with AI, not become a separate course platform.
- Make beginner controls concrete before they become abstract: show fixtures, colors, and dimmer / intensity changes directly in the stage preview.

## Technical Notes

- SwiftUI can own the control surface and app state.
- RealityKit can own the immersive stage, entities, materials, lights, and effects.
- Shared state should likely live in `AppModel` or dedicated observable models.
- Early prototypes can use bundled Reality Composer Pro assets before introducing persistence.
- If audio-reactive behavior becomes central, isolate that system early.
- OpenAI Responses API is the recommended MVP path for text prompt -> structured lighting configuration -> explanation.
- Use Structured Outputs / JSON schema so the model returns predictable fields that can update the stage schema.
- The demo should use real speech-to-text. Realtime transcription is the preferred path if microphone streaming is stable enough; captured audio plus a transcription call is an acceptable fallback for the same user-facing flow.
- The transcription step should use a lighting vocabulary prompt so mixed Mandarin / English terms such as `wash`, `spot`, `front light`, `background wash`, `dimmer`, `電門`, and `亮度` are less likely to be misread.
- After transcription, the transcript should feed the structured OpenAI Responses API call that returns the cue-based lighting patch and explanation.
- The MVP cross-device workflow needs a shared stage configuration format so iPad micro-adjustments, AI-generated results, and Vision Pro previews all operate on the same data model.
- The `v1` interface should model voice commands as structured operations against the stage schema, even if the UI only exposes a floating conversation box.
- iPad micro-adjustments should also be represented as structured patch operations against the selected cue in the same stage schema.
- Cue changes should animate between fixture-group states, especially intensity and RGB color values, using each cue's transition duration and easing.
- The floating box needs a minimal conversation state: listening, transcribing, interpreting, applying, explaining, and error / retry.
- `v1` should create a 1:1 outdoor stage digital twin rather than trying to cast virtual light onto the real stage.
- The stage configuration should capture a fixed `standardNight` outdoor ambient baseline, not only designed lighting looks. Useful fields may include stage scale, stage orientation, ambient-light level, surrounding-light color temperature, residual sky brightness, and viewing positions, but these should stay fixed for the MVP.
- Indoor window daylight, daytime sun position, house lights, hallway spill, signage, and reflective surfaces should remain future schema candidates rather than `v1` requirements.
- Rigging points, truss alternatives, blocked mount points, and unknown load capacity should remain future schema candidates, but not the first demo requirement.
- Voice editing on Apple Vision Pro should likely modify the same structured stage schema rather than directly manipulating rendered RealityKit entities.
- Targeted AI editing requires stable object, fixture-group, zone, and cue identifiers so voice commands can modify only the intended part of the stage.
- AI edits should ideally be represented as patch operations against the stage schema, with before/after review when the change is significant.
- Full voice-driven generation should create a new schema version or major revision so users can compare it against the previous design instead of losing the prior state.
- Learning feedback should be generated from the same structured stage data so explanations stay tied to real fixtures, zones, cues, and visual changes.

## Decisions

| Date | Decision | Reason |
| --- | --- | --- |
| 2026-05-21 | Use Markdown for project discussion notes. | Easy to read, revise, and keep beside the codebase. |
| 2026-05-21 | Use `AI-assisted stage lighting design first, learning support second` as the current competition framing. | The main product value is generating and revising lighting through AI conversation; education helps users communicate better with AI instead of becoming a separate course. |
| 2026-05-21 | For AI generation, make `v1` generate an editable stage configuration instead of direct lighting-console output. | This keeps the demo ambitious while avoiding premature claims about production-grade fixture control. |
| 2026-05-21 | Include iPad micro-adjustment in the Core Experience. | iPad is useful for precise dimmer and color changes, while full fixture placement, cue editing, and ambient-light switching remain future scope. |
| 2026-05-21 | Voice editing should support both targeted local modifications and explicit full-stage generation. | This preserves approved design choices during small edits while still allowing Vision Pro to generate complete new lighting directions when requested. |
| 2026-05-21 | Add lightweight AI communication guidance as part of generated stage results. | Beginners should learn terms such as fixture names, color, and dimmer / intensity so they can ask AI for more precise lighting designs. |
| 2026-05-25 | Focus `v1` on a 1:1 outdoor stage digital twin. | Outdoor stages are common for student events and can be inspected more completely than indoor venues, making them a clearer first simulation target. |
| 2026-05-25 | AI communication support must cover fixtures, color, and dimmer / intensity. | These basics let beginners describe lighting intent more clearly to AI before moving into advanced cue design or spatial planning. |
| 2026-05-25 | `v1` uses a floating AI conversation box plus iPad micro-controls. | Voice and AI handle generation, while iPad gives stable, precise control for demo-critical fine-tuning. |
| 2026-05-25 | Student-event scenarios should not assume LED screens. | Student activities usually will not have LED screens, so the first demo should use more common conditions such as a nighttime outdoor stage, ambient surroundings, and basic stage fixtures. |
| 2026-05-25 | Teach industry language with plain explanations. | Users should learn terms they can use with AI and lighting people, but each term must be explained in language a beginner can understand. |
| 2026-05-25 | Use OpenAI API for MVP AI generation. | The demo needs structured lighting configuration and short explanations; OpenAI Responses API with structured output fits this better than building a custom AI backend. |
| 2026-05-25 | Use real speech-to-text for `v1`, including mixed Mandarin / English speech. | The Core Experience should feel voice-first, while a transcript -> structured command step keeps bilingual lighting terms controllable before the stage updates. |
| 2026-05-25 | Use typed prompt as the fallback if speech-to-text fails during the demo. | The main experience stays voice-first, but typed input is the fastest and clearest recovery path without needing prerecorded audio or hidden preset transcripts. |
| 2026-05-25 | Use the MVP Lighting Look Schema as the first OpenAI structured output. | The first schema should describe the visible lighting state through a fixed `standardNight` ambient baseline, cues, fixture groups, color, intensity, animated transitions, and explanation instead of modeling full lighting-console engineering data. |
| 2026-05-25 | Use only `standardNight` for the MVP ambient-light model. | The demo should not spend effort on ambient preset switching yet; alternate night conditions can wait until the AI lighting loop is working. |
| 2026-05-25 | Match Swift model names and enum raw values directly to the MVP Lighting Look Schema. | Keeping Swift types aligned with OpenAI JSON avoids extra translation layers between generation, AppModel state, iPad controls, and RealityKit rendering. |
| 2026-05-25 | Limit MVP iPad micro-controls to front light dimmer, background wash color, and reset. | These three controls are enough to demonstrate precise post-AI adjustment without turning the first iPad panel into a larger editor. |
| 2026-05-25 | Make the MVP lighting look cue-based, with two animated cues. | Use only `Opening` and `Highlight` for the demo; iPad micro-controls adjust the selected cue, and moving between cues animates fixture intensity and color instead of jumping instantly. |
| 2026-05-25 | Limit the first fixture vocabulary to `wash`, `spot`, `front light`, and `background wash`. | These four terms are enough for beginners to communicate useful stage-lighting intent with AI while keeping the MVP schema small. |
| 2026-05-25 | Show mic state, transcript, AI understood command, and explanation in the floating AI box. | These four items are the minimum needed to make the voice-first workflow understandable and recoverable without turning the Vision Pro UI into a control panel. |

## Remaining MVP Decisions

- Choose the visual style: believable but simplified, not photorealistic simulation.

## Questions To Ask Lighting Designers

- If `LumaStage` can only solve one source of mismatch first, which is the most painful in real projects?
- Is the biggest gap caused by fixture behavior differences, venue space/material differences, the difference between screen-viewing and standing in the space, or control-data / cue-write differences?

## Questions To Ask Students Or Beginners

- What kind of AI-assisted lighting design or testing would they want to do without renting equipment or borrowing a venue?
- If they had a Vision Pro-based AI lighting-design tool, what would help them communicate better with AI first: fixture names, color concepts, dimmer / intensity, cue testing, or stage-space understanding?
- Would they feel more comfortable starting with voice commands, a few visible buttons, or a mix of both?

## Future Outlook

- Audio reactivity
- Timeline / cue sequencing
- MIDI or controller input
- Multi-user stage sessions
- Recording / exporting performance clips
- Importing custom 3D assets
- Preset marketplace or scene library
- AI-generated stage schema / cue pipeline
- Cross-device iPad-to-Vision-Pro sync
- Future iPad precision editor
- Realtime API speech-to-speech for fully live conversational AI responses
- AI-generated learning feedback
- Indoor venue / window-daylight simulation
- Real-world AR alignment mode
- Rigging, truss, load-capacity, and engineering drawing mismatch
- Lighting-console export
