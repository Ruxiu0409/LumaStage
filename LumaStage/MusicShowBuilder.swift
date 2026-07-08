import Foundation

// MARK: - Music show builder (SPEC 05 P1, owner A2 — Foundation-only, smoke-tested)
//
// The DETERMINISTIC, AI-free backbone: a `ShowPlan` (one brief per section) becomes a renderable
// multi-cue `LightingLook`. Each cue gets a palette + intensity + dynamic effects chosen from the
// section's (keyMode, energy): major → warm/white-ish, minor → cool/blue-violet; high-energy cues
// saturate and give movers/strobes a `LightEffect`; calm cues stay steady. The rig is a fixed,
// left/right-symmetric set (paired fixtures, never a lone laser — the rig-symmetry convention), sized
// to `maxFixtures` (default 8). Everything goes through `LightingLookDraft.makeValidatedLook(...)` →
// `validate()` so the result is guaranteed renderable, then `rig.enforce(on:)` clamps it to the locked
// inventory. Pure so the smoke tests pin it without a simulator (this is the show that runs even when
// the model/analysis is unavailable).

enum MusicShowBuilder {
    /// Builds a multi-cue `LightingLook` from a `ShowPlan` — one cue per `CueBrief` — using a deterministic
    /// symmetric rig. Validated, then clamped to `rig`.
    static func buildLook(plan: ShowPlan, rig: RigConstraint, lookName: String, maxFixtures: Int = 8) throws -> LightingLook {
        let rigSpecs = symmetricRig(maxFixtures: maxFixtures)

        let cues: [LightingLookDraft.Cue] = plan.cues.enumerated().map { index, brief in
            LightingLookDraft.Cue(
                id: "cue_music_\(index)",
                name: brief.name,
                fixtures: rigSpecs.enumerated().map { slot, spec in
                    fixture(for: spec, brief: brief, slot: slot)
                }
            )
        }

        let look = try LightingLookDraft.makeValidatedLook(
            lookName: lookName,
            mood: mood(for: plan),
            cues: cues,
            explanationTerm: "音樂同步演出",
            explanationPlainText: "依歌曲段落、調性與能量自動生成的多場景演出：主歌沉穩、副歌爆發，燈光隨段落自動切換。",
            explanationActionSummary: "已依音樂分析生成 \(cues.count) 個場景的整場演出。",
            explanationRationale: "大調段落偏暖白、小調偏冷藍紫；高能量段落提升飽和與亮度並讓搖頭燈／頻閃燈動起來，低能量段落維持穩定主光，建立整場的張力起伏。"
        )

        return rig.enforce(on: look)
    }

    // MARK: - Rig

    /// One fixture in the deterministic rig.
    private struct RigSpec {
        var id: String
        var name: String
        var model: LightingFixtureVisualModel
        var zone: StageZone
    }

    /// A left/right-symmetric rig, largest meaningful set first, trimmed to `maxFixtures`. Listed so that
    /// truncating the tail still leaves symmetric pairs at the front (key pair → back zone → PARs).
    ///
    /// CRITICAL: members SHARING A ZONE must be listed PALINDROMICALLY (mirror partners at the ends),
    /// because `RigPlacement` spreads a zone's fixtures across slots in list order, so slot→X is
    /// `slot/(count-1)*2-1`. The `.stageBack` zone here is `laser_l · mh_l · mh_r · laser_r`, so the
    /// lasers land at slots 0 and 3 → x = -1 (far left) and +1 (far right), the proven `showcaseDemo()`
    /// pattern. A naive `…mh_l, mh_r, laser_l, laser_r` order would put BOTH lasers in the right half.
    /// Any `prefix(count)` truncation MUST keep each zone's members palindromic — never cut one of a
    /// mirror pair; the even-count clamp below trims whole pairs from the tail.
    private static func symmetricRig(maxFixtures: Int) -> [RigSpec] {
        let full: [RigSpec] = [
            RigSpec(id: "key_l", name: "主光柔光燈（左）", model: .frontFresnel, zone: .stageFront),
            RigSpec(id: "key_r", name: "主光柔光燈（右）", model: .frontFresnel, zone: .stageFront),
            // Upstage truss, palindromic: laser · moving head · moving head · laser → lasers at the ends.
            RigSpec(id: "laser_l", name: "雷射燈（左）", model: .laser, zone: .stageBack),
            RigSpec(id: "mh_l", name: "搖頭光束燈（左）", model: .movingHeadBeam, zone: .stageBack),
            RigSpec(id: "mh_r", name: "搖頭光束燈（右）", model: .movingHeadBeam, zone: .stageBack),
            RigSpec(id: "laser_r", name: "雷射燈（右）", model: .laser, zone: .stageBack),
            RigSpec(id: "par_l", name: "LED PAR（左）", model: .ledPar, zone: .stageLeft),
            RigSpec(id: "par_r", name: "LED PAR（右）", model: .ledPar, zone: .stageRight)
        ]
        // Keep an even count so no fixture (especially the laser) is left without a mirror partner.
        // NOTE: trimming the tail here can split a zone's palindrome (e.g. count 6 keeps laser_l · mh_l ·
        // mh_r but drops laser_r). The default rig (maxFixtures 8) keeps the full palindromic back zone,
        // so both lasers stay mirrored. If a smaller rig must be produced, trim in whole mirror pairs.
        var count = max(2, min(maxFixtures, full.count))
        if count % 2 != 0 { count -= 1 }
        return Array(full.prefix(count))
    }

    // MARK: - Per-cue fixture state

    private static func fixture(for spec: RigSpec, brief: CueBrief, slot: Int) -> LightingLookDraft.Fixture {
        let role = spec.model.derivedRole
        let (hex, intensity) = lookValues(for: spec, brief: brief)
        // High-energy sections come alive with EXPLICITLY AUTHORED effects. We author them here (rather
        // than relying on `LightEffect.suggested`) because `suggested` deliberately returns `.none` for
        // the static/wash/strobe fixtures now (an auto intensity-driving effect read as flicker on the
        // 1:1 rig — see BUG 4 in LightEffect.suggested). In the music show the strobe/chase IS the design,
        // and `MusicBeatSync` locks these to the beat, so authoring them here keeps the show dynamic.
        let effect = brief.highEnergy ? highEnergyEffect(for: spec.model, slot: slot) : LightEffect.none

        return LightingLookDraft.Fixture(
            id: spec.id,
            name: spec.name,
            role: role,
            zone: spec.zone,
            enabled: true,
            intensity: intensity,
            colorHex: hex,
            model: spec.model,
            beamAngleDegrees: spec.model.defaultBeamDegrees,
            // A `.none` effect is inert; store it only when animated so calm cues read as steady.
            effect: effect.isAnimated ? effect : nil
        )
    }

    /// The explicit high-energy effect the music show authors per fixture model. Strobe bars / blinders
    /// punch, PARs / wash chase colour, movers sweep — driven on the beat by `MusicBeatSync`. The static
    /// key/spot fixtures stay steady. `slot` staggers the phase so chases ripple across the rig.
    private static func highEnergyEffect(for model: LightingFixtureVisualModel, slot: Int) -> LightEffect {
        let phase = (Double(slot) * 0.2).truncatingRemainder(dividingBy: 1)
        switch model {
        case .movingHeadBeam:
            // High-energy: the prominent centre beams hard-strobe on the beat (drivesIntensity → the visible
            // cone flashes via LightEffectSystem's OpacityComponent drive). Low-energy cues author no effect,
            // so movers fall back to a gentle panSweep (LightEffect.suggested) — verse sweeps, chorus flashes.
            return LightEffect(kind: .strobe, speedHz: 4, sizeDegrees: 0, phase: phase)
        case .ledStrobeBar:
            return LightEffect(kind: .strobe, speedHz: 8, sizeDegrees: 0, phase: phase)
        case .audienceBlinder:
            return LightEffect(kind: .strobe, speedHz: 4, sizeDegrees: 0, phase: phase)
        case .ledPar, .washBar, .backgroundBatten:
            return LightEffect(kind: .colorChase, speedHz: 0.7, sizeDegrees: 0, phase: phase)
        case .laser, .frontFresnel, .ledFresnel, .spotBarrel:
            return .none
        }
    }

    /// The (hex, intensity) for one fixture in one cue, from the brief's energy + keyMode and the fixture's role.
    private static func lookValues(for spec: RigSpec, brief: CueBrief) -> (hex: String, intensity: Double) {
        let role = spec.model.derivedRole
        let intensity = min(max(brief.suggestedIntensity, 0), 1)

        // Key/front light: keep performers visible — warm for major, cooler-neutral for minor.
        if role == .frontLight {
            let hex = brief.keyMode == .minor ? "#DCE4FF" : "#FFE6C2"
            return (hex, intensity)
        }

        // Everything else (movers/PARs/lasers/background): palette driven by key mode + energy.
        let hex = accentHex(keyMode: brief.keyMode, energy: brief.energy, slot: spec.id)
        return (hex, intensity)
    }

    /// Accent colour for non-front fixtures. Major → warm/amber-white; minor → cool blue-violet. Higher
    /// energy pushes toward saturated, slightly varied hues; low energy stays muted. Slot id adds a small
    /// L/R hue split so a symmetric pair isn't monotone.
    private static func accentHex(keyMode: MusicKeyMode, energy: Double, slot: String) -> String {
        let isLeft = slot.hasSuffix("_l")
        switch keyMode {
        case .major:
            if energy >= LightEffectPlan.highEnergyThreshold {
                return isLeft ? "#FF7A1A" : "#FFC21A"   // saturated warm amber/gold
            }
            return isLeft ? "#FFD9A8" : "#FFE9C8"       // soft warm white
        case .minor:
            if energy >= LightEffectPlan.highEnergyThreshold {
                return isLeft ? "#2E3CFF" : "#8A2BE2"   // saturated blue / violet
            }
            return isLeft ? "#3E5AA8" : "#5A4FA8"       // muted cool blue-violet
        case .unknown:
            if energy >= LightEffectPlan.highEnergyThreshold {
                return isLeft ? "#16C2C2" : "#33E07A"   // neutral high-energy teal/green
            }
            return isLeft ? "#7FA0C0" : "#8FB0A0"       // muted neutral
        }
    }

    private static func mood(for plan: ShowPlan) -> String {
        let peak = plan.cues.map(\.energy).max() ?? 0.5
        if peak >= 0.75 { return "高能量、隨拍律動、整場演出" }
        if peak >= LightEffectPlan.highEnergyThreshold { return "層次分明、段落起伏、整場演出" }
        return "沉穩、聚焦、整場演出"
    }
}
