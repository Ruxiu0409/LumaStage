import Foundation

// MARK: - Dynamic effects engine (the console "Effects" / movement layer)
//
// A continuous, time-driven movement or flash applied to a fixture's beam ON TOP of its cue values —
// the subsystem a real console (grandMA2) calls "Effects": sine pan/tilt sweeps, strobe, colour chase.
// The decidable math lives here (Foundation-only, smoke-tested); `ImmersiveView`'s `LightEffectSystem`
// ticks it every frame and writes the result into the live RealityKit `SpotLight`. Effects modulate ONLY
// beam direction + intensity (never the soft shadow), which is the agreed perf budget for an 8–12 light rig.

/// The kind of movement/flash an effect produces.
enum LightEffectKind: String, Codable, CaseIterable {
    case none
    case panSweep      // side-to-side fan about the base aim
    case tiltSweep     // up/down nod about the base aim
    case circle        // pan + tilt 90° out of phase → the beam traces a circle
    case strobe        // hard on/off flash
    case colorChase    // smooth intensity pulse, phase-staggered so it "runs" across the rig
}

/// A fixture's effect: a kind plus its speed, swing size, and a per-fixture phase offset. Codable + additive
/// so it can ride on a `FixtureGroup` later (AI-authored), but for now it's derived per fixture type by
/// `suggested(for:highEnergy:slot:)` so a rig comes alive without the model authoring parameters.
struct LightEffect: Codable, Equatable {
    var kind: LightEffectKind
    /// Cycles per second.
    var speedHz: Double
    /// Pan/tilt swing amplitude in degrees (sweep + circle). Ignored by strobe / colorChase.
    var sizeDegrees: Double
    /// 0...1 per-fixture phase offset, so a chase/fan ripples across the rig instead of moving in lockstep.
    var phase: Double

    static let none = LightEffect(kind: .none, speedHz: 0, sizeDegrees: 0, phase: 0)

    /// Whether this effect does anything (a `.none`/zero-speed effect is inert).
    var isAnimated: Bool { kind != .none && speedHz > 0 }

    /// True when the effect OWNS the dimmer (strobe/chase drive intensity); false when it only re-aims the
    /// beam (sweeps/circle) and the cue keeps control of intensity.
    var drivesIntensity: Bool { kind == .strobe || kind == .colorChase }

    /// A sensible default movement for a fixture type, scaled by whether the cue reads as high-energy.
    /// Lets a generated/demo rig move without the AI authoring per-fixture effect parameters; `slot`
    /// (the fixture's index in the rig) staggers the per-fixture phase so chases/sweeps ripple across it.
    ///
    /// IMPORTANT: auto-effects no longer DRIVE INTENSITY on the static/wash/strobe fixtures. An
    /// intensity-driving default (`colorChase` on PARs/wash, `strobe` on strobe bars/blinders) made the
    /// pale cyclorama wash pulse every frame on any high-energy cue — it read as flicker ("一閃一閃"), not
    /// design. So those fixtures are now `.none` by default; their movement/strobe is OPT-IN via an
    /// authored `fixture.effect` (e.g. `MusicShowBuilder` authors it explicitly on high-energy sections).
    /// Only the moving head keeps an auto-effect (`panSweep`): it RE-AIMS the beam, never touching
    /// intensity, so it animates without flicker.
    static func suggested(for model: LightingFixtureVisualModel, highEnergy: Bool, slot: Int) -> LightEffect {
        let phase = (Double(slot) * 0.2).truncatingRemainder(dividingBy: 1)
        switch model {
        case .movingHeadBeam:
            return LightEffect(kind: .panSweep, speedHz: highEnergy ? 0.5 : 0.22, sizeDegrees: highEnergy ? 26 : 12, phase: phase)
        case .laser:
            // No movement: the laser's visible aerial beam fan is static geometry the effects system does
            // not animate, so sweeping only its cone spill would look broken (cone swings, fan frozen).
            return .none
        case .ledStrobeBar, .audienceBlinder:
            // Authored-only: an auto-strobe rewrites intensity every frame → flicker on the static rig.
            return .none
        case .ledPar, .washBar, .backgroundBatten:
            // Authored-only: an auto-chase rewrites intensity every frame → the cyc/wash pulses (flicker).
            return .none
        case .frontFresnel, .ledFresnel, .spotBarrel:
            return .none   // steady key/spot light — movement here would just look unstable
        }
    }
}

/// What an effect contributes at a given time: pan/tilt offsets (degrees) ADDED to the fixture's base aim,
/// and a 0...1 multiplier on the cue's intensity (1 = unchanged). The renderer composes these onto the
/// fixture's resting aim + cue lumens.
struct LightEffectOutput: Equatable {
    var panOffsetDegrees: Double
    var tiltOffsetDegrees: Double
    var intensityScale: Double

    static let identity = LightEffectOutput(panOffsetDegrees: 0, tiltOffsetDegrees: 0, intensityScale: 1)
}

/// Pure, deterministic mapping from `(effect, time)` to a movement/intensity offset. The only place the
/// effect math lives, so the smoke tests can pin it without a simulator.
enum LightEffectEngine {
    static func output(_ effect: LightEffect, at time: Double) -> LightEffectOutput {
        guard effect.isAnimated else { return .identity }
        let theta = 2 * Double.pi * (effect.speedHz * time + effect.phase)
        switch effect.kind {
        case .none:
            return .identity
        case .panSweep:
            return LightEffectOutput(panOffsetDegrees: effect.sizeDegrees * sin(theta), tiltOffsetDegrees: 0, intensityScale: 1)
        case .tiltSweep:
            return LightEffectOutput(panOffsetDegrees: 0, tiltOffsetDegrees: effect.sizeDegrees * sin(theta), intensityScale: 1)
        case .circle:
            return LightEffectOutput(panOffsetDegrees: effect.sizeDegrees * sin(theta), tiltOffsetDegrees: effect.sizeDegrees * cos(theta), intensityScale: 1)
        case .strobe:
            return LightEffectOutput(panOffsetDegrees: 0, tiltOffsetDegrees: 0, intensityScale: sin(theta) >= 0 ? 1 : 0)
        case .colorChase:
            return LightEffectOutput(panOffsetDegrees: 0, tiltOffsetDegrees: 0, intensityScale: (sin(theta) + 1) / 2)
        }
    }
}

/// The shared gate the renderer (`ImmersiveView.apply`) and the in-app effect readout (`RelightDebugSnapshot`)
/// both use, so the debug panel can't drift from what actually animates. A cue's rig "comes alive" (its
/// fixtures run their suggested effects) when the cue reads as high-energy — its fixtures' average intensity
/// is at or above the threshold. This is what makes the show's arc (calm Opening → energetic Finale) drive
/// the movement, with no separate authoring.
enum LightEffectPlan {
    static let highEnergyThreshold = 0.6

    static func averageIntensity(of fixtures: [FixtureGroup]) -> Double {
        guard !fixtures.isEmpty else { return 0 }
        return fixtures.reduce(0.0) { $0 + $1.intensity } / Double(fixtures.count)
    }

    static func isHighEnergy(_ cue: LightingCue) -> Bool {
        averageIntensity(of: cue.fixtureGroups) >= highEnergyThreshold
    }

    /// The effect each fixture in the cue runs (in rig order) under this cue's energy — the single source
    /// the renderer and the debug readout share, so they always agree.
    static func effects(for cue: LightingCue) -> [LightEffect] {
        let highEnergy = isHighEnergy(cue)
        return cue.fixtureGroups.enumerated().map { index, fixture in
            // AI-authored effect wins; otherwise fall back to the deterministic per-type default so a
            // rig with no authored movement keeps its existing behaviour (no regression).
            fixture.effect ?? LightEffect.suggested(for: fixture.renderModel, highEnergy: highEnergy, slot: index)
        }
    }
}
