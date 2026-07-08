import Foundation

#if os(visionOS)
import RealityKit
import UIKit
import simd

/// Builds inspect-ready RealityKit fixture models for the spatial observatory volume.
///
/// This is the RealityKit counterpart of the SceneKit `LightingFixtureSceneFactory` used for the
/// flat catalog thumbnails: it rebuilds the same procedural geometry (boxes, cylinders, spheres,
/// rings) as `ModelEntity`s so the fixture can float in a volumetric window and be observed from
/// any angle. Each model is built once, cached, and handed out as a `clone(recursive:)` so cue
/// swaps stay cheap.
enum FixtureRealityModel {
    private static var cache: [LightingFixtureVisualModel: Entity] = [:]

    /// A centered, uniformly scaled fixture entity that fits inside the observatory volume.
    /// Returns a clone so callers can own and re-parent it freely.
    static func makeEntity(for model: LightingFixtureVisualModel) -> Entity {
        if let template = cache[model] {
            return template.clone(recursive: true)
        }
        let template = buildTemplate(for: model)
        cache[model] = template
        return template.clone(recursive: true)
    }

    /// A stage-scale clone of the fixture-type model, sized to ~`targetHeight` metres (scene units) and
    /// aimed so its front points along `aim`. Reuses the cached observatory geometry.
    ///
    /// The observatory model is built front-facing along +Z and (for floor types) standing on a stand
    /// whose base sits at the model origin; this clone is recentered on its own visual bounds, uniformly
    /// scaled so its tallest axis is `targetHeight`, then rotated so that local +Z lines up with `aim`.
    /// The returned container's transform is identity at the origin — the caller sets its position.
    static func makeStageFixture(for model: LightingFixtureVisualModel, targetHeight: Float, aim: SIMD3<Float>) -> Entity {
        // Reuse the same procedural geometry as the observatory, but without the thumbnail's three-quarter
        // tilt — the stage version is driven entirely by `aim`. Build (or fetch) a centered, unit-untilted
        // template, then scale + orient a fresh clone.
        let centered = centeredTemplate(for: model).clone(recursive: true)

        let bounds = centered.visualBounds(relativeTo: nil)
        let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let scale = maxExtent > 0.0001 ? targetHeight / maxExtent : 1

        let container = Entity()
        container.addChild(centered)
        container.scale = SIMD3<Float>(repeating: scale)
        // Rotate the model's front (+Z) to point along `aim`. If `aim` is degenerate, leave facing +Z.
        let target = simd_length(aim) > 0.0001 ? simd_normalize(aim) : SIMD3<Float>(0, 0, 1)
        container.orientation = rotation(from: SIMD3<Float>(0, 0, 1), to: target)
        return container
    }

    /// A cached, recentered (but un-tilted, unscaled) template used by `makeStageFixture`. Distinct from
    /// the observatory cache because that one bakes the three-quarter view + fit scale into its pivot.
    private static var stageCache: [LightingFixtureVisualModel: Entity] = [:]

    private static func centeredTemplate(for model: LightingFixtureVisualModel) -> Entity {
        if let template = stageCache[model] {
            return template
        }
        let assembly = Entity()
        switch model {
        case .ledStrobeBar: buildLedStrobeBar(into: assembly)
        case .movingHeadBeam: buildMovingHeadBeam(into: assembly)
        case .ledPar: buildLedPar(into: assembly)
        case .audienceBlinder: buildAudienceBlinder(into: assembly)
        case .ledFresnel: buildLedFresnel(into: assembly)
        case .laser: buildLaser(into: assembly)
        }
        let bounds = assembly.visualBounds(relativeTo: nil)
        assembly.position = -bounds.center

        let pivot = Entity()
        pivot.addChild(assembly)
        stageCache[model] = pivot
        return pivot
    }

    /// Shortest-arc quaternion rotating `source` onto `target` (both treated as directions). Mirrors the
    /// `orientation(from:to:)` helper in `ImmersiveView`, kept local so this file stays self-contained.
    private static func rotation(from source: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let from = simd_normalize(source)
        let to = simd_normalize(target)
        let dot = min(max(simd_dot(from, to), -1), 1)
        if dot > 0.9999 {
            return simd_quatf(angle: 0, axis: from)
        }
        if dot < -0.9999 {
            // Antiparallel: pick any axis perpendicular to `from`.
            let axis = abs(from.x) < 0.9 ? simd_cross(from, SIMD3<Float>(1, 0, 0)) : simd_cross(from, SIMD3<Float>(0, 1, 0))
            return simd_quatf(angle: .pi, axis: simd_normalize(axis))
        }
        return simd_quatf(angle: acos(dot), axis: simd_normalize(simd_cross(from, to)))
    }

    private static func buildTemplate(for model: LightingFixtureVisualModel) -> Entity {
        let assembly = Entity()
        switch model {
        case .ledStrobeBar: buildLedStrobeBar(into: assembly)
        case .movingHeadBeam: buildMovingHeadBeam(into: assembly)
        case .ledPar: buildLedPar(into: assembly)
        case .audienceBlinder: buildAudienceBlinder(into: assembly)
        case .ledFresnel: buildLedFresnel(into: assembly)
        case .laser: buildLaser(into: assembly)
        }

        // Recenter on the model's visual bounds, then uniformly scale the longest axis to fit the
        // volume with margin. A slight yaw/pitch matches the SceneKit thumbnail's three-quarter view.
        let bounds = assembly.visualBounds(relativeTo: nil)
        let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        // Longest-axis target size (metres) inside the 0.7m volume. Kept comfortably below the volume so
        // the fixture opens compact rather than filling the window; the user can pinch to scale it up.
        let fitTarget: Float = 0.40
        let scale = maxExtent > 0.0001 ? fitTarget / maxExtent : 1
        assembly.position = -bounds.center

        let pivot = Entity()
        pivot.addChild(assembly)
        pivot.scale = SIMD3<Float>(repeating: scale)
        pivot.orientation = eulerQuat(x: -0.12, y: -0.44)
        return pivot
    }

    // MARK: - Real-world product fixtures

    private static func buildLedStrobeBar(into root: Entity) {
        // Long pixel/strobe bar, horizontal along X, standing on small end feet.
        root.addChild(box(1.84, 0.20, 0.20, .blackBody, 0.6, at: [0, 0.42, 0]))
        root.addChild(box(1.78, 0.13, 0.05, .graphite, 0.5, at: [0, 0.42, 0.11]))

        // Rainbow LED pixel row across the front.
        let rainbow: [FixturePaletteColor] = [.redLens, .yellowLens, .greenLens, .cyanLens, .blueLens, .magentaLens]
        let pixelCount = 16
        for index in 0..<pixelCount {
            let x = -0.80 + Float(index) * (1.60 / Float(pixelCount - 1))
            root.addChild(box(0.07, 0.10, 0.02, .blackBody, 0.55, at: [x, 0.42, 0.135]))
            root.addChild(box(0.052, 0.082, 0.02, rainbow[index % rainbow.count], 0.05, alpha: 0.9, at: [x, 0.42, 0.15]))
        }

        // A few bright white strobe cells along the bottom edge.
        for x in [-0.55, 0.0, 0.55] as [Float] {
            root.addChild(box(0.12, 0.05, 0.02, .coolWhite, 0.04, alpha: 0.95, at: [x, 0.32, 0.135]))
        }

        // End brackets + small feet so it reads as standing on the deck.
        for x in [-0.92, 0.92] as [Float] {
            root.addChild(box(0.08, 0.30, 0.24, .darkMetal, 0.66, at: [x, 0.40, 0]))
            root.addChild(box(0.22, 0.04, 0.34, .darkMetal, 0.7, at: [x, 0.245, 0]))
            addYokeKnob(to: root, at: [x, 0.40, 0.0])
        }

        addCoolingSlots(to: root, originX: -0.7, y: 0.50, z: -0.105, count: 9, vertical: true)
        addCable(to: root, fromX: 0.86, y: 0.30, z: -0.10)
    }

    private static func buildMovingHeadBeam(into root: Entity) {
        // Heavy base — the moving head stands on it, no separate stand.
        root.addChild(box(0.66, 0.20, 0.60, .blackBody, 0.6, at: [0, -0.18, 0]))
        root.addChild(box(0.56, 0.08, 0.52, .graphite, 0.5, at: [0, -0.04, 0]))
        root.addChild(box(0.18, 0.07, 0.02, .cyanLens, 0.05, alpha: 0.92, at: [-0.18, -0.04, 0.27]))

        // Two yoke arms.
        for x in [-0.34, 0.34] as [Float] {
            root.addChild(box(0.12, 0.62, 0.26, .darkMetal, 0.62, at: [x, 0.22, 0]))
        }
        addYokeKnob(to: root, at: [-0.30, 0.40, 0])
        addYokeKnob(to: root, at: [0.30, 0.40, 0])

        // Head — a cylinder whose axis points along Z so the lens faces forward (+Z).
        let head = cylinder(0.26, 0.56, .blackBody, 0.62, at: [0, 0.46, 0.02])
        head.orientation = eulerQuat(x: .pi / 2)
        root.addChild(head)

        let rim = cylinder(0.275, 0.07, .darkMetal, 0.7, at: [0, 0.46, 0.27])
        rim.orientation = eulerQuat(x: .pi / 2)
        root.addChild(rim)

        let lens = cylinder(0.205, 0.04, .coolWhite, 0.05, alpha: 0.82, at: [0, 0.46, 0.30])
        lens.orientation = eulerQuat(x: .pi / 2)
        root.addChild(lens)
        addRing(to: root, ringRadius: 0.225, pipeRadius: 0.007, at: [0, 0.46, 0.31], faceZ: true)

        let rearCap = cylinder(0.245, 0.07, .graphite, 0.66, at: [0, 0.46, -0.26])
        rearCap.orientation = eulerQuat(x: .pi / 2)
        root.addChild(rearCap)

        addCoolingSlots(to: root, originX: -0.13, y: 0.62, z: -0.05, count: 5, vertical: false)
    }

    private static func buildLedPar(into root: Entity) {
        addStand(to: root)

        root.addChild(box(0.86, 0.07, 0.12, .blackBody, 0.65, at: [0, 0.54, 0]))

        for x in [-0.40, 0.40] as [Float] {
            root.addChild(box(0.07, 0.50, 0.08, .blackBody, 0.65, at: [x, 0.28, 0]))
        }
        addYokeKnob(to: root, at: [-0.44, 0.30, 0])
        addYokeKnob(to: root, at: [0.44, 0.30, 0])

        // Round PAR can — axis along Z so the lens face points forward.
        let can = cylinder(0.34, 0.30, .blackBody, 0.6, at: [0, 0.22, 0])
        can.orientation = eulerQuat(x: .pi / 2)
        root.addChild(can)

        let rearFins = cylinder(0.345, 0.10, .graphite, 0.66, at: [0, 0.22, -0.16])
        rearFins.orientation = eulerQuat(x: .pi / 2)
        root.addChild(rearFins)

        let bezel = cylinder(0.34, 0.03, .darkMetal, 0.6, at: [0, 0.22, 0.155])
        bezel.orientation = eulerQuat(x: .pi / 2)
        root.addChild(bezel)
        addRing(to: root, ringRadius: 0.32, pipeRadius: 0.007, at: [0, 0.22, 0.17], faceZ: true)

        // Dense grid of small LED cells filling the circular face.
        let ledColors: [FixturePaletteColor] = [.coolWhite, .coolWhite, .coolWhite, .redLens, .greenLens, .blueLens]
        var colorIndex = 0
        let step: Float = 0.088
        var gridY: Float = -0.26
        while gridY <= 0.26 {
            var gridX: Float = -0.26
            while gridX <= 0.26 {
                if (gridX * gridX + gridY * gridY).squareRoot() <= 0.27 {
                    let led = cylinder(0.032, 0.02, ledColors[colorIndex % ledColors.count], 0.05, alpha: 0.9, at: [gridX, 0.22 + gridY, 0.175])
                    led.orientation = eulerQuat(x: .pi / 2)
                    root.addChild(led)
                    colorIndex += 1
                }
                gridX += step
            }
            gridY += step
        }
    }

    private static func buildAudienceBlinder(into root: Entity) {
        addStand(to: root)

        root.addChild(box(1.02, 0.08, 0.12, .blackBody, 0.65, at: [0, 0.66, 0]))

        for x in [-0.50, 0.50] as [Float] {
            root.addChild(box(0.08, 0.60, 0.08, .blackBody, 0.65, at: [x, 0.32, 0]))
        }
        addYokeKnob(to: root, at: [-0.54, 0.34, 0])
        addYokeKnob(to: root, at: [0.54, 0.34, 0])

        // Square panel housing.
        root.addChild(box(0.86, 0.86, 0.22, .blackBody, 0.55, at: [0, 0.30, 0]))

        // 2x2 grid of large warm-white COB cells.
        for row in 0..<2 {
            for column in 0..<2 {
                let cellX = -0.20 + Float(column) * 0.40
                let cellY = 0.10 + Float(row) * 0.40
                root.addChild(box(0.36, 0.36, 0.05, .graphite, 0.5, at: [cellX, cellY, 0.12]))

                let lens = cylinder(0.15, 0.03, .warmWhite, 0.04, alpha: 0.92, at: [cellX, cellY, 0.155])
                lens.orientation = eulerQuat(x: .pi / 2)
                root.addChild(lens)
                addRing(to: root, ringRadius: 0.16, pipeRadius: 0.007, at: [cellX, cellY, 0.165], faceZ: true)
            }
        }

        addCoolingSlots(to: root, originX: -0.5, y: 0.30, z: -0.12, count: 8, vertical: false)
        addCable(to: root, fromX: 0.40, y: 0.10, z: -0.10)
    }

    private static func buildLedFresnel(into root: Entity) {
        addStand(to: root)

        root.addChild(box(0.64, 0.58, 0.44, .darkMetal, 0.62, at: [0, 0.20, 0]))
        root.addChild(box(0.92, 0.08, 0.08, .blackBody, 0.65, at: [0, 0.56, 0]))

        for x in [-0.40, 0.40] as [Float] {
            root.addChild(box(0.07, 0.56, 0.08, .blackBody, 0.65, at: [x, 0.27, 0]))
        }
        addYokeKnob(to: root, at: [-0.45, 0.29, 0])
        addYokeKnob(to: root, at: [0.45, 0.29, 0])

        // Fresnel lens with concentric rings.
        let lens = cylinder(0.26, 0.06, .coolWhite, 0.05, alpha: 0.84, at: [0, 0.20, 0.25])
        lens.orientation = eulerQuat(x: .pi / 2)
        root.addChild(lens)

        for radius in [0.10, 0.17, 0.24] as [Float] {
            addRing(to: root, ringRadius: radius, pipeRadius: 0.008, at: [0, 0.20, 0.285], faceZ: true, color: .silverMetal, metalness: 0.7)
        }

        // Three LED emitters visible behind the lens (matches the product's triple-LED face).
        for emitter in [SIMD3<Float>(0, 0.31, 0.205), SIMD3<Float>(-0.10, 0.135, 0.205), SIMD3<Float>(0.10, 0.135, 0.205)] {
            root.addChild(sphere(0.05, .coolWhite, 0.04, at: emitter))
        }

        // Square lens-holder frame standing proud of the lens.
        let frameEdges: [(Float, Float, Float, Float)] = [
            (0.54, 0.04, 0.0, 0.47),
            (0.54, 0.04, 0.0, -0.07),
            (0.04, 0.54, -0.27, 0.20),
            (0.04, 0.54, 0.27, 0.20)
        ]
        for (width, height, edgeX, edgeY) in frameEdges {
            root.addChild(box(width, height, 0.05, .blackBody, 0.55, at: [edgeX, edgeY, 0.33]))
        }

        addCoolingSlots(to: root, originX: -0.16, y: 0.20, z: -0.235, count: 5, vertical: true)
        addScrew(to: root, at: [-0.27, 0.47, 0.30])
        addScrew(to: root, at: [0.27, -0.07, 0.30])
    }

    private static func buildLaser(into root: Entity) {
        // A truss-mounted laser scanner: a compact housing with an RGB emitter face, plus the signature
        // fan of razor-thin aerial beams shooting forward — built as Unlit rods so they glow like a real
        // laser regardless of the observatory lighting.
        addHangingClamp(to: root, y: 0.74)

        root.addChild(box(0.92, 0.42, 0.5, .blackBody, 0.6, at: [0, 0.2, 0]))
        root.addChild(box(0.8, 0.3, 0.05, .graphite, 0.5, at: [0, 0.2, 0.25]))

        // Side cheek plates the scanner pivots between.
        for x in [-0.5, 0.5] as [Float] {
            root.addChild(box(0.08, 0.5, 0.5, .darkMetal, 0.66, at: [x, 0.2, 0]))
        }

        // Emitter apertures: a row of RGB pilot dots set into black cups across the front face.
        let emitterColors: [FixturePaletteColor] = [.redLens, .greenLens, .blueLens, .cyanLens, .magentaLens]
        for (index, x) in ([-0.28, -0.14, 0.0, 0.14, 0.28] as [Float]).enumerated() {
            let cup = cylinder(0.05, 0.04, .blackBody, 0.6, at: [x, 0.2, 0.265])
            cup.orientation = eulerQuat(x: .pi / 2)
            root.addChild(cup)
            root.addChild(sphere(0.03, emitterColors[index % emitterColors.count], 0.05, at: [x, 0.2, 0.285]))
        }

        addCoolingSlots(to: root, originX: -0.34, y: 0.42, z: -0.255, count: 7, vertical: true)

        // The signature: a small fan of thin, bright green beams shooting forward (+Z).
        let beamLength: Float = 0.62
        for yawDegrees in [-16.0, 0.0, 16.0] as [Float] {
            let beamOrientation = simd_quatf(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
                * simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            let direction = simd_act(beamOrientation, SIMD3<Float>(0, 1, 0))
            let beam = ModelEntity(
                mesh: .generateCylinder(height: beamLength, radius: 0.012),
                materials: [UnlitMaterial(color: laserBeamColor)]
            )
            beam.orientation = beamOrientation
            beam.position = SIMD3<Float>(0, 0.2, 0.30) + direction * (beamLength / 2)
            root.addChild(beam)
        }
    }

    /// The default emissive green of a laser beam in the observatory preview.
    private static let laserBeamColor = UIColor(red: 0.16, green: 1.0, blue: 0.42, alpha: 0.95)

    // MARK: - Shared sub-assemblies

    private static func addStand(to root: Entity) {
        root.addChild(cylinder(0.025, 0.72, .silverMetal, 0.8, at: [0, -0.36, 0]))
        root.addChild(cylinder(0.34, 0.035, .darkMetal, 0.7, at: [0, -0.74, 0]))
    }

    private static func addHangingClamp(to root: Entity, y: Float) {
        let rail = cylinder(0.035, 1.2, .silverMetal, 0.82, at: [0, y, -0.04])
        rail.orientation = eulerQuat(z: .pi / 2)
        root.addChild(rail)

        root.addChild(box(0.18, 0.14, 0.18, .darkMetal, 0.72, at: [0, y - 0.13, -0.04]))
        addRing(to: root, ringRadius: 0.10, pipeRadius: 0.014, at: [0, y - 0.06, -0.04], faceZ: true)
    }

    private static func addRing(
        to root: Entity,
        ringRadius: Float,
        pipeRadius: Float,
        at position: SIMD3<Float>,
        faceZ: Bool,
        color: FixturePaletteColor = .silverMetal,
        metalness: CGFloat = 0.72
    ) {
        let ring = ModelEntity(mesh: torusMesh(ringRadius: ringRadius, pipeRadius: pipeRadius), materials: [material(color, metalness)])
        ring.orientation = faceZ ? eulerQuat(x: .pi / 2) : eulerQuat(z: .pi / 2)
        ring.position = position
        root.addChild(ring)
    }

    private static func addScrew(to root: Entity, at position: SIMD3<Float>) {
        let screw = cylinder(0.018, 0.010, .silverMetal, 0.88, at: position)
        screw.orientation = eulerQuat(x: .pi / 2)
        root.addChild(screw)
    }

    private static func addYokeKnob(to root: Entity, at position: SIMD3<Float>) {
        let knob = cylinder(0.075, 0.040, .rubberBlack, 0.12, at: position + [0, 0, 0.06])
        knob.orientation = eulerQuat(x: .pi / 2)
        root.addChild(knob)

        let cap = cylinder(0.040, 0.012, .silverMetal, 0.80, at: position + [0, 0, 0.09])
        cap.orientation = eulerQuat(x: .pi / 2)
        root.addChild(cap)
    }

    private static func addCoolingSlots(to root: Entity, originX: Float, y: Float, z: Float, count: Int, vertical: Bool) {
        for index in 0..<count {
            let offset = Float(index) * 0.055
            let slot = box(
                vertical ? 0.018 : 0.040,
                vertical ? 0.14 : 0.014,
                0.010,
                .rubberBlack,
                0.08,
                at: [originX + offset, y, z]
            )
            root.addChild(slot)
        }
    }

    private static func addBarnDoor(to root: Entity, at position: SIMD3<Float>, angle: Float) {
        let panel = box(0.44, 0.055, 0.20, .blackBody, 0.50, at: position)
        panel.orientation = eulerQuat(x: angle)
        root.addChild(panel)
    }

    private static func addCable(to root: Entity, fromX: Float, y: Float, z: Float) {
        let cable = cylinder(0.014, 0.42, .rubberBlack, 0.04, at: [fromX + 0.12, y - 0.04, z - 0.16])
        cable.orientation = eulerQuat(x: .pi / 2, z: 0.28)
        root.addChild(cable)
    }

    // MARK: - Primitive factories

    private static func box(
        _ width: Float,
        _ height: Float,
        _ length: Float,
        _ color: FixturePaletteColor,
        _ metalness: CGFloat,
        alpha: CGFloat = 1,
        at position: SIMD3<Float>
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(width: width, height: height, depth: length, cornerRadius: 0.012),
            materials: [material(color, metalness, alpha: alpha)]
        )
        entity.position = position
        return entity
    }

    private static func cylinder(
        _ radius: Float,
        _ height: Float,
        _ color: FixturePaletteColor,
        _ metalness: CGFloat,
        alpha: CGFloat = 1,
        at position: SIMD3<Float>
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: height, radius: radius),
            materials: [material(color, metalness, alpha: alpha)]
        )
        entity.position = position
        return entity
    }

    private static func sphere(
        _ radius: Float,
        _ color: FixturePaletteColor,
        _ metalness: CGFloat,
        at position: SIMD3<Float>
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material(color, metalness)]
        )
        entity.position = position
        return entity
    }

    /// A torus whose ring lies in the X-Z plane (axis along Y), matching `SCNTorus`, so the same
    /// rotations used for the SceneKit rings apply unchanged.
    private static func torusMesh(ringRadius: Float, pipeRadius: Float, ringSegments: Int = 48, pipeSegments: Int = 16) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for i in 0..<ringSegments {
            let u = Float(i) / Float(ringSegments) * 2 * .pi
            let cosU = cos(u), sinU = sin(u)
            for j in 0..<pipeSegments {
                let v = Float(j) / Float(pipeSegments) * 2 * .pi
                let cosV = cos(v), sinV = sin(v)
                let radial = ringRadius + pipeRadius * cosV
                positions.append(SIMD3<Float>(radial * cosU, pipeRadius * sinV, radial * sinU))
                normals.append(SIMD3<Float>(cosV * cosU, sinV, cosV * sinU))
            }
        }

        func vertex(_ i: Int, _ j: Int) -> UInt32 {
            UInt32((i % ringSegments) * pipeSegments + (j % pipeSegments))
        }
        for i in 0..<ringSegments {
            for j in 0..<pipeSegments {
                let a = vertex(i, j), b = vertex(i + 1, j), c = vertex(i + 1, j + 1), d = vertex(i, j + 1)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "fixture_ring")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: pipeRadius)
    }

    private static func material(_ color: FixturePaletteColor, _ metalness: CGFloat, alpha: CGFloat = 1) -> SimpleMaterial {
        SimpleMaterial(color: color.uiColor.withAlphaComponent(alpha), isMetallic: metalness >= 0.5)
    }

    /// Composes Euler angles into a quaternion matching `SCNNode.eulerAngles` (roll, then yaw,
    /// then pitch): `v' = Rx · Ry · Rz · v`.
    private static func eulerQuat(x: Float = 0, y: Float = 0, z: Float = 0) -> simd_quatf {
        let qx = simd_quatf(angle: x, axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: z, axis: SIMD3<Float>(0, 0, 1))
        return qx * qy * qz
    }
}

/// The fixture material palette, mirroring the SceneKit thumbnails' `FixtureUIColor` so the
/// spatial model reads with the same finish.
enum FixturePaletteColor {
    case blackBody
    case darkMetal
    case graphite
    case silverMetal
    case blueLens
    case deepBlueLens
    case amberLens
    case warmLens
    case redLens
    case greenLens
    case yellowLens
    case magentaLens
    case cyanLens
    case coolWhite
    case warmWhite
    case rubberBlack

    var uiColor: UIColor {
        switch self {
        case .blackBody: return UIColor(red: 0.03, green: 0.035, blue: 0.045, alpha: 1)
        case .darkMetal: return UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
        case .graphite: return UIColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1)
        case .silverMetal: return UIColor(red: 0.70, green: 0.72, blue: 0.72, alpha: 1)
        case .blueLens: return UIColor(red: 0.19, green: 0.55, blue: 1.0, alpha: 1)
        case .deepBlueLens: return UIColor(red: 0.08, green: 0.18, blue: 0.82, alpha: 1)
        case .amberLens: return UIColor(red: 1.0, green: 0.53, blue: 0.16, alpha: 1)
        case .warmLens: return UIColor(red: 1.0, green: 0.72, blue: 0.44, alpha: 1)
        case .redLens: return UIColor(red: 1.0, green: 0.16, blue: 0.18, alpha: 1)
        case .greenLens: return UIColor(red: 0.20, green: 0.92, blue: 0.34, alpha: 1)
        case .yellowLens: return UIColor(red: 1.0, green: 0.85, blue: 0.16, alpha: 1)
        case .magentaLens: return UIColor(red: 0.96, green: 0.20, blue: 0.78, alpha: 1)
        case .cyanLens: return UIColor(red: 0.16, green: 0.86, blue: 0.96, alpha: 1)
        case .coolWhite: return UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
        case .warmWhite: return UIColor(red: 1.0, green: 0.93, blue: 0.78, alpha: 1)
        case .rubberBlack: return UIColor(red: 0.006, green: 0.007, blue: 0.009, alpha: 1)
        }
    }
}
#endif
