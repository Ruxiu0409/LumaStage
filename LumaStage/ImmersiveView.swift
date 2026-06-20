//
//  ImmersiveView.swift
//  LumaStage
//
//  Created by Tsai Cheng-Yeh on 2026/5/20.
//

import SwiftUI
import RealityKit
import UIKit
import simd

#if os(visionOS)
struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel

    /// Offset between the grab point and the composer's origin while a drag is in flight, so the
    /// box follows the pinch without snapping its corner to the finger. `nil` when not dragging.
    @State private var composerDragOffset: SIMD3<Float>?

    var body: some View {
        RealityView { content, attachments in
            let root = Self.makeStageRoot(layout: appModel.stageLayout)
            content.add(root)

            if let aiBox = attachments.entity(for: "ai_box") {
                aiBox.position = AIComposerPlacement.defaultPosition
                aiBox.scale = SIMD3<Float>(0.72, 0.72, 0.72)
                // Make the attachment grabbable so it can be dragged anywhere in the scene.
                aiBox.components.set(InputTargetComponent())
                aiBox.generateCollisionShapes(recursive: true)
                content.add(aiBox)
            }
        } update: { content, _ in
            guard let root = content.entities.first(where: { $0.name == "LumaStageRoot" }) else {
                return
            }

            Self.syncStageLayout(appModel.stageLayout, in: root)

            if let selectedCue = appModel.selectedCue {
                Self.apply(selectedCue, to: root)
            }

            // Room-spill mode hides the opaque venue so the real room shows through passthrough.
            if let venue = root.findEntity(named: Self.opaqueVenueName) {
                venue.isEnabled = SurroundingsLightPolicy.includesOpaqueVenue(in: appModel.stageImmersionMode)
            }
        } attachments: {
            Attachment(id: "ai_box") {
                VisionAIComposerBox()
                    .environment(appModel)
            }
        }
        .preferredSurroundingsEffect(appModel.stageImmersionMode == .roomSpill ? .dim(intensity: 0.45) : nil)
        .gesture(composerDragGesture)
    }

    /// Drag the floating AI composer to any spot in front of the viewer. Position is clamped by
    /// `AIComposerPlacement` so the box can't be lost behind or out of reach.
    private var composerDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let parent = value.entity.parent else { return }
                let grabPoint = value.convert(value.location3D, from: .local, to: parent)
                if composerDragOffset == nil {
                    composerDragOffset = value.entity.position - grabPoint
                }
                value.entity.position = AIComposerPlacement.clamped(grabPoint + (composerDragOffset ?? .zero))
            }
            .onEnded { _ in
                composerDragOffset = nil
            }
    }

    private static let stageScale: Float = 0.46
    private static let stageOrigin = SIMD3<Float>(0, 0, -2.45)
    private static let layoutRootPrefix = "stage_layout_root_"

    private static func makeStageRoot(layout: StageLayout) -> Entity {
        let root = Entity()
        root.name = "LumaStageRoot"

        addVenueEnvironment(to: root, layout: layout)
        addSpatialLights(to: root)
        root.addChild(makeStageLayoutEntity(plan: ImmersiveStageGeometryPlan.make(from: layout), layout: layout))
        addLightingPreview(to: root, layout: layout)
        return root
    }

    /// The concrete floor + black backdrop that make the full-immersion "night stage" illusion.
    /// Grouped under one container so room-spill mode can hide them and reveal passthrough.
    private static let opaqueVenueName = "venue_opaque"

    private static func addVenueEnvironment(to root: Entity, layout: StageLayout) {
        let venue = Entity()
        venue.name = opaqueVenueName

        venue.addChild(box(name: "floor_concrete", width: 7.2, height: 0.018, depth: 5.4, hex: "#2D3032", intensity: 0.82, position: SIMD3<Float>(0, -0.025, -2.4)))

        for offset in [-2.2, -1.1, 0, 1.1, 2.2] as [Float] {
            venue.addChild(box(name: "floor_seam_x", width: 0.008, height: 0.004, depth: 5.4, hex: "#1B1D1E", intensity: 0.7, position: SIMD3<Float>(offset, -0.012, -2.4)))
        }

        let upstageZ = layout.objects.flatMap(\.trussEndpoints).map(\.z).min() ?? -1.25
        let drape = box(
            name: "black_backdrop_drape",
            width: 2.45,
            height: 1.55,
            depth: 0.025,
            hex: "#08090D",
            intensity: 0.92,
            position: scenePoint(Vector3Meters(x: 0, y: 1.05, z: upstageZ - 0.32))
        )
        venue.addChild(drape)

        for index in 0..<9 {
            let x = -1.05 + Float(index) * 0.26
            venue.addChild(box(name: "drape_fold", width: 0.018, height: 1.45, depth: 0.018, hex: index.isMultiple(of: 2) ? "#171A20" : "#050609", intensity: 0.82, position: drape.position + SIMD3<Float>(x, 0, 0.018)))
        }

        root.addChild(venue)
    }

    private static func addSpatialLights(to root: Entity) {
        let keyLight = DirectionalLight()
        keyLight.name = "venue_key_light"
        keyLight.light.intensity = 2600
        keyLight.light.color = UIColor(red: 1.0, green: 0.92, blue: 0.78, alpha: 1.0)
        keyLight.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: .pi / 7, axis: SIMD3<Float>(0, 1, 0))
        root.addChild(keyLight)

        let fillLight = PointLight()
        fillLight.name = "venue_fill_light"
        fillLight.light.intensity = 900
        fillLight.light.color = UIColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 1.0)
        fillLight.position = SIMD3<Float>(-1.8, 1.6, -1.2)
        root.addChild(fillLight)
    }

    private static func syncStageLayout(_ layout: StageLayout, in root: Entity) {
        let plan = ImmersiveStageGeometryPlan.make(from: layout)
        let expectedName = "\(layoutRootPrefix)\(abs(plan.layoutSignature.hashValue))"
        if root.children.contains(where: { $0.name == expectedName }) {
            return
        }

        for child in root.children where child.name.hasPrefix(layoutRootPrefix) {
            child.removeFromParent()
        }

        root.addChild(makeStageLayoutEntity(plan: plan, layout: layout))
    }

    private static func makeStageLayoutEntity(plan: ImmersiveStageGeometryPlan, layout: StageLayout) -> Entity {
        let layoutEntity = Entity()
        layoutEntity.name = "\(layoutRootPrefix)\(abs(plan.layoutSignature.hashValue))"

        for base in plan.stageBases {
            addStageBase(base, to: layoutEntity)
        }

        for (index, member) in plan.trussMembers.enumerated() {
            if let memberEntity = trussMember(member, index: index) {
                layoutEntity.addChild(memberEntity)
            }
        }

        for block in plan.connectorBlocks {
            layoutEntity.addChild(connectorBlock(block))
        }

        return layoutEntity
    }

    private static func addStageBase(_ object: StageObject, to root: Entity) {
        guard let size = object.size else {
            return
        }

        let body = box(
            name: "stage_base_body_\(object.id)",
            width: sceneLength(size.width),
            height: sceneLength(size.height),
            depth: sceneLength(size.depth),
            hex: "#070607",
            intensity: 1.0,
            position: scenePoint(object.position)
        )
        markShadowCaster(body)
        root.addChild(body)

        let topY = object.position.y + size.height / 2
        let frontZ = object.position.z + size.depth / 2
        let backZ = object.position.z - size.depth / 2
        let leftX = object.position.x - size.width / 2
        let rightX = object.position.x + size.width / 2
        let trimY = topY + 0.02

        let top = box(
            name: "stage_base_top_\(object.id)",
            width: sceneLength(size.width),
            height: 0.026,
            depth: sceneLength(size.depth),
            hex: "#C30010",
            intensity: 1.0,
            position: scenePoint(Vector3Meters(x: object.position.x, y: topY, z: object.position.z)) + SIMD3<Float>(0, 0.014, 0)
        )
        root.addChild(top)

        root.addChild(box(name: "stage_front_trim_\(object.id)", width: sceneLength(size.width), height: 0.024, depth: 0.025, hex: "#232528", intensity: 0.78, position: scenePoint(Vector3Meters(x: object.position.x, y: trimY, z: frontZ))))
        root.addChild(box(name: "stage_back_trim_\(object.id)", width: sceneLength(size.width), height: 0.018, depth: 0.02, hex: "#202226", intensity: 0.70, position: scenePoint(Vector3Meters(x: object.position.x, y: trimY, z: backZ))))
        root.addChild(box(name: "stage_left_trim_\(object.id)", width: 0.02, height: 0.018, depth: sceneLength(size.depth), hex: "#202226", intensity: 0.70, position: scenePoint(Vector3Meters(x: leftX, y: trimY, z: object.position.z))))
        root.addChild(box(name: "stage_right_trim_\(object.id)", width: 0.02, height: 0.018, depth: sceneLength(size.depth), hex: "#202226", intensity: 0.70, position: scenePoint(Vector3Meters(x: rightX, y: trimY, z: object.position.z))))

        let legInset = 0.28
        for (index, leg) in [
            Vector3Meters(x: leftX + legInset, y: size.height / 2, z: backZ + legInset),
            Vector3Meters(x: rightX - legInset, y: size.height / 2, z: backZ + legInset),
            Vector3Meters(x: rightX - legInset, y: size.height / 2, z: frontZ - legInset),
            Vector3Meters(x: leftX + legInset, y: size.height / 2, z: frontZ - legInset)
        ].enumerated() {
            let legEntity = ModelEntity(
                mesh: .generateCylinder(height: sceneLength(size.height), radius: 0.018),
                materials: [material(hex: "#6C6F73", intensity: 0.80, isMetallic: true)]
            )
            legEntity.name = "stage_leg_\(object.id)_\(index)"
            legEntity.position = scenePoint(leg)
            markShadowCaster(legEntity)
            root.addChild(legEntity)
        }

        let shadow = box(
            name: "stage_contact_shadow_\(object.id)",
            width: sceneLength(size.width * 1.04),
            height: 0.006,
            depth: sceneLength(size.depth * 1.04),
            hex: "#000000",
            intensity: 0.35,
            alpha: 0.42,
            position: scenePoint(Vector3Meters(x: object.position.x, y: 0.012, z: object.position.z))
        )
        root.addChild(shadow)
    }

    private static func trussMember(_ member: TrussVisualMember, index: Int) -> ModelEntity? {
        let start = scenePoint(member.start)
        let end = scenePoint(member.end)
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.001 else {
            return nil
        }

        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: 0.018),
            materials: [material(hex: "#D6D8D5", intensity: 0.96, isMetallic: true)]
        )
        entity.name = "truss_member_\(index)"
        entity.position = (start + end) / 2
        entity.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: direction / length)
        markShadowCaster(entity)
        return entity
    }

    private static func connectorBlock(_ block: TrussConnectorBlock) -> ModelEntity {
        let size = sceneLength(block.size)
        let entity = box(
            name: "truss_connector_\(block.id)",
            width: size,
            height: size,
            depth: size,
            hex: "#C9CBC8",
            intensity: 0.95,
            position: scenePoint(block.position)
        )
        entity.orientation = simd_quatf(angle: .pi / 10, axis: SIMD3<Float>(0, 1, 0))
        entity.model?.materials = [material(hex: "#C9CBC8", intensity: 0.95, isMetallic: true)]
        addConnectorBolts(to: entity, blockSize: size)
        markShadowCaster(entity)
        return entity
    }

    private static func addConnectorBolts(to connector: Entity, blockSize: Float) {
        let boltSize = max(0.012, blockSize * 0.12)
        for x in [-0.24, 0.24] as [Float] {
            for y in [-0.24, 0.24] as [Float] {
                let bolt = box(
                    name: "connector_bolt",
                    width: boltSize,
                    height: boltSize,
                    depth: 0.006,
                    hex: "#74777A",
                    intensity: 0.75,
                    position: SIMD3<Float>(x * blockSize, y * blockSize, blockSize * 0.52)
                )
                bolt.model?.materials = [material(hex: "#74777A", intensity: 0.75, isMetallic: true)]
                connector.addChild(bolt)
            }
        }
    }

    private static func addLightingPreview(to root: Entity, layout: StageLayout) {
        guard let stageBase = layout.objects.first(where: { $0.type == .stageBase }),
              let stageSize = stageBase.size else {
            return
        }

        let stageTopY = stageBase.position.y + stageSize.height / 2
        let upstageZ = layout.objects.flatMap(\.trussEndpoints).map(\.z).min() ?? (stageBase.position.z - stageSize.depth / 2)
        let maxTrussY = layout.objects.flatMap(\.trussEndpoints).map(\.y).max() ?? (stageTopY + 2)
        let fixtureY = maxTrussY - 0.18

        // Visible moving-head fixtures on the upstage truss double as the real background-wash
        // emitters, casting light back onto the backdrop drape.
        let washTarget = Vector3Meters(
            x: stageBase.position.x,
            y: stageTopY + (maxTrussY - stageTopY) * 0.45,
            z: upstageZ - 0.28
        )
        for (index, xOffset) in [-0.75, 0.75].enumerated() {
            let fixture = Vector3Meters(x: stageBase.position.x + stageSize.width * xOffset / 2, y: fixtureY, z: upstageZ + 0.08)
            addMovingHeadFixture(
                name: "moving_head_\(index)",
                to: root,
                position: fixture,
                color: "#2B2F38",
                lensColor: "#9FB6FF"
            )
            addStageSpotLight(
                name: "spot_backgroundWash_\(index)",
                to: root,
                from: Vector3Meters(x: fixture.x, y: fixture.y - 0.12, z: fixture.z + 0.05),
                aim: washTarget,
                beamAngleDegrees: 60
            )
        }

        // Front-of-house key light: elevated and downstage of the deck, aimed at the performer
        // area. No visible fixture — FOH positions sit out past the audience in a real venue.
        let frontTarget = Vector3Meters(
            x: stageBase.position.x,
            y: stageTopY + 0.05,
            z: stageBase.position.z + stageSize.depth * 0.12
        )
        for (index, xOffset) in [-0.55, 0.55].enumerated() {
            let source = Vector3Meters(
                x: stageBase.position.x + stageSize.width * xOffset / 2,
                y: stageTopY + 1.9,
                z: stageBase.position.z + stageSize.depth * 0.95 + 0.7
            )
            addStageSpotLight(
                name: "spot_frontLight_\(index)",
                to: root,
                from: source,
                aim: frontTarget,
                beamAngleDegrees: 40
            )
        }
    }

    @discardableResult
    private static func addStageSpotLight(
        name: String,
        to root: Entity,
        from sourceModel: Vector3Meters,
        aim aimModel: Vector3Meters,
        beamAngleDegrees: Double
    ) -> SpotLight {
        let spot = SpotLight()
        spot.name = name

        // Starts dark; `apply(_:to:)` drives color/intensity from the selected cue.
        spot.light.color = .white
        spot.light.intensity = 0
        let cone = SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees)
        spot.light.innerAngleInDegrees = Float(cone.inner)
        spot.light.outerAngleInDegrees = Float(cone.outer)
        spot.light.attenuationRadius = 18
        spot.shadow = SpotLightComponent.Shadow()

        // Opt this virtual spotlight into illuminating the real room in passthrough (room-spill)
        // mode. Inert in full immersion (no passthrough to light), so it's safe to always tag.
        if #available(visionOS 27.0, *) {
            spot.components.set(SpotLightComponent.SurroundingsLight())
        }

        let position = scenePoint(sourceModel)
        spot.position = position
        let direction = scenePoint(aimModel) - position
        if simd_length(direction) > 0.0001 {
            // A spotlight emits along its local -Z; aim that axis at the stage target.
            spot.orientation = orientation(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(direction))
        }

        root.addChild(spot)
        return spot
    }

    private static func addMovingHeadFixture(name: String, to root: Entity, position: Vector3Meters, color: String, lensColor: String) {
        let basePosition = scenePoint(position)
        let yoke = box(name: "\(name)_yoke", width: 0.16, height: 0.08, depth: 0.08, hex: "#161A20", intensity: 0.85, position: basePosition)
        yoke.model?.materials = [material(hex: color, intensity: 0.82, isMetallic: true)]
        markShadowCaster(yoke)
        root.addChild(yoke)

        let head = box(name: "\(name)_head", width: 0.13, height: 0.10, depth: 0.16, hex: "#20242C", intensity: 0.9, position: basePosition + SIMD3<Float>(0, -0.075, 0.035))
        head.orientation = simd_quatf(angle: -.pi / 10, axis: SIMD3<Float>(1, 0, 0))
        head.model?.materials = [material(hex: color, intensity: 0.9, isMetallic: true)]
        markShadowCaster(head)
        root.addChild(head)

        let lens = box(name: "\(name)_lens", width: 0.07, height: 0.038, depth: 0.012, hex: lensColor, intensity: 0.75, alpha: 0.92, position: basePosition + SIMD3<Float>(0, -0.09, 0.122))
        root.addChild(lens)
    }

    private static func apply(_ cue: LightingCue, to root: Entity) {
        if let frontLight = try? cue.requireFixture(role: .frontLight) {
            for index in 0..<2 {
                updateSpotLight(
                    named: "spot_frontLight_\(index)",
                    in: root,
                    role: .frontLight,
                    color: frontLight.color.value,
                    intensity: frontLight.intensity,
                    beamAngleDegrees: frontLight.effectiveFineControl.beamAngleDegrees,
                    gobo: frontLight.gobo,
                    duration: cue.transition.duration
                )
            }
        }

        if let backgroundWash = try? cue.requireFixture(role: .backgroundWash) {
            for index in 0..<2 {
                updateSpotLight(
                    named: "spot_backgroundWash_\(index)",
                    in: root,
                    role: .backgroundWash,
                    color: backgroundWash.color.value,
                    intensity: backgroundWash.intensity,
                    beamAngleDegrees: backgroundWash.effectiveFineControl.beamAngleDegrees,
                    gobo: backgroundWash.gobo,
                    duration: cue.transition.duration
                )
            }
        }
    }

    // Drives a real RealityKit spotlight from a cue's fixture values. The mutation runs inside a
    // SwiftUI animation transaction so `SpotLightComponent` (an `_ImplicitlyAnimatableBuiltinComponent`
    // on visionOS 27) cross-fades color/intensity/cone over the cue's transition duration instead of
    // hard-cutting.
    private static func updateSpotLight(
        named name: String,
        in root: Entity,
        role: FixtureRole,
        color: String,
        intensity: Double,
        beamAngleDegrees: Double,
        gobo: GoboPattern?,
        duration: Double
    ) {
        guard let spot = root.findEntity(named: name) as? SpotLight else {
            return
        }

        let rgb = RGBComponents(hex: color) ?? .white
        let lumens = Float(SpotLightRenderMath.lumens(forIntensity: intensity, role: role))
        let cone = SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees)

        withAnimation(.easeInOut(duration: duration)) {
            spot.light.color = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            spot.light.intensity = lumens
            spot.light.innerAngleInDegrees = Float(cone.inner)
            spot.light.outerAngleInDegrees = Float(cone.outer)
        }

        // Soft shadow: widen the penumbra with the beam, keyed brighter for the front key light.
        // Shadow isn't an _ImplicitlyAnimatableBuiltinComponent, so this is set outside the
        // animation (beam width rarely changes between cues anyway).
        var shadow = spot.shadow ?? SpotLightComponent.Shadow()
        shadow.lightSize = Float(SpotLightRenderMath.shadowLightSize(beamAngleDegrees: beamAngleDegrees))
        shadow.quality = role == .frontLight ? .high : .medium
        spot.shadow = shadow

        // Digital gobo: project a pattern through the cone, or remove it for a plain beam.
        // Set/removed outside the withAnimation above on purpose — ProjectiveTexture conforms only
        // to Component (not _ImplicitlyAnimatableBuiltinComponent), so it can't cross-fade and
        // hard-cuts regardless of placement, unlike the color/intensity/cone above.
        if let gobo, let texture = goboTexture(for: gobo) {
            spot.components.set(SpotLightComponent.ProjectiveTexture(texture: texture))
        } else {
            spot.components.remove(SpotLightComponent.ProjectiveTexture.self)
        }
    }

    // MARK: - Digital gobos (projective textures)

    private static var goboTextureCache: [GoboPattern: TextureResource] = [:]

    /// Lazily builds and caches a `TextureResource` for each gobo pattern from a procedurally
    /// drawn image, so cue changes only generate each pattern once.
    private static func goboTexture(for pattern: GoboPattern) -> TextureResource? {
        if let cached = goboTextureCache[pattern] {
            return cached
        }
        // .color is the conventional semantic for projected imagery (and keeps the door open for
        // colored gobos). It sRGB-decodes the mask, which slightly darkens midtones of the
        // breakup/stars patterns — a visual-tuning item to A/B against .raw on device.
        guard let cgImage = makeGoboImage(for: pattern),
              let texture = try? TextureResource(
                image: cgImage,
                withName: "gobo_\(pattern.rawValue)",
                options: TextureResource.CreateOptions(semantic: .color)
              ) else {
            return nil
        }
        goboTextureCache[pattern] = texture
        return texture
    }

    /// Procedurally draws a 256×256 grayscale gobo: bright = light passes, dark = blocked.
    /// Patterns are deterministic so the projected look is stable across runs.
    private static func makeGoboImage(for pattern: GoboPattern) -> CGImage? {
        let size = CGSize(width: 256, height: 256)
        let bounds = CGRect(origin: .zero, size: size)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            switch pattern {
            case .breakup:
                UIColor.black.setFill()
                ctx.fill(bounds)
                var rng = GoboRandom(seed: 0x1234_5678)
                for _ in 0..<44 {
                    let radius = 12 + rng.next() * 28
                    let x = rng.next() * size.width
                    let y = rng.next() * size.height
                    UIColor(white: 1, alpha: 0.35 + rng.next() * 0.6).setFill()
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            case .stripes:
                UIColor.black.setFill()
                ctx.fill(bounds)
                UIColor.white.setFill()
                let bars = 7
                let barWidth = size.width / CGFloat(bars * 2 - 1)
                for index in 0..<bars {
                    ctx.fill(CGRect(x: CGFloat(index) * barWidth * 2, y: 0, width: barWidth, height: size.height))
                }
            case .stars:
                UIColor.black.setFill()
                ctx.fill(bounds)
                var rng = GoboRandom(seed: 0x0FEE_1DAD)
                for _ in 0..<96 {
                    let radius = 1 + rng.next() * 2.4
                    let x = rng.next() * size.width
                    let y = rng.next() * size.height
                    UIColor(white: 1, alpha: 0.5 + rng.next() * 0.5).setFill()
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
                }
            case .grid:
                UIColor.white.setFill()
                ctx.fill(bounds)
                UIColor.black.setFill()
                let frame: CGFloat = 14
                ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: frame))
                ctx.fill(CGRect(x: 0, y: size.height - frame, width: size.width, height: frame))
                ctx.fill(CGRect(x: 0, y: 0, width: frame, height: size.height))
                ctx.fill(CGRect(x: size.width - frame, y: 0, width: frame, height: size.height))
                let mullion: CGFloat = 10
                for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
                    ctx.fill(CGRect(x: size.width * fraction - mullion / 2, y: 0, width: mullion, height: size.height))
                    ctx.fill(CGRect(x: 0, y: size.height * fraction - mullion / 2, width: size.width, height: mullion))
                }
            }
        }
        return image.cgImage
    }

    /// Tiny deterministic LCG so procedurally scattered gobos (breakup, stars) are reproducible.
    private struct GoboRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 40) / CGFloat(1 << 24)
        }
    }

    private static func scenePoint(_ point: Vector3Meters) -> SIMD3<Float> {
        SIMD3<Float>(
            Float(point.x) * stageScale + stageOrigin.x,
            Float(point.y) * stageScale + stageOrigin.y,
            Float(point.z) * stageScale + stageOrigin.z
        )
    }

    private static func sceneLength(_ meters: Double) -> Float {
        Float(meters) * stageScale
    }

    private static func orientation(from source: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let from = simd_normalize(source)
        let to = simd_normalize(target)
        let dot = min(max(simd_dot(from, to), -1), 1)

        if dot > 0.9999 {
            return simd_quatf(angle: 0, axis: from)
        }

        if dot < -0.9999 {
            return simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }

        return simd_quatf(angle: acos(dot), axis: simd_normalize(simd_cross(from, to)))
    }

    /// Opts a mesh into casting real shadows from the dynamic spotlights. RealityKit renders
    /// dynamic-light shadows only for entities carrying a `DynamicLightShadowComponent`; without it
    /// the `SpotLightComponent.Shadow` settings are inert. Lit surfaces receive shadows automatically,
    /// so only casters (structure that should block the beam) need this.
    private static func markShadowCaster(_ entity: Entity) {
        entity.components.set(DynamicLightShadowComponent(castsShadow: true))
    }

    private static func box(
        name: String,
        width: Float,
        height: Float,
        depth: Float,
        hex: String,
        intensity: Double,
        alpha: Double = 1.0,
        position: SIMD3<Float>
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(width: width, height: height, depth: depth),
            materials: [material(hex: hex, intensity: intensity, alpha: alpha)]
        )
        entity.name = name
        entity.position = position
        return entity
    }

    private static func material(hex: String, intensity: Double, isMetallic: Bool = false, alpha: Double = 1.0) -> SimpleMaterial {
        let rgb = (RGBComponents(hex: hex) ?? .white).dimmed(by: max(0.18, min(intensity, 1.0)))
        return SimpleMaterial(
            color: UIColor(
                red: rgb.red,
                green: rgb.green,
                blue: rgb.blue,
                alpha: alpha
            ),
            isMetallic: isMetallic
        )
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
#endif
