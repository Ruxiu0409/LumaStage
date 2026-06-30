import Foundation

// MARK: - Music beat sync (SPEC 05, owner A — Foundation-only, smoke-tested)
//
// A pure, deterministic beat grid plus a beat-locked re-mapping of the A1 effect engine. When music sync is
// on, effects stop free-running on their own `speedHz` and instead lock to this beat grid so flashes/chases
// land ON the beat. The platform `MusicSyncEngine` (owner B) supplies the `MusicBeatClock` + playback time;
// `LightEffectSystem` (owner C) feeds them here. All math here is pure (no Date/now) so the smoke tests pin
// it without a simulator.

/// A tempo grid: a fixed BPM and the time of the first downbeat. Everything else (which beat, where inside a
/// beat) is derived, so it stays trivially testable.
struct MusicBeatClock: Equatable {
    /// Beats per minute, e.g. 128. Must be > 0 to be meaningful.
    var bpm: Double
    /// Time (seconds, in the same clock as the times passed to the query methods) of the first beat (beat 0).
    var startOffset: Double

    /// Beats per second.
    var beatHz: Double { bpm / 60 }

    /// Position within the current beat, in `0..<1` (0 exactly on each beat boundary, approaching 1 just
    /// before the next beat). Guards `bpm <= 0` by returning 0.
    func beatPhase(at time: Double) -> Double {
        guard bpm > 0 else { return 0 }
        let beats = (time - startOffset) * beatHz
        // Fractional part, normalised into [0, 1) even for negative times before `startOffset`.
        var phase = beats - floor(beats)
        // Guard against tiny FP drift pushing phase to exactly 1.
        if phase >= 1 { phase -= 1 }
        if phase < 0 { phase += 1 }
        return phase
    }

    /// Which beat `time` falls in, 0-based. Negative before `startOffset`. Guards `bpm <= 0` by returning 0.
    func beatIndex(at time: Double) -> Int {
        guard bpm > 0 else { return 0 }
        return Int(floor((time - startOffset) * beatHz))
    }
}

/// Beat-locked counterpart to `LightEffectEngine.output`. Same `(effect) -> LightEffectOutput` contract, but
/// the time axis is the beat grid instead of wall-clock seconds, so effects fire on tempo regardless of their
/// authored `speedHz`. Pure + deterministic (no Date/now).
enum MusicBeatSync {
    /// Fraction of each beat the strobe stays lit (a hard punch on the leading edge of the beat).
    static let strobeDutyCycle = 0.30

    static func output(_ effect: LightEffect, clock: MusicBeatClock, at time: Double) -> LightEffectOutput {
        guard effect.isAnimated, clock.bpm > 0 else { return .identity }

        let phase = clock.beatPhase(at: time)            // 0..<1 within the current beat
        // A continuous beat coordinate: beatIndex + beatPhase increases monotonically and continuously with
        // `time` (it equals (time - startOffset) * beatHz), so any motion driven off it never jumps across a
        // beat boundary.
        let beatTime = Double(clock.beatIndex(at: time)) + phase

        switch effect.kind {
        case .none:
            return .identity

        case .strobe:
            // Hard flash on the LEADING fraction of each beat → the rig punches ON the beat. The per-fixture
            // `phase` (0..1) subtly offsets WHICH beat-fraction it fires, kept small so all fixtures still
            // read as hitting the same beat. Wrap the shifted phase into [0,1) for a clean window test.
            let shift = effect.phase * strobeDutyCycle           // subtle stagger, within the lit window
            var p = phase - shift
            if p < 0 { p += 1 }
            let lit = p < strobeDutyCycle
            return LightEffectOutput(panOffsetDegrees: 0, tiltOffsetDegrees: 0, intensityScale: lit ? 1 : 0)

        case .colorChase:
            // A smooth once-per-beat pulse (raised cosine of beatPhase): 0 at the beat boundary, rising to 1
            // at mid-beat and back to 0 — staggered by the fixture's `phase` so the pulse "runs" across the
            // rig within each beat. Stays in 0...1.
            let staggered = phase - effect.phase
            let wrapped = staggered - floor(staggered)           // back into [0,1)
            let pulse = (1 - cos(2 * Double.pi * wrapped)) / 2   // raised cosine, 0 at edges, 1 mid-beat
            return LightEffectOutput(panOffsetDegrees: 0, tiltOffsetDegrees: 0, intensityScale: pulse)

        case .panSweep, .tiltSweep, .circle:
            // Delegate to the A1 engine but feed it a beat-based time so the motion rides tempo. We map ONE
            // full `speedHz` cycle per beat-unit by handing the engine `beatTime` with a unit-rate effect
            // (speedHz = 1): the engine computes 2π·(1·beatTime + phase), and since `beatTime` is continuous
            // and monotonic in real time, the sweep is smooth and never jumps at a beat boundary.
            var beatLocked = effect
            beatLocked.speedHz = 1
            return LightEffectEngine.output(beatLocked, at: beatTime)
        }
    }
}
