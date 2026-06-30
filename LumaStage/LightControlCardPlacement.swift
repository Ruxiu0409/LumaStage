//
//  LightControlCardPlacement.swift
//  LumaStage
//
//  Pure placement math for the per-light manual control card. Foundation-only so it can be
//  smoke-tested headlessly — the RealityKit view (`ImmersiveView`) is a thin consumer that reads
//  the selected light's world position and asks this enum where to park the card.
//

import Foundation
import simd

/// Decides where the manual control card (`SelectedLightControlView` attachment) should appear when a
/// light is selected. The rule: pull the card out of the (possibly 5m-high, several-metres-deep) light
/// toward the viewer so it lands within arm's reach, clamp its height to a comfortable band, and nudge
/// it sideways so it doesn't sit dead-centre over the beam the user is looking at.
///
/// Pure + deterministic (no RealityKit types) so `LumaStageCoreSmokeTests` can pin the clamp/lerp.
enum LightControlCardPlacement {
    // Coefficients are defaulted params, kept here as the single tuning surface — TUNE ON DEVICE: the
    // right pull/height/side-offset is a hand-feel call once it's in the headset.
    //
    // - `pullToViewer`: horizontal (x,z) interpolation fraction from the light toward the viewer. 0 = at
    //   the light, 1 = at the viewer. 0.4 keeps the card visually associated with its light while bringing
    //   it close enough to reach.
    // - `minY`/`maxY`: the reachable height band the card's y is clamped into, so a truss-hung light at
    //   y≈5 doesn't float its controls up out of reach, and a low FOH light doesn't sit on the floor.
    // - `sideOffset`: lateral (+x) shift so the card sits beside the beam rather than blocking it.
    static func position(
        lightWorld: SIMD3<Float>,
        viewer: SIMD3<Float>,
        pullToViewer: Float = 0.4,
        minY: Float = 0.9,
        maxY: Float = 1.6,
        sideOffset: Float = 0.18
    ) -> SIMD3<Float> {
        // Horizontal (x,z) lerp from the light toward the viewer — bring the card within reach while
        // keeping it roughly between the user and the light they're looking at.
        let pulledX = lightWorld.x + (viewer.x - lightWorld.x) * pullToViewer
        let pulledZ = lightWorld.z + (viewer.z - lightWorld.z) * pullToViewer

        // Clamp the height into the reachable band (a 5m-high light's card never floats up there).
        let clampedY = min(max(lightWorld.y, minY), maxY)

        // Nudge sideways so the card doesn't sit dead-centre over the beam.
        return SIMD3<Float>(pulledX + sideOffset, clampedY, pulledZ)
    }
}
