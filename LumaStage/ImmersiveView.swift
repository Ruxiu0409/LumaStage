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

    var body: some View {
        RealityView { content, attachments in
            let root = Self.makeStageRoot(layout: appModel.stageLayout)
            content.add(root)

            if let aiBox = attachments.entity(for: "ai_box") {
                aiBox.position = SIMD3<Float>(0, 1.45, -1.15)
                aiBox.scale = SIMD3<Float>(0.72, 0.72, 0.72)
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
        } attachments: {
            Attachment(id: "ai_box") {
                VisionAIComposerBox()
                    .environment(appModel)
            }
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

    private static func addVenueEnvironment(to root: Entity, layout: StageLayout) {
        root.addChild(box(name: "floor_concrete", width: 7.2, height: 0.018, depth: 5.4, hex: "#2D3032", intensity: 0.82, position: SIMD3<Float>(0, -0.025, -2.4)))

        for offset in [-2.2, -1.1, 0, 1.1, 2.2] as [Float] {
            root.addChild(box(name: "floor_seam_x", width: 0.008, height: 0.004, depth: 5.4, hex: "#1B1D1E", intensity: 0.7, position: SIMD3<Float>(offset, -0.012, -2.4)))
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
        root.addChild(drape)

        for index in 0..<9 {
            let x = -1.05 + Float(index) * 0.26
            root.addChild(box(name: "drape_fold", width: 0.018, height: 1.45, depth: 0.018, hex: index.isMultiple(of: 2) ? "#171A20" : "#050609", intensity: 0.82, position: drape.position + SIMD3<Float>(x, 0, 0.018)))
        }
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

        let backgroundWash = box(
            name: "background_wash_zone",
            width: sceneLength(stageSize.width * 0.9),
            height: sceneLength(max(1.0, maxTrussY - stageTopY)),
            depth: 0.025,
            hex: "#4FA8FF",
            intensity: 0.45,
            alpha: 0.48,
            position: scenePoint(Vector3Meters(x: stageBase.position.x, y: stageTopY + (maxTrussY - stageTopY) / 2, z: upstageZ - 0.18))
        )
        root.addChild(backgroundWash)

        let frontLight = box(
            name: "front_light_zone",
            width: sceneLength(stageSize.width * 0.82),
            height: 0.026,
            depth: sceneLength(stageSize.depth * 0.48),
            hex: "#FFD1A3",
            intensity: 0.38,
            alpha: 0.36,
            position: scenePoint(Vector3Meters(x: stageBase.position.x, y: stageTopY + 0.03, z: stageBase.position.z + stageSize.depth * 0.08))
        )
        root.addChild(frontLight)

        let beamY = stageTopY + max(0.7, (maxTrussY - stageTopY) * 0.45)
        let fixtureY = maxTrussY - 0.18
        for (index, xOffset) in [-0.75, 0.75].enumerated() {
            addMovingHeadFixture(
                name: "front_fixture_\(index)",
                to: root,
                position: Vector3Meters(x: stageBase.position.x + stageSize.width * xOffset / 2, y: fixtureY, z: upstageZ + 0.08),
                color: "#2B2F38",
                lensColor: "#FFD1A3"
            )
        }

        let leftBeam = box(
            name: "front_beam_left",
            width: sceneLength(stageSize.width * 0.2),
            height: 0.022,
            depth: sceneLength(stageSize.depth * 0.86),
            hex: "#FFD1A3",
            intensity: 0.28,
            alpha: 0.30,
            position: scenePoint(Vector3Meters(x: stageBase.position.x - stageSize.width * 0.2, y: beamY, z: stageBase.position.z - stageSize.depth * 0.12))
        )
        leftBeam.orientation = simd_quatf(angle: -0.30, axis: SIMD3<Float>(0, 1, 0))
        root.addChild(leftBeam)

        let rightBeam = box(
            name: "front_beam_right",
            width: sceneLength(stageSize.width * 0.2),
            height: 0.022,
            depth: sceneLength(stageSize.depth * 0.86),
            hex: "#FFD1A3",
            intensity: 0.28,
            alpha: 0.30,
            position: scenePoint(Vector3Meters(x: stageBase.position.x + stageSize.width * 0.2, y: beamY, z: stageBase.position.z - stageSize.depth * 0.12))
        )
        rightBeam.orientation = simd_quatf(angle: 0.30, axis: SIMD3<Float>(0, 1, 0))
        root.addChild(rightBeam)
    }

    private static func addMovingHeadFixture(name: String, to root: Entity, position: Vector3Meters, color: String, lensColor: String) {
        let basePosition = scenePoint(position)
        let yoke = box(name: "\(name)_yoke", width: 0.16, height: 0.08, depth: 0.08, hex: "#161A20", intensity: 0.85, position: basePosition)
        yoke.model?.materials = [material(hex: color, intensity: 0.82, isMetallic: true)]
        root.addChild(yoke)

        let head = box(name: "\(name)_head", width: 0.13, height: 0.10, depth: 0.16, hex: "#20242C", intensity: 0.9, position: basePosition + SIMD3<Float>(0, -0.075, 0.035))
        head.orientation = simd_quatf(angle: -.pi / 10, axis: SIMD3<Float>(1, 0, 0))
        head.model?.materials = [material(hex: color, intensity: 0.9, isMetallic: true)]
        root.addChild(head)

        let lens = box(name: "\(name)_lens", width: 0.07, height: 0.038, depth: 0.012, hex: lensColor, intensity: 0.75, alpha: 0.92, position: basePosition + SIMD3<Float>(0, -0.09, 0.122))
        root.addChild(lens)
    }

    private static func apply(_ cue: LightingCue, to root: Entity) {
        if let frontLight = try? cue.requireFixture(role: .frontLight) {
            updateModel(
                named: "front_light_zone",
                in: root,
                color: frontLight.color.value,
                intensity: frontLight.intensity,
                duration: cue.transition.duration,
                fineControl: frontLight.effectiveFineControl
            )
        }

        if let backgroundWash = try? cue.requireFixture(role: .backgroundWash) {
            updateModel(
                named: "background_wash_zone",
                in: root,
                color: backgroundWash.color.value,
                intensity: backgroundWash.intensity,
                duration: cue.transition.duration,
                fineControl: backgroundWash.effectiveFineControl
            )
        }
    }

    private static func updateModel(
        named name: String,
        in root: Entity,
        color: String,
        intensity: Double,
        duration: Double,
        fineControl: FixtureFineControl? = nil
    ) {
        guard let entity = root.findEntity(named: name) as? ModelEntity else {
            return
        }

        entity.model?.materials = [material(hex: color, intensity: intensity)]

        var transform = entity.transform
        let clampedIntensity = Float(max(0.1, min(intensity, 1.0)))
        transform.scale = SIMD3<Float>(1, 1, clampedIntensity)
        entity.move(
            to: transform,
            relativeTo: entity.parent,
            duration: duration,
            timingFunction: .easeInOut
        )

        if name == "front_light_zone" {
            updateBeam(named: "front_beam_left", in: root, color: color, intensity: intensity, duration: duration, fineControl: fineControl, lateralOffset: -0.28)
            updateBeam(named: "front_beam_right", in: root, color: color, intensity: intensity, duration: duration, fineControl: fineControl, lateralOffset: 0.28)
        }
    }

    private static func updateBeam(
        named name: String,
        in root: Entity,
        color: String,
        intensity: Double,
        duration: Double,
        fineControl: FixtureFineControl?,
        lateralOffset: Double
    ) {
        guard let entity = root.findEntity(named: name) as? ModelEntity else {
            return
        }

        entity.model?.materials = [material(hex: color, intensity: intensity * 0.72, alpha: 0.34 + intensity * 0.28)]
        var transform = entity.transform
        let beamAngle = Float(fineControl?.beamAngleDegrees ?? 42)
        transform.scale = SIMD3<Float>(
            0.45 + Float(intensity) * 0.42 + beamAngle / 180,
            1,
            0.62 + Float(intensity) * 0.35
        )
        if let fineControl {
            let source = FixturePosition(
                x: fineControl.position.x + lateralOffset,
                y: fineControl.position.y,
                z: fineControl.position.z
            )
            transform.translation = scenePoint(Vector3Meters(x: source.x, y: source.y, z: source.z))
            transform.rotation =
                simd_quatf(angle: Float(fineControl.panDegrees) * .pi / 180, axis: SIMD3<Float>(0, 1, 0)) *
                simd_quatf(angle: Float(fineControl.tiltDegrees) * .pi / 180, axis: SIMD3<Float>(1, 0, 0)) *
                simd_quatf(angle: Float(fineControl.rollDegrees) * .pi / 180, axis: SIMD3<Float>(0, 0, 1))
        }
        entity.move(
            to: transform,
            relativeTo: entity.parent,
            duration: duration,
            timingFunction: .easeInOut
        )
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
