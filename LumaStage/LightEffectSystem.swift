import Foundation
#if os(visionOS)
import RealityKit
import simd

// MARK: - Dynamic effects: per-frame RealityKit layer
//
// The runtime half of the effects engine. `LightEffect`/`LightEffectEngine` (Foundation, smoke-tested)
// own the math; this file ticks it every frame and writes the result into the live `SpotLight`. Each
// animated spotlight carries a `LightEffectComponent`; `LightEffectSystem` re-aims the beam (sweeps /
// circle) around its RESTING aim and drives the dimmer (strobe / colour chase). It deliberately touches
// only orientation + intensity — never the soft shadow — which is the agreed perf budget for an 8–12
// light rig (re-rendering shadows every frame would be the expensive part).

/// Per-spotlight state the effects system reads each frame: the effect to run, the fixture's RESTING aim
/// (so sweeps modulate around it rather than around a drifting live aim), and the cue's resolved lumens
/// (so strobe/chase scale the dimmer). `ImmersiveView` captures `baseAim` when the spotlight is built and
/// refreshes `effect` + `baseLumens` per cue in `apply`.
struct LightEffectComponent: Component {
    var effect: LightEffect = .none
    var baseAim: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    var baseLumens: Float = 0
    /// Name of the fixture's VISIBLE aerial beam container (`spotbeam_<id>` or `laser_<id>`), a sibling of
    /// this spot under the `rig`. `LightEffectSystem` pulses its `OpacityComponent` for intensity-driving
    /// effects (strobe/chase) so the flash reads on the cone, not just on the (invisible) SpotLight lumens.
    var beamEntityName: String? = nil
}

/// Ticks every fixture's `LightEffect` each frame and writes it into the `SpotLight`.
final class LightEffectSystem: System {
    private static let query = EntityQuery(where: .has(LightEffectComponent.self))
    private var time: TimeInterval = 0

    required init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        // Free-run time keeps advancing every frame regardless of music, so disabling music sync never
        // regresses (effects fall straight back onto their authored per-frame motion).
        time += context.deltaTime

        // SPEC 05 owner C: beat-lock to the music clock when active. Sampled ONCE per frame off the
        // render-thread-safe shared source (lock-guarded snapshot). A System isn't a SwiftUI body, so the
        // Observation footgun doesn't apply — we read `.shared` directly. `nil` ⇒ no music ⇒ free-run.
        let beatSnapshot = MusicSyncClockSource.shared.snapshot()

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let component = entity.components[LightEffectComponent.self],
                  let spot = entity as? SpotLight else { continue }

            let out: LightEffectOutput
            if let beatSnapshot {
                // Music sync on: same effect, but fired on the beat grid instead of wall-clock seconds.
                out = MusicBeatSync.output(component.effect, clock: beatSnapshot.clock, at: beatSnapshot.time)
            } else {
                // No music: the effect free-runs on its authored `speedHz`.
                out = LightEffectEngine.output(component.effect, at: time)
            }

            // Re-aim around the resting direction. Offsets are zero for a steady/none effect, so a calm
            // cue holds the beam at rest (and a cue change back to steady eases it home next frame).
            let aim = Self.aim(base: component.baseAim,
                               panDegrees: out.panOffsetDegrees,
                               tiltDegrees: out.tiltOffsetDegrees)
            spot.orientation = Self.lookOrientation(forward: aim)

            // Strobe / chase own the dimmer; sweeps leave intensity to the cue's cross-fade.
            if component.effect.drivesIntensity {
                spot.light.intensity = component.baseLumens * Float(out.intensityScale)
            }

            // The SpotLight above lights SURFACES; the visible aerial cone is an `UnlitMaterial` that doesn't
            // react to it, so a beat-locked strobe/chase wouldn't read in the dark venue unless we also
            // modulate the cone. Drive the sibling beam container's `OpacityComponent` (hierarchical → covers
            // the sheath / laser layers) so the flash is visible. Non-intensity effects (sweeps) leave the
            // cone at its per-cue opacity, which `updateSpotBeam` resets to 1 on each cue.
            if component.effect.drivesIntensity,
               let beamName = component.beamEntityName,
               let beam = spot.parent?.findEntity(named: beamName) {
                beam.components.set(OpacityComponent(opacity: Float(out.intensityScale)))
            }
        }
    }

    /// Registers the component + system once (RealityKit needs both registered before first use). Safe to
    /// call on every scene build — guarded so it only runs once per process.
    static func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true
        LightEffectComponent.registerComponent()
        LightEffectSystem.registerSystem()
    }
    private static var isRegistered = false

    /// Rotates the resting aim by `pan` (about world up) then `tilt` (about the beam's right axis).
    /// Delegates to the Foundation-only, smoke-tested `FixtureAimMath.apply` so the forward rotation and
    /// its inverse (used by the tabletop "aim at stage centre" button) can never drift apart.
    static func aim(base: SIMD3<Float>, panDegrees: Double, tiltDegrees: Double) -> SIMD3<Float> {
        FixtureAimMath.apply(base: base, panDegrees: panDegrees, tiltDegrees: tiltDegrees)
    }

    /// Orientation that aims a spotlight's local -Z along `forward` (matches `ImmersiveView`'s rig math).
    static func lookOrientation(forward: SIMD3<Float>) -> simd_quatf {
        let from = SIMD3<Float>(0, 0, -1)
        let to = simd_normalize(forward)
        let dot = min(max(simd_dot(from, to), -1), 1)
        if dot > 0.9999 { return simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, -1)) }
        if dot < -0.9999 { return simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0)) }
        return simd_quatf(angle: acos(dot), axis: simd_normalize(simd_cross(from, to)))
    }
}
#endif
