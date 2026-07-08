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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    // Base intensity captured at the start of a pinch-drag, so vertical drag deltas are applied against
    // a stable origin (not the running value) for the duration of the gesture. nil between drags.
    @State private var dragBaseIntensity: Double?

    var body: some View {
        // Establish a body-level Observation dependency on the lighting look so a generation-
        // or cue-driven look change re-evaluates this body, which re-runs the RealityView
        // `update:` closure below and re-applies the cue to the spotlights. The look is otherwise
        // read ONLY inside `update:` — an escaping closure that does NOT register its own body
        // dependencies (WWDC25 "Better together: SwiftUI and RealityKit": the update closure is an
        // extension of the view's body and only re-runs when the body re-evaluates) — so without
        // this read, AI generation updates the AI box text but the scene never relights.
        // Same pattern as LumaStageApp's `let _ = appModel.stageImmersionMode`.
        let _ = appModel.lightingLook
        // Also depend on the per-light overrides so "close the light 3" re-runs the update closure.
        let _ = appModel.lightOverrides
        // And on the manually selected light so a pinch-to-select re-runs the update closure below,
        // which toggles the on-stage highlight ring (the floating control card is now a native
        // `WindowGroup` driven by the `.onChange` below, not the update closure). Same Observation
        // footgun as the reads above: the `update:` closure registers no dependencies of its own.
        let _ = appModel.selectedLightNumber
        // And on the group submasters (SPEC 08) so an iPad fader ride re-runs the update closure and
        // folds the new master into the relight. Same Observation footgun as the reads above.
        let _ = appModel.groupMasters

        RealityView { content in
            let root = Self.makeStageRoot(layout: appModel.stageLayout)
            // Build the dynamic rig (fixtures + spotlights + labels) from the look's fixtures, then light it.
            Self.syncRig(cue: appModel.selectedCue, layout: appModel.stageLayout, in: root)
            if let selectedCue = appModel.selectedCue {
                Self.apply(
                    selectedCue,
                    overrides: appModel.lightOverrides,
                    groupMasters: appModel.groupMasterByLight(),
                    to: root,
                    manualLightNumber: appModel.selectedLightNumber
                )
            }
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "LumaStageRoot" }) else {
                return
            }

            Self.syncStageLayout(appModel.stageLayout, in: root)
            // Reconcile the rig to the current look (rebuilds only when the fixture set changes — e.g.
            // a new AI generation with different fixtures), then relight the selected cue + overrides.
            Self.syncRig(cue: appModel.selectedCue, layout: appModel.stageLayout, in: root)

            if let selectedCue = appModel.selectedCue {
                Self.apply(
                    selectedCue,
                    overrides: appModel.lightOverrides,
                    groupMasters: appModel.groupMasterByLight(),
                    to: root,
                    manualLightNumber: appModel.selectedLightNumber
                )
            }

            // Highlight the pick proxy of the currently selected light (and clear any stale ring).
            // (The manual control CARD itself is now a native `WindowGroup`, opened/dismissed by the
            // `.onChange(of: appModel.selectedLightNumber)` below — only the on-stage ring stays here.)
            Self.syncSelectionHighlight(selectedLightNumber: appModel.selectedLightNumber, in: root)

            // Room-spill mode hides the opaque venue so the real room shows through passthrough.
            if let venue = root.findEntity(named: Self.opaqueVenueName) {
                venue.isEnabled = SurroundingsLightPolicy.includesOpaqueVenue(in: appModel.stageImmersionMode)
            }
        }
        // Pinch a light's pick proxy to select it for manual control. Mirrors `TabletopStageEditorView`'s
        // tap-and-walk-up-to-a-named-container pattern.
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    // Select the pinched light. Empty-space pinches don't fire (targetedToAnyEntity only delivers on
                    // entities with an InputTargetComponent, and the pick proxies are the only ones), so deselection is
                    // via the control card's X button — not an empty tap.
                    if let number = Self.lightNumber(forPickTarget: value.entity) {
                        appModel.selectLight(number: number)
                    }
                }
        )
        // Pinch a light and pull it up/down to dim it in real time — the spec's headline "捏拉調暗".
        // Composed with the tap above via `.simultaneousGesture` so tap-to-select still fires; a drag
        // also selects the light on its first change. Up (negative drag height) = brighter, clamped 0...1.
        .simultaneousGesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard let n = Self.lightNumber(forPickTarget: value.entity) else { return }
                    if dragBaseIntensity == nil {
                        // First change of this drag: select the light and capture its current resolved
                        // intensity as the base the drag delta is applied against.
                        appModel.selectLight(number: n)
                        dragBaseIntensity = appModel.selectedLightResolved?.intensity ?? 0
                    }
                    let delta = -Double(value.translation.height) * Self.dragIntensityPerPoint
                    let target = min(max((dragBaseIntensity ?? 0) + delta, 0), 1)
                    appModel.setManualIntensity(light: n, target)
                }
                .onEnded { _ in
                    dragBaseIntensity = nil
                }
        )
        .preferredSurroundingsEffect(appModel.stageImmersionMode == .roomSpill ? .dim(intensity: 0.45) : nil)
        // The per-light manual control card is a single native `Window` (declared in LumaStageApp) — it
        // gets the system move bar and keeps its own position across content updates (no more "jump back
        // to a generated spot" when the user recolours a light). Open it whenever a light becomes
        // selected and dismiss it when the selection clears; because it's a `Window` (not a `WindowGroup`),
        // re-opening for a newly selected light reuses the same card instead of stacking duplicates. `selectedLightNumber` is already read at
        // body level (above) so this `.onChange` observes it. The card's own X button calls
        // `appModel.selectLight(number: nil)`, which flows back through here to dismiss the window.
        .onChange(of: appModel.selectedLightNumber, initial: true) { _, newValue in
            if newValue == nil {
                dismissWindow(id: AppModel.lightControlWindowID)
            } else {
                openWindow(id: AppModel.lightControlWindowID)
            }
        }
        // The AI composer is a native `WindowGroup` (declared in LumaStageApp) so it gets the
        // system move bar and smooth, compositor-driven dragging instead of a hand-rolled entity
        // drag. The system does NOT auto-hide an app's own windows when an immersive space opens,
        // so it's opened with the space here and dismissed when the space closes.
        .onAppear {
            appModel.immersiveSpaceState = .open
            // Fresh stage session: clear any stale programmatic-dismiss guard so the windowed
            // composer's user-close detection (issue #7) starts from a known state.
            appModel.expectedComposerDismiss = false
            openWindow(id: AppModel.aiComposerWindowID)
            // Dismiss the launch/project window for the duration of the stage. It's otherwise left
            // behind the immersive scene as nothing but its empty, draggable system bar (ContentView
            // collapses to a 1x1 clear view, but the window — and its move bar — stays alive).
            // Reopened in onDisappear; the auto-open guard lives in AppModel so the recreated
            // ContentView doesn't re-open the stage the user just closed.
            dismissWindow(id: AppModel.mainWindowID)
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            // Mark this composer dismiss as programmatic so its onDisappear doesn't mistake the
            // normal stage teardown for a user closing the window (issue #7).
            appModel.expectedComposerDismiss = true
            dismissWindow(id: AppModel.aiComposerWindowID)
            // Also dismiss the per-light control window so it doesn't leak when leaving the stage.
            dismissWindow(id: AppModel.lightControlWindowID)
            openWindow(id: AppModel.mainWindowID)
        }
    }

    /// True 1:1 scale: one modelled metre renders as one real metre, per the spec's "1:1 night
    /// outdoor stage digital twin". (Previously 0.46, which made the stage read as a tabletop model.)
    private static let stageScale: Float = 1.0
    /// Push the stage back so its front edge sits a comfortable ~3m in front of the viewer at 1:1.
    private static let stageOrigin = SIMD3<Float>(0, 0, -4.5)
    private static let layoutRootPrefix = "stage_layout_root_"

    /// `SpotLightRenderMath` lumens were tuned at the original 0.46 scene scale. Spotlight illuminance
    /// falls off with distance², so at full 1:1 the same lumens read dimmer (source→target distances
    /// grow by 1/0.46). Scale lumens by (stageScale / referenceScale)² to preserve the tuned surface
    /// brightness — it equals 1.0 at the reference scale, so dialling `stageScale` back stays lossless.
    private static let photometricReferenceScale: Float = 0.46
    private static var lumenScaleCompensation: Float {
        let ratio = stageScale / photometricReferenceScale
        return ratio * ratio
    }

    private static func makeStageRoot(layout: StageLayout) -> Entity {
        // Register the per-frame dynamic-effects system (sweeps / strobe / chase) before any spotlight
        // carrying a LightEffectComponent enters the scene. Idempotent.
        LightEffectSystem.registerIfNeeded()
        let root = Entity()
        root.name = "LumaStageRoot"

        addVenueEnvironment(to: root, layout: layout)
        addSpatialLights(to: root)
        root.addChild(makeStageLayoutEntity(plan: ImmersiveStageGeometryPlan.make(from: layout), layout: layout))
        // Fixtures (lit gear + their spotlights) are built dynamically from the look's rig by
        // `syncRig`, not here — the rig varies per look (any number/type of fixtures).
        addPerformerStandIn(to: root, layout: layout)
        return root
    }

    /// The concrete floor + black backdrop that make the full-immersion "night stage" illusion.
    /// Grouped under one container so room-spill mode can hide them and reveal passthrough.
    private static let opaqueVenueName = "venue_opaque"

    private static func addVenueEnvironment(to root: Entity, layout: StageLayout) {
        let venue = Entity()
        venue.name = opaqueVenueName

        // Derive the venue footprint from the actual stage so the floor + backdrop stay coherent with
        // the stage at any `stageScale`. The old fixed 7.2 x 5.4 floor only matched the 0.46 model and
        // left the (real-scale) floor dwarfing the shrunken stage.
        let stageBase = layout.objects.first { $0.type == .stageBase }
        let stageSize = stageBase?.size ?? StageObjectSize(width: 6, depth: 3, height: 0.8)
        let stageCenterX = stageBase?.position.x ?? 0
        let stageCenterZ = stageBase?.position.z ?? 0
        let frontEdgeZ = stageCenterZ + stageSize.depth / 2
        let upstageZ = layout.objects.flatMap(\.trussEndpoints).map(\.z).min() ?? (stageCenterZ - stageSize.depth / 2)
        let trussTopY = layout.objects.flatMap(\.trussEndpoints).map(\.y).max() ?? 3

        // Floor: from the viewer's feet (downstage) to behind the truss, with a margin on each side.
        let floorWidth = stageSize.width + 4.0
        let floorFrontZ = frontEdgeZ + 3.5
        let floorBackZ = upstageZ - 2.0
        let floorDepth = floorFrontZ - floorBackZ
        let floorCenterZ = (floorFrontZ + floorBackZ) / 2
        var floorPosition = scenePoint(Vector3Meters(x: stageCenterX, y: 0, z: floorCenterZ))
        floorPosition.y = -0.02
        venue.addChild(box(name: "floor_concrete", width: sceneLength(floorWidth), height: 0.02, depth: sceneLength(floorDepth), hex: "#2D3032", intensity: 0.82, position: floorPosition))

        let seamCount = 9
        for index in 0..<seamCount {
            let fraction = Double(index) / Double(seamCount - 1)
            let seamX = stageCenterX - floorWidth / 2 + fraction * floorWidth
            var seamPosition = scenePoint(Vector3Meters(x: seamX, y: 0, z: floorCenterZ))
            seamPosition.y = -0.012
            venue.addChild(box(name: "floor_seam_x", width: 0.008, height: 0.006, depth: sceneLength(floorDepth), hex: "#1B1D1E", intensity: 0.7, position: seamPosition))
        }

        // Backdrop cyclorama: a light, near-neutral surface a touch wider than the truss and exactly
        // as tall as its top, set just behind it. It is intentionally LIGHT (not the old near-black drape)
        // so the coloured background wash actually shows — a real cyc is pale precisely so a wash reads
        // on it; a black backdrop just absorbed the colour. With the venue ambient now dimmed, the cyc
        // mostly shows the wash colour.
        let drapeWidth = stageSize.width + 1.5
        let drapeHeight = trussTopY   // match the truss top exactly — the cyc shouldn't loom above the rig
        let drape = box(
            name: "backdrop_cyclorama",
            width: sceneLength(drapeWidth),
            height: sceneLength(drapeHeight),
            depth: 0.03,
            hex: "#C8CCD2",
            intensity: 1.0,
            position: scenePoint(Vector3Meters(x: stageCenterX, y: drapeHeight / 2, z: upstageZ - 0.5))
        )
        venue.addChild(drape)

        // Faint, low-contrast vertical seams so the cyc reads as panelled rather than a flat slab —
        // light enough that they don't break up the projected wash colour.
        let foldCount = 15
        for index in 0..<foldCount {
            let fraction = Double(index) / Double(foldCount - 1)
            let foldX = -drapeWidth / 2 + fraction * drapeWidth
            let foldPosition = drape.position + SIMD3<Float>(sceneLength(foldX), 0, 0.02)
            venue.addChild(box(name: "cyclorama_seam", width: 0.012, height: sceneLength(drapeHeight * 0.95), depth: 0.02, hex: index.isMultiple(of: 2) ? "#BFC3C9" : "#CDD1D7", intensity: 1.0, position: foldPosition))
        }

        root.addChild(venue)
    }

    private static func addSpatialLights(to root: Entity) {
        // These are AMBIENT venue lights only — just enough to read the stage structure. They are kept
        // DIM and near-neutral on purpose so the cue spotlights dominate and their colour reads true: a
        // strong, unchanging warm key + saturated blue fill previously washed the whole stage and made
        // a cue colour change (e.g. "make it yellow") barely perceptible.
        let keyLight = DirectionalLight()
        keyLight.name = "venue_key_light"
        keyLight.light.intensity = 700   // directional intensity is in lux (no distance falloff), so it's scale-independent
        keyLight.light.color = UIColor(red: 0.90, green: 0.93, blue: 1.0, alpha: 1.0)
        keyLight.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0)) * simd_quatf(angle: .pi / 7, axis: SIMD3<Float>(0, 1, 0))
        root.addChild(keyLight)

        // A gentle, near-neutral fill from stage-left-front. Positioned in model space (so it scales
        // with the stage) and brightened by the same distance² compensation as the spotlights —
        // PointLight is lumens-based. Much dimmer/less saturated than before so it no longer tints the
        // cue colours.
        let fillLight = PointLight()
        fillLight.name = "venue_fill_light"
        fillLight.light.intensity = 240 * lumenScaleCompensation
        fillLight.light.attenuationRadius = sceneLength(40)
        fillLight.light.color = UIColor(red: 0.80, green: 0.85, blue: 0.96, alpha: 1.0)
        fillLight.position = scenePoint(Vector3Meters(x: -3.0, y: 2.5, z: 1.0))
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
            layoutEntity.addChild(connectorBlock(block, layout: layout))
        }

        addLatticeNodes(plan, to: layoutEntity)

        return layoutEntity
    }

    /// Caps the interior lattice junctions (where diagonal braces meet the chords) with small metal
    /// node spheres, closing the thin-cylinder gaps that show at 1:1. Junctions that coincide with a
    /// truss-to-truss connector are skipped — the connector cube already covers those.
    private static func addLatticeNodes(_ plan: ImmersiveStageGeometryPlan, to layoutEntity: Entity) {
        var nodes: [Vector3Meters] = []
        for member in plan.trussMembers {
            for point in [member.start, member.end] {
                if nodes.contains(where: { $0.distance(to: point) < 0.02 }) { continue }
                if plan.connectorBlocks.contains(where: { $0.position.distance(to: point) < 0.26 }) { continue }
                nodes.append(point)
            }
        }
        for (index, node) in nodes.enumerated() {
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: sceneLength(0.055)),
                materials: [material(hex: "#C2C4C1", intensity: 0.95, isMetallic: true)]
            )
            sphere.name = "truss_node_\(index)"
            sphere.position = scenePoint(node)
            markShadowCaster(sphere)
            layoutEntity.addChild(sphere)
        }
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
                mesh: .generateCylinder(height: sceneLength(size.height), radius: sceneLength(0.04)),
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
            mesh: .generateCylinder(height: length, radius: sceneLength(0.04)),
            materials: [material(hex: "#D6D8D5", intensity: 0.96, isMetallic: true)]
        )
        entity.name = "truss_member_\(index)"
        entity.position = (start + end) / 2
        entity.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: direction / length)
        markShadowCaster(entity)
        return entity
    }

    private static func connectorBlock(_ block: TrussConnectorBlock, layout: StageLayout) -> Entity {
        // The portal is planar in X-Y, so truss only ever enters a joint along ±X / ±Y; ±Z always stays
        // clear and faces the audience. Knowing the occupied axes lets us bolt the clear faces and add a
        // base plate under a foot.
        let incoming = incomingTrussDirections(at: block.position, layout: layout)
        let isFooting = block.position.y < 0.05
        let isCorner = incoming.count == 2 && abs(simd_dot(incoming[0], incoming[1])) < 0.5

        // The cube must be big enough to *swallow* the chord/brace ends that converge at the joint —
        // otherwise the bare tubes crossing read as a tangle. A 90° corner needs a notably bigger block
        // (real portal truss uses a prominent corner cube there).
        let cubeSize = sceneLength(block.size) * (isCorner ? 1.5 : (incoming.count <= 1 ? 1.3 : 1.15))

        let connector = Entity()
        connector.name = "truss_connector_\(block.id)"
        // Lift a floor joint so the cube rests on the deck/floor rather than sinking half below it.
        var origin = scenePoint(block.position)
        if isFooting { origin.y += cubeSize / 2 }
        connector.position = origin

        // Axis-aligned solid cube, same finish as the truss (the old 18° tilt read as a skewed joint).
        let cube = box(name: "connector_cube_\(block.id)", width: cubeSize, height: cubeSize, depth: cubeSize, hex: "#D6D8D5", intensity: 0.96, position: .zero)
        cube.model?.materials = [material(hex: "#D6D8D5", intensity: 0.96, isMetallic: true)]
        markShadowCaster(cube)
        connector.addChild(cube)

        // Bolt studs on every face the truss doesn't pass through (and not the footing's underside).
        let faces: [SIMD3<Float>] = [
            SIMD3(0, 0, 1), SIMD3(0, 0, -1),
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0),
            SIMD3(0, 1, 0), SIMD3(0, -1, 0)
        ]
        for normal in faces {
            if incoming.contains(where: { simd_dot($0, normal) > 0.5 }) { continue }
            if isFooting && normal.y < -0.5 { continue }
            addConnectorBolts(to: cube, blockSize: cubeSize, faceNormal: normal)
        }

        if isFooting {
            addBasePlate(to: connector, blockSize: cubeSize)
        }

        return connector
    }

    /// Unit directions (along ±X / ±Y) of the truss segments meeting at a joint, in model/scene axes
    /// (`scenePoint` only scales+translates, so model axes == scene axes).
    private static func incomingTrussDirections(at position: Vector3Meters, layout: StageLayout) -> [SIMD3<Float>] {
        var directions: [SIMD3<Float>] = []
        for object in layout.objects where object.type == .trussSegment {
            let endpoints = object.trussEndpoints
            guard endpoints.count == 2 else { continue }
            for (index, endpoint) in endpoints.enumerated() where endpoint.distance(to: position) <= 0.06 {
                let toward = endpoints[1 - index] - endpoint
                let vector = SIMD3<Float>(Float(toward.x), Float(toward.y), Float(toward.z))
                let length = simd_length(vector)
                guard length > 0.0001 else { continue }
                let unit = vector / length
                if !directions.contains(where: { simd_dot($0, unit) > 0.9 }) {
                    directions.append(unit)
                }
            }
        }
        return directions
    }

    private static func addConnectorBolts(to connector: Entity, blockSize: Float, faceNormal: SIMD3<Float>) {
        let studRadius = max(0.01, blockSize * 0.085)
        let studHeight = max(0.02, blockSize * 0.12)
        let inset = blockSize * 0.26
        // Two in-plane axes spanning the face.
        let reference: SIMD3<Float> = abs(faceNormal.y) > 0.5 ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0)
        let inPlaneA = simd_normalize(simd_cross(reference, faceNormal))
        let inPlaneB = simd_normalize(simd_cross(faceNormal, inPlaneA))
        let faceCenter = faceNormal * (blockSize * 0.5 + studHeight * 0.3)
        for a in [-inset, inset] as [Float] {
            for b in [-inset, inset] as [Float] {
                let stud = ModelEntity(
                    mesh: .generateCylinder(height: studHeight, radius: studRadius),
                    materials: [material(hex: "#8A8D90", intensity: 0.82, isMetallic: true)]
                )
                stud.name = "connector_bolt"
                stud.position = faceCenter + inPlaneA * a + inPlaneB * b
                // The cylinder's axis is local +Y; lay it along the face normal so the stud pokes out.
                stud.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: faceNormal)
                connector.addChild(stud)
            }
        }
    }

    /// Flat square steel base plate under a truss leg foot, with anchor bolts — a realistic ground joint.
    private static func addBasePlate(to connector: Entity, blockSize: Float) {
        let plateSize = blockSize * 1.8
        let plateThickness = sceneLength(0.03)
        // The connector origin was lifted by blockSize/2, so the floor sits at local y = -blockSize/2.
        let plateY = -blockSize / 2 + plateThickness / 2
        let plate = box(name: "connector_baseplate", width: plateSize, height: plateThickness, depth: plateSize, hex: "#9A9CA0", intensity: 0.9, position: SIMD3<Float>(0, plateY, 0))
        plate.model?.materials = [material(hex: "#9A9CA0", intensity: 0.9, isMetallic: true)]
        markShadowCaster(plate)
        connector.addChild(plate)

        let inset = plateSize * 0.36
        for x in [-inset, inset] as [Float] {
            for z in [-inset, inset] as [Float] {
                let bolt = ModelEntity(
                    mesh: .generateCylinder(height: plateThickness * 1.8, radius: blockSize * 0.06),
                    materials: [material(hex: "#74777A", intensity: 0.8, isMetallic: true)]
                )
                bolt.name = "connector_bolt"
                bolt.position = SIMD3<Float>(x, plateY + plateThickness * 0.7, z)
                connector.addChild(bolt)
            }
        }
    }

    private static let rigRootPrefix = "rig_root_"

    /// Builds the dynamic rig — visible gear + a spotlight per fixture — from the cue's fixtures, placed
    /// by `RigPlacement` (any number/type, spread across their zones). Reconciles like `syncStageLayout`:
    /// it only rebuilds when the fixture set changes (a new AI look with different fixtures), so cue
    /// switches and per-cue relights don't churn the geometry. Each fixture's spotlight is named
    /// `spot_<fixtureId>` so `apply` can drive it.
    private static func syncRig(cue: LightingCue?, layout: StageLayout, in root: Entity) {
        guard let cue else { return }

        // The signature includes the aim offset AND the manual position, not just id|model|zone: a
        // rotation ("Light N turn right 60") or a live drag changes only those, and without them in the
        // signature the rig would NOT rebuild on the live 1:1 stage, so the beam/head would never re-aim
        // (or re-seat). Pan/tilt are rounded to whole degrees so sub-degree float noise can't churn the
        // rig. (v1 hard-cuts on rebuild — no smooth pan animation; see SPEC 13 Caveats.)
        let signature = cue.fixtureGroups
            .map {
                let pan = Int(($0.aimOffset?.panDegrees ?? 0).rounded())
                let tilt = Int(($0.aimOffset?.tiltDegrees ?? 0).rounded())
                let manual = $0.manualPosition.map { "\($0.x),\($0.y),\($0.z)" } ?? "-"
                return "\($0.id)|\($0.renderModel.rawValue)|\($0.zone.rawValue)|\(pan)|\(tilt)|\(manual)"
            }
            .sorted()
            .joined(separator: ",")
        let expectedName = "\(rigRootPrefix)\(abs(signature.hashValue))"
        if root.children.contains(where: { $0.name == expectedName }) {
            return
        }

        for child in root.children where child.name.hasPrefix(rigRootPrefix) {
            child.removeFromParent()
        }

        let rig = Entity()
        rig.name = expectedName

        // Spread fixtures evenly within each zone: each fixture's slot is its index among the fixtures
        // sharing its zone, and count is how many share it.
        var zoneTotals: [StageZone: Int] = [:]
        for fixture in cue.fixtureGroups {
            zoneTotals[fixture.zone, default: 0] += 1
        }
        var zoneSlots: [StageZone: Int] = [:]
        for (index, fixture) in cue.fixtureGroups.enumerated() {
            let slot = zoneSlots[fixture.zone, default: 0]
            zoneSlots[fixture.zone] = slot + 1
            let placement = RigPlacement.resolvedPlacement(
                fixture: fixture,
                slot: slot,
                count: zoneTotals[fixture.zone] ?? 1,
                layout: layout
            )
            addRigFixture(fixture, lightNumber: index + 1, at: placement, layout: layout, to: rig)
        }

        root.addChild(rig)
    }

    /// Instantiates one fixture's visible gear + its (initially dark) spotlight at a placement, plus a
    /// floating "Light N" label so it can be addressed by voice ("close the light N"). The support policy
    /// (`RigPlacement.support`) decides physics: a fixture whose resolved position sits under the truss
    /// footprint and high enough hangs (no post); anything else grows a floor stand up to it — so no light
    /// ever floats. `apply` drives color/intensity later.
    private static func addRigFixture(
        _ fixture: FixtureGroup,
        lightNumber: Int,
        at placement: (position: Vector3Meters, aim: Vector3Meters),
        layout: StageLayout,
        to rig: Entity
    ) {
        // Physical support from the resolved position (not the zone): floor-stand fixtures grow a post from
        // the floor and their label floats above; truss-hung fixtures get no post and their label drops
        // BELOW the fixture to clear the truss. This covers side booms and manually-dragged lights too.
        let support = RigPlacement.support(forPosition: placement.position, layout: layout)

        // The resting aim = the zone-derived direction rotated by the fixture's user-authored aimOffset
        // (SPEC 13). A nil/zero offset returns the zone direction unchanged, so existing / AI looks aim
        // exactly as before (the tilt-doubling trap is avoided by using this NEW field, not fineControl).
        // This one direction drives the head model, the spotlight orientation, and the effect baseAim so
        // the geometry and beam stay coherent.
        let baseDir = scenePoint(placement.aim) - scenePoint(placement.position)
        let baseUnit = simd_length(baseDir) > 0.0001 ? simd_normalize(baseDir) : SIMD3<Float>(0, 0, -1)
        let offset = fixture.aimOffset ?? .zero
        let restingDir = LightEffectSystem.aim(base: baseUnit,
                                               panDegrees: offset.panDegrees,
                                               tiltDegrees: offset.tiltDegrees)

        if fixture.renderModel == .laser {
            // The laser builds its own emitter + visible aerial beam fan; the spotlight below still adds
            // a faint colour spill on the surfaces the cone reaches. (v1: the visible beam fan itself uses
            // a fixed orientation — only the spot cone spill follows the aim offset; see SPEC 13 Caveats.)
            addLaserProjector(name: "laser_\(fixture.id)", to: rig, source: placement.position, beamColorHex: fixture.color.value)

            // If the laser isn't hung under the truss (e.g. moved off it), grow a floor stand up to the
            // emitter head so it doesn't float. Truss-hung lasers (the default stageBack) get no post.
            if case .floorStand(let topY) = support {
                if let post = strut(named: "laser_\(fixture.id)_post",
                                    from: Vector3Meters(x: placement.position.x, y: 0.0, z: placement.position.z),
                                    to: Vector3Meters(x: placement.position.x, y: topY, z: placement.position.z),
                                    radius: 0.035, hex: "#3A3D42", intensity: 0.72) {
                    post.name = "laser_\(fixture.id)_post"
                    rig.addChild(post)
                }
            }
        } else {
            // Every other type renders as its real model-type geometry (moving head, PAR, strobe bar,
            // blinder, fresnel…) at ~0.4 m, aimed front-first along the resting direction. `spot_<id>`/
            // label/pick proxy below are separate entities and keep driving the actual light.
            let model = FixtureRealityModel.makeStageFixture(
                for: fixture.renderModel,
                targetHeight: sceneLength(0.4),
                aim: restingDir
            )
            model.name = "model_\(fixture.id)"
            model.position = scenePoint(placement.position)
            markShadowCasterRecursively(model)
            rig.addChild(model)

            // Floor-stand fixtures (FOH, side booms, or anything dragged off the truss) read as "standing":
            // drop a slim post from the floor up to just under the fixture so it doesn't appear to float.
            // Truss-hung types hang as-is (no post).
            if case .floorStand(let topY) = support {
                if let post = strut(named: "model_\(fixture.id)_post",
                                    from: Vector3Meters(x: placement.position.x, y: 0.0, z: placement.position.z),
                                    to: Vector3Meters(x: placement.position.x, y: topY, z: placement.position.z),
                                    radius: 0.035, hex: "#3A3D42", intensity: 0.72) {
                    post.name = "model_\(fixture.id)_post"
                    rig.addChild(post)
                }
            }
        }

        addStageSpotLight(
            name: "spot_\(fixture.id)",
            to: rig,
            from: placement.position,
            aim: placement.aim,
            restingAimDirection: restingDir,
            beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees
        )

        // Three-tier aerial-cone visibility (SPEC 19): `.full` for upstage/back wash + moving-head beams,
        // `.faint` (alpha × `faintAlphaScale`) for front-of-house key/wash and side fixtures — a see-through
        // veil so the stage stays visible even though the cone crosses the viewer's line of sight — and
        // `.hidden` for lasers, which draw their own fan (`addLaserProjector`), preserving the old
        // `!= .laser` skip (footgun ①).
        let beamVisibility = RigPlacement.aerialBeamConeVisibility(model: fixture.renderModel, zone: fixture.zone)
        if beamVisibility != .hidden {
            addSpotBeamCone(
                name: "spotbeam_\(fixture.id)",
                to: rig,
                source: placement.position,
                aim: restingDir,
                throwMeters: placement.position.distance(to: placement.aim),
                beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees,
                colorHex: fixture.color.value,
                isFaint: beamVisibility == .faint
            )
        }

        addLightLabel(number: lightNumber, near: placement.position, mountedAbove: support.isFloorStand, to: rig)
        addLightPickTarget(
            number: lightNumber,
            near: placement.position,
            to: rig
        )
    }

    private static let lightPickPrefix = "lightpick_"
    private static let lightPickRingPrefix = "lightpick_ring_"

    /// A near-invisible, hit-testable proxy sphere at the fixture so the user can pinch a (physically
    /// tiny, possibly high) fixture to select it for manual control. It carries a faint `UnlitMaterial`
    /// (essentially transparent), a small sphere collider, and an `InputTargetComponent`. A disabled
    /// "selected" ring lives inside it, toggled by `syncSelectionHighlight` when this light is the
    /// selected one. Named `lightpick_<number>` so the tap/drag gestures can parse the number off the
    /// tapped ancestor.
    ///
    /// **BUG 1 fix — chosen approach: shrink the proxy + drop its `HoverEffectComponent`.** Before SPEC 02
    /// this proxy was a 0.16 m-radius (~0.32 m diameter) sphere carrying a `HoverEffectComponent`; once
    /// real ~0.4 m fixture geometry (`model_<id>`) landed at the same spot, the system gaze highlight
    /// painted this oversized invisible sphere as a glowing orb engulfing the fixture. We keep the input
    /// target on THIS proxy (not on `model_<id>`) because every existing path — gaze/pinch selection,
    /// pinch-to-dim, and the selection ring — keys off the `lightpick_<n>` name and hierarchy;
    /// moving the input target onto the sibling `model_<id>` would break `lightNumber(forPickTarget:)`'s
    /// walk-up (the model is not a `lightpick_` ancestor). Instead we (a) shrink the collider drastically
    /// to `sceneLength(0.06)` so it hugs the fixture rather than ballooning past it, and (b) remove the
    /// `HoverEffectComponent` entirely so it never renders as an orb. The fixture still gaze-selects and
    /// pinch-drags exactly as before; it just no longer glows a bubble over the gear.
    private static func addLightPickTarget(
        number: Int,
        near position: Vector3Meters,
        to rig: Entity
    ) {
        let pick = ModelEntity(
            mesh: .generateSphere(radius: sceneLength(0.06)),
            // Alpha kept just above zero: essentially invisible, but the mesh still hit-tests.
            materials: [UnlitMaterial(color: UIColor(white: 1, alpha: 0.02))]
        )
        pick.name = "\(lightPickPrefix)\(number)"
        // Sit the pick proxy ON THE FIXTURE itself (not at the label's +0.34 spot) so the floating
        // "Light N" label is no longer trapped inside this sphere / its selection ring — you pinch
        // the light, the ring haloes the light, and the label reads clearly in the clear space above it.
        pick.position = scenePoint(position)
        pick.generateCollisionShapes(recursive: false)
        pick.components.set(InputTargetComponent())
        // NOTE: deliberately NO HoverEffectComponent — see the doc comment above. The system hover
        // highlight on this invisible sphere is exactly the glowing-orb bug (BUG 1).

        // Selection ring: an UnlitMaterial torus so it reads at any brightness (even when the light is
        // off), starting disabled. `syncSelectionHighlight` enables exactly the selected light's ring.
        let ring = ModelEntity(
            mesh: selectionRingMesh(),
            materials: [UnlitMaterial(color: UIColor(LumaStageDesign.coolBlue))]
        )
        ring.name = "\(lightPickRingPrefix)\(number)"
        ring.isEnabled = false
        pick.addChild(ring)

        rig.addChild(pick)
    }

    /// A flat ring (thin torus lying in X-Y so it faces the audience/viewer) used as the selection
    /// halo around a pick proxy. RealityKit has no `generateTorus`, so it's a small `MeshDescriptor`
    /// torus — mirrors the observatory's ring approach. Cached: every ring is identical.
    private static var cachedSelectionRingMesh: MeshResource?
    private static func selectionRingMesh() -> MeshResource {
        if let cached = cachedSelectionRingMesh {
            return cached
        }
        let majorRadius = sceneLength(0.20)
        let minorRadius = sceneLength(0.012)
        let majorSegments = 48
        let minorSegments = 10

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0..<majorSegments {
            let theta = Float(i) / Float(majorSegments) * 2 * .pi
            // Ring lies in the X-Y plane (faces +Z, toward the viewer), matching the floating labels.
            let center = SIMD3<Float>(cos(theta) * majorRadius, sin(theta) * majorRadius, 0)
            let radial = SIMD3<Float>(cos(theta), sin(theta), 0)
            for j in 0..<minorSegments {
                let phi = Float(j) / Float(minorSegments) * 2 * .pi
                let offset = radial * (cos(phi) * minorRadius) + SIMD3<Float>(0, 0, sin(phi) * minorRadius)
                positions.append(center + offset)
            }
        }
        for i in 0..<majorSegments {
            for j in 0..<minorSegments {
                let a = UInt32(i * minorSegments + j)
                let b = UInt32(i * minorSegments + (j + 1) % minorSegments)
                let c = UInt32(((i + 1) % majorSegments) * minorSegments + j)
                let d = UInt32(((i + 1) % majorSegments) * minorSegments + (j + 1) % minorSegments)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "selection_ring")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = (try? MeshResource.generate(from: [descriptor])) ?? .generateSphere(radius: sceneLength(0.18))
        cachedSelectionRingMesh = mesh
        return mesh
    }

    /// Toggles the per-light selection rings so exactly the selected light's halo shows. Subtle but
    /// readable at any cue brightness (the ring is `UnlitMaterial`, so it doesn't depend on the lights).
    /// Walks the hierarchy by hand — RealityKit's `Entity` has no built-in recursive enumerator.
    private static func syncSelectionHighlight(selectedLightNumber: Int?, in root: Entity) {
        forEachDescendant(of: root) { entity in
            guard entity.name.hasPrefix(lightPickRingPrefix) else { return }
            let number = Int(entity.name.dropFirst(lightPickRingPrefix.count))
            entity.isEnabled = (number != nil && number == selectedLightNumber)
        }
    }

    /// Depth-first walk of an entity's whole subtree (the node itself + every descendant).
    private static func forEachDescendant(of entity: Entity, _ body: (Entity) -> Void) {
        body(entity)
        for child in entity.children {
            forEachDescendant(of: child, body)
        }
    }

    private static let dragIntensityPerPoint = 1.0 / 400.0 // vertical points → 0...1 intensity; tune on device

    /// Walks a tapped entity up to the nearest `lightpick_<n>` ancestor and parses its 1-based light
    /// number, or `nil` if the tap didn't land on a pick proxy (→ deselect).
    private static func lightNumber(forPickTarget tapped: Entity) -> Int? {
        var node: Entity? = tapped
        while let current = node {
            if current.name.hasPrefix(lightPickPrefix), !current.name.hasPrefix(lightPickRingPrefix) {
                return Int(current.name.dropFirst(lightPickPrefix.count))
            }
            node = current.parent
        }
        return nil
    }

    /// A small floating "Light N" name tag above a fixture (RealityKit text, unlit so it reads at any
    /// brightness, on a dark backing). Faces +Z (toward the audience/viewer). Lets the user see which
    /// number to say for single-light commands.
    private static func addLightLabel(number: Int, near position: Vector3Meters, mountedAbove: Bool, to rig: Entity) {
        let label = makeLabelEntity(StageLightLabel.displayName(number: number))
        label.name = "light_label_\(number)"
        // FOH labels float above the fixture; truss-hung labels drop below it (toward the deck) so they
        // clear the truss beams/connectors instead of poking into them. The label faces +Z (the
        // audience), so it reads from the front either way.
        let offsetY = mountedAbove ? sceneLength(0.34) : -sceneLength(0.34)
        label.position = scenePoint(position) + SIMD3<Float>(0, offsetY, 0)
        rig.addChild(label)
    }

    private static func makeLabelEntity(_ text: String) -> Entity {
        let container = Entity()

        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.004,
            font: .systemFont(ofSize: 0.12, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let textEntity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let bounds = textEntity.model?.mesh.bounds ?? mesh.bounds
        // Recenter the glyphs (generateText pivots at the baseline origin) and float them in front.
        textEntity.position = SIMD3<Float>(-bounds.center.x, -bounds.center.y, 0.004)
        container.addChild(textEntity)

        let backing = ModelEntity(
            mesh: .generatePlane(width: bounds.extents.x + 0.06, height: bounds.extents.y + 0.045, cornerRadius: 0.02),
            materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1.0))]
        )
        container.addChild(backing)
        return container
    }

    /// A front-of-house lighting stand: a tripod-footed vertical column carrying a par/fresnel-style
    /// fixture at `source`, the exact point the matching `spot_frontLight_*` emits from, aimed at the
    /// stage. Makes the otherwise-invisible front light read as real gear standing in the audience area
    /// — so the user can see where the light comes from. Stage geometry (not the opaque venue), so it
    /// stays visible in room-spill passthrough too.
    private static func addFrontLightStand(name: String, to root: Entity, at source: Vector3Meters, aim target: Vector3Meters) {
        let stand = Entity()
        stand.name = name

        // Vertical column from the floor up to just under the fixture.
        let columnTopY = max(0.3, source.y - 0.14)
        if let column = strut(named: "\(name)_column",
                              from: Vector3Meters(x: source.x, y: 0.0, z: source.z),
                              to: Vector3Meters(x: source.x, y: columnTopY, z: source.z),
                              radius: 0.035, hex: "#3A3D42", intensity: 0.72) {
            stand.addChild(column)
        }

        // Tripod feet splayed from a hub low on the column to the floor.
        let hub = Vector3Meters(x: source.x, y: min(0.6, columnTopY), z: source.z)
        let spread = 0.55
        for leg in 0..<3 {
            let angle = Double(leg) / 3.0 * 2.0 * Double.pi
            let foot = Vector3Meters(x: source.x + cos(angle) * spread, y: 0.02, z: source.z + sin(angle) * spread)
            if let legEntity = strut(named: "\(name)_leg_\(leg)", from: hub, to: foot, radius: 0.022, hex: "#3A3D42", intensity: 0.66) {
                stand.addChild(legEntity)
            }
        }

        // Fixture aimed at the stage: its barrel axis points along the throw direction.
        let aimVector = scenePoint(target) - scenePoint(source)
        let aimUnit = simd_length(aimVector) > 0.0001 ? simd_normalize(aimVector) : SIMD3<Float>(0, 0, -1)
        let headOrientation = orientation(from: SIMD3<Float>(0, 1, 0), to: aimUnit)

        // Yoke bracket between the column top and the can.
        let yoke = box(name: "\(name)_yoke", width: 0.10, height: 0.05, depth: 0.10, hex: "#26292F", intensity: 0.8,
                       position: scenePoint(Vector3Meters(x: source.x, y: columnTopY + 0.04, z: source.z)))
        yoke.model?.materials = [material(hex: "#26292F", intensity: 0.8, isMetallic: true)]
        markShadowCaster(yoke)
        stand.addChild(yoke)

        // Par-can body centred on the emit point, barrel along the throw.
        let can = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.30), radius: sceneLength(0.14)),
            materials: [material(hex: "#1B1E24", intensity: 0.85, isMetallic: true)]
        )
        can.name = "\(name)_can"
        can.position = scenePoint(source)
        can.orientation = headOrientation
        markShadowCaster(can)
        stand.addChild(can)

        // Warm lens disc at the front of the can so the emitter reads as a glowing source.
        let lens = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.02), radius: sceneLength(0.125)),
            materials: [material(hex: "#FFE7B8", intensity: 0.95)]
        )
        lens.name = "\(name)_lens"
        lens.position = scenePoint(source) + aimUnit * sceneLength(0.16)
        lens.orientation = headOrientation
        stand.addChild(lens)

        root.addChild(stand)
    }

    /// A metal strut (cylinder) spanning two model-space points — shared by the front-light stand's
    /// column and tripod legs. Mirrors `trussMember`'s start→end orientation math.
    private static func strut(named name: String, from a: Vector3Meters, to b: Vector3Meters, radius: Double, hex: String, intensity: Double) -> ModelEntity? {
        let start = scenePoint(a)
        let end = scenePoint(b)
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.001 else {
            return nil
        }

        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: sceneLength(radius)),
            materials: [material(hex: hex, intensity: intensity, isMetallic: true)]
        )
        entity.name = name
        entity.position = (start + end) / 2
        entity.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: direction / length)
        markShadowCaster(entity)
        return entity
    }

    /// A neutral, light-grey performer stand-in centred where the front light aims. An empty deck gives
    /// the coloured front light nothing to land on, so a cue colour change is invisible; a matte mid-grey
    /// figure takes on the front-light colour at a glance and casts a shadow that shows the beam. It is
    /// stage geometry (not part of the opaque venue), so it stays visible in room-spill passthrough too.
    private static func addPerformerStandIn(to root: Entity, layout: StageLayout) {
        guard let stageBase = layout.objects.first(where: { $0.type == .stageBase }),
              let stageSize = stageBase.size else {
            return
        }

        let deckTopY = stageBase.position.y + stageSize.height / 2
        // SPEC 22: the user can place the performer in the tabletop editor (persisted in
        // `layout.performerPosition`); use its X/Z when set, else the default centre-deck stand. Y is always
        // the deck top so the feet rest on the deck. The front/spot aim tracking follows automatically via
        // `RigPlacement.resolvedPlacement` (used by `syncRig`), so no change to `syncRig` is needed here.
        let standX = layout.performerPosition?.x ?? stageBase.position.x
        let standZ = layout.performerPosition?.z ?? (stageBase.position.z + stageSize.depth * 0.12)

        let feet = Vector3Meters(x: standX, y: deckTopY, z: standZ)
        let plan = HumanoidFigurePlan.make(feet: feet)
        let skin = mannequinMaterial()        // one shared instance — uniform surface, single allocation

        let performer = Entity()
        performer.name = "performer_stand_in"

        // Smooth limbs: a cylinder per limb, capped at both ends by the joint spheres below (same radius),
        // so each arm/leg reads as one seamless rounded tube.
        for (index, bone) in plan.bones.enumerated() {
            if let entity = limbBone(
                name: "performer_bone_\(index)_\(bone.role.rawValue)",
                from: bone.a,
                to: bone.b,
                radius: bone.radius,
                material: skin
            ) {
                performer.addChild(entity)
            }
        }

        // Rounded joint caps and hand/foot stubs — radius matches the limb so the surface stays smooth.
        for joint in plan.joints where joint.capRadius > 0 {
            performer.addChild(sphereJoint(
                name: "performer_joint_\(joint.id)",
                center: joint.position,
                radius: joint.capRadius,
                material: skin
            ))
        }

        // Rounded body masses (torso / hips / feet) as scaled spheres — the smooth, blobby silhouette.
        for blob in plan.blobs {
            performer.addChild(blobMass(
                name: "performer_\(blob.id)",
                center: blob.center,
                radius: blob.radius,
                scale: blob.scale,
                material: skin
            ))
        }

        // Big round head; its bottom overlaps the torso so there is no neck seam. Blank and featureless,
        // matching the reference — and a procedural face would be the uncanny trap anyway.
        performer.addChild(blobMass(
            name: "performer_head",
            center: plan.headCenter,
            radius: plan.headRadius,
            scale: Vector3Meters(x: 1, y: 1, z: 1),
            material: skin
        ))

        root.addChild(performer)
    }

    /// `true` swaps the performer to a flat `SimpleMaterial` (consistent with the rest of the rig) for an
    /// on-device A/B against the PBR look; `false` uses the smooth white material below.
    private static let useMatteSimpleMaterialForPerformer = false

    /// The performer's skin. A near-white smooth matte `PhysicallyBasedMaterial`, modelled on the
    /// "Meccha Chameleon" character (a pure-white, paintable blob). It is the one object whose purpose is
    /// to *show how coloured light lands on a body*, so it earns proper Lambert falloff and a soft sheen
    /// (the beam gradient reads across the figure) — worth being the only non-`SimpleMaterial` surface in
    /// the scene. White maximises colour pickup (a saturated front light tints it to a true hue) and
    /// metallic 0 keeps it dielectric. (`UnlitMaterial` is avoided — it would ignore the cue lights.)
    private static func mannequinMaterial() -> RealityKit.Material {
        if useMatteSimpleMaterialForPerformer {
            return material(hex: "#EDEDEA", intensity: 1.0)
        }
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = PhysicallyBasedMaterial.BaseColor(
            tint: UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0)   // near-white, slight headroom
        )
        pbr.roughness = 0.62   // smooth matte, like the printed/game model
        pbr.metallic = 0.0     // dielectric → coloured light reads as its true hue
        pbr.specular = 0.40    // a little soft sheen on the rounded surface
        return pbr
    }

    /// A rounded body mass: a sphere stretched per-axis into an ovoid. The torso/hips/feet/head are built
    /// from these so the figure reads as smooth blobs rather than boxes. `scale` is dimensionless factors.
    private static func blobMass(name: String, center: Vector3Meters, radius: Double, scale: Vector3Meters, material: RealityKit.Material) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: sceneLength(radius)),
            materials: [material]
        )
        entity.name = name
        entity.position = scenePoint(center)
        entity.scale = SIMD3<Float>(Float(scale.x), Float(scale.y), Float(scale.z))
        markShadowCaster(entity)
        return entity
    }

    /// A sphere at a joint, wearing the supplied material and casting shadow. Mirrors the lattice-node
    /// spheres; a sphere can't come from `strut`, so this is its companion.
    private static func sphereJoint(name: String, center: Vector3Meters, radius: Double, material: RealityKit.Material) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: sceneLength(radius)),
            materials: [material]
        )
        entity.name = name
        entity.position = scenePoint(center)
        markShadowCaster(entity)
        return entity
    }

    /// `strut`'s twin for limbs: a cylinder spanning two model-space points, but carrying an injectable
    /// material (the performer's PBR skin) instead of `strut`'s hardcoded metal finish. `strut` stays as
    /// is for the metal stands.
    private static func limbBone(name: String, from a: Vector3Meters, to b: Vector3Meters, radius: Double, material: RealityKit.Material) -> ModelEntity? {
        let start = scenePoint(a)
        let end = scenePoint(b)
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.001 else {
            return nil
        }

        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: sceneLength(radius)),
            materials: [material]
        )
        entity.name = name
        entity.position = (start + end) / 2
        entity.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: direction / length)
        markShadowCaster(entity)
        return entity
    }

    @discardableResult
    private static func addStageSpotLight(
        name: String,
        to root: Entity,
        from sourceModel: Vector3Meters,
        aim aimModel: Vector3Meters,
        restingAimDirection: SIMD3<Float>? = nil,
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
        spot.light.attenuationRadius = sceneLength(40)   // scene-metre reach; scales with the stage
        spot.shadow = SpotLightComponent.Shadow()

        // visionOS 26 has no `SpotLightComponent.SurroundingsLight`, so in room-spill mode the
        // virtual spotlights cannot illuminate the real passthrough room — the mode still switches
        // to passthrough with the dim effect; real-room spill lighting needs visionOS 27+.

        let position = scenePoint(sourceModel)
        spot.position = position
        // Prefer the caller's resting direction (the zone aim already rotated by the fixture's aimOffset —
        // SPEC 13), falling back to the raw zone aim (position → target) when none is supplied. The dynamic
        // effect system sweeps AROUND this baseAim, so a steady cue holds the beam exactly at restingDir.
        let direction = restingAimDirection ?? (scenePoint(aimModel) - position)
        if simd_length(direction) > 0.0001 {
            // A spotlight emits along its local -Z; aim that axis along the resting direction. Use the
            // shared `lookOrientation` so the geometry aim, the spotlight, and the effect math all agree.
            let aim = simd_normalize(direction)
            spot.orientation = LightEffectSystem.lookOrientation(forward: aim)
            // Capture the resting aim so the dynamic-effects system can sweep around it (effect kind +
            // base lumens are filled in per cue by `apply`).
            spot.components.set(LightEffectComponent(effect: .none, baseAim: aim, baseLumens: 0))
        }

        root.addChild(spot)
        return spot
    }

    private static func addMovingHeadFixture(name: String, to root: Entity, position: Vector3Meters, color: String, lensColor: String) {
        // DECORATION ONLY. The actual illumination comes from the separate `spot_backgroundWash_*`
        // SpotLight entities; this rebuilds the visible "moving head beam" product that hangs under
        // the truss clamp at `basePosition`, aimed down toward the stage. Proportions mirror the
        // observatory's `addMovingHeadBeam`, scaled down to ~0.34m overall and oriented hanging /
        // pointing down instead of standing. All sizes/offsets go through `sceneLength` so the
        // fixture stays correct at any `stageScale`.
        let basePosition = scenePoint(position)

        // Downward aim about X — matches the old fixture's ~-18°..-22° tilt toward the stage.
        // Positive here tips the laid-horizontal head's front face down toward -Y (see headAxis).
        let tilt: Float = .pi / 9   // 20° of downward pitch

        // 1) Clamp/yoke block gripping the truss at the mount point.
        let clamp = box(
            name: "\(name)_clamp",
            width: sceneLength(0.13),
            height: sceneLength(0.055),
            depth: sceneLength(0.12),
            hex: color,
            intensity: 0.82,
            position: basePosition
        )
        clamp.model?.materials = [material(hex: color, intensity: 0.82, isMetallic: true)]
        markShadowCaster(clamp)
        root.addChild(clamp)

        // 2) Heavy base body just below the clamp.
        let base = box(
            name: "\(name)_base",
            width: sceneLength(0.165),
            height: sceneLength(0.07),
            depth: sceneLength(0.15),
            hex: color,
            intensity: 0.78,
            position: basePosition + SIMD3<Float>(0, sceneLength(-0.06), 0)
        )
        base.model?.materials = [material(hex: color, intensity: 0.78, isMetallic: true)]
        markShadowCaster(base)
        root.addChild(base)

        // 3) Two yoke side-arms dropping down to cradle the head.
        let armY = sceneLength(-0.135)
        for (suffix, dx) in [("left", sceneLength(-0.085)), ("right", sceneLength(0.085))] {
            let arm = box(
                name: "\(name)_arm_\(suffix)",
                width: sceneLength(0.03),
                height: sceneLength(0.155),
                depth: sceneLength(0.065),
                hex: color,
                intensity: 0.8,
                position: basePosition + SIMD3<Float>(dx, armY, 0)
            )
            arm.model?.materials = [material(hex: color, intensity: 0.8, isMetallic: true)]
            markShadowCaster(arm)
            root.addChild(arm)
        }

        // 4) Cylindrical HEAD between the arms. `generateCylinder`'s axis is Y, so rotate it to lay
        // horizontal and tilt it down: a +pi/2 turn about X lays the length axis along +Z, and the
        // extra `tilt` about X pitches that front face past horizontal so the lens points forward
        // and down toward the stage (resulting headAxis ≈ (0, -0.34, 0.94)).
        let headCenter = basePosition + SIMD3<Float>(0, sceneLength(-0.18), sceneLength(0.02))
        let headOrientation = simd_quatf(angle: tilt, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        // Local +Y of the cylinder (its length axis) after the orientation above — the direction the
        // lens face points — used to offset the rim / lens / rear cap along the barrel.
        let headAxis = simd_act(headOrientation, SIMD3<Float>(0, 1, 0))

        let head = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.17), radius: sceneLength(0.05)),
            materials: [material(hex: color, intensity: 0.9, isMetallic: true)]
        )
        head.name = "\(name)_head"
        head.position = headCenter
        head.orientation = headOrientation
        markShadowCaster(head)
        root.addChild(head)

        // Front rim ring — a thin cylinder just ahead of the head's front face.
        let rim = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.018), radius: sceneLength(0.057)),
            materials: [material(hex: color, intensity: 0.7, isMetallic: true)]
        )
        rim.name = "\(name)_rim"
        rim.position = headCenter + headAxis * sceneLength(0.088)
        rim.orientation = headOrientation
        markShadowCaster(rim)
        root.addChild(rim)

        // Glowing front lens (lensColor, translucent, high intensity).
        let lens = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.012), radius: sceneLength(0.044)),
            materials: [material(hex: lensColor, intensity: 0.95, alpha: 0.85)]
        )
        lens.name = "\(name)_lens"
        lens.position = headCenter + headAxis * sceneLength(0.097)
        lens.orientation = headOrientation
        root.addChild(lens)

        // Rear cap closing the back of the head barrel.
        let rearCap = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.022), radius: sceneLength(0.052)),
            materials: [material(hex: color, intensity: 0.66, isMetallic: true)]
        )
        rearCap.name = "\(name)_rear_cap"
        rearCap.position = headCenter - headAxis * sceneLength(0.086)
        rearCap.orientation = headOrientation
        markShadowCaster(rearCap)
        root.addChild(rearCap)
    }

    // MARK: - Laser projector (visible aerial beams)

    /// Model-space throw of the laser fan: forward toward the audience (+Z) and angled down over the
    /// stage. The fan spreads horizontally about vertical, so the beams read as a wall of light over
    /// the crowd. `scenePoint` only scales+translates, so model axes == scene axes for this direction.
    private static let laserBaseDirection = simd_normalize(SIMD3<Float>(0, -0.35, 1))
    private static let laserFanHalfAngle: Float = 30 * .pi / 180
    private static let laserBeamCount = 7
    /// Model-space beam throw length and core radius (converted to scene units via `sceneLength`). The
    /// core is thin so it reads as a laser pencil, not a rod; the sheath/particles carry the volume.
    private static let laserBeamLengthMeters = 12.0
    private static let laserCoreRadiusMeters = 0.01

    /// Builds a laser projector: a compact emitter head on the upstage truss plus a fan of volumetric
    /// aerial beams shooting out over the stage. Each beam is two co-axial layers — a thin white-hot
    /// `UnlitMaterial` core and a soft low-alpha glow sheath — so it reads as light in the air, not a
    /// solid rod. The layers are their own light source (a real laser doesn't depend on the room being
    /// lit); `apply` recolors / toggles them per cue via `updateLaserProjector`. This is the show-stopper
    /// fixture: visible beams in the air, not just a cone landing on a surface. (An earlier third layer
    /// of additive haze particles was removed — it read as a weird off-axis speckle at 1:1 scale.)
    private static func addLaserProjector(name: String, to rig: Entity, source: Vector3Meters, beamColorHex: String) {
        let container = Entity()
        container.name = name
        let origin = scenePoint(source)
        let throwOrientation = orientation(from: SIMD3<Float>(0, 1, 0), to: laserBaseDirection)

        // Emitter head: a small dark box (physical gear that stays visible at any cue).
        let body = box(name: "\(name)_body", width: sceneLength(0.26), height: sceneLength(0.18), depth: sceneLength(0.30), hex: "#15171C", intensity: 0.85, position: origin)
        body.model?.materials = [material(hex: "#15171C", intensity: 0.85, isMetallic: true)]
        markShadowCaster(body)
        container.addChild(body)

        // Glowing aperture disc the beams emit from.
        let aperture = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.03), radius: sceneLength(0.075)),
            materials: [UnlitMaterial(color: laserBeamUIColor(hex: beamColorHex, intensity: 1))]
        )
        aperture.name = "\(name)_aperture"
        aperture.orientation = throwOrientation
        aperture.position = origin + laserBaseDirection * sceneLength(0.18)
        container.addChild(aperture)

        // The beam fan. Each beam is two co-axial layers so it reads as light in the air, not a solid
        // rod: (1) a thin, near-white-hot core, and (2) a wider low-alpha glow sheath that bleeds colour
        // outward and softens the silhouette. Both share the beam's orientation (the cylinder mesh's
        // local +Y == the beam direction).
        let config = LaserScatterConfig.default
        let beamLength = sceneLength(laserBeamLengthMeters)
        let coreRadius = sceneLength(laserCoreRadiusMeters)
        let sheathRadius = sceneLength(LaserScatterMath.sheathRadius(coreRadiusMeters: laserCoreRadiusMeters, config: config))
        for index in 0..<laserBeamCount {
            let fraction = laserBeamCount <= 1 ? 0 : Float(index) / Float(laserBeamCount - 1) * 2 - 1   // -1...1
            let yaw = fraction * laserFanHalfAngle
            let beamOrientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * throwOrientation
            let center = origin + simd_act(beamOrientation, SIMD3<Float>(0, 1, 0)) * (beamLength / 2)

            // Layer 1: the thin, near-white-hot core.
            let core = ModelEntity(
                mesh: .generateCylinder(height: beamLength, radius: coreRadius),
                materials: [UnlitMaterial(color: laserCoreUIColor(hex: beamColorHex, intensity: 1))]
            )
            core.name = "\(name)_beam_\(index)"
            core.orientation = beamOrientation
            core.position = center
            container.addChild(core)

            // Layer 2: the soft translucent glow sheath.
            let sheath = ModelEntity(
                mesh: .generateCylinder(height: beamLength, radius: sheathRadius),
                materials: [UnlitMaterial(color: laserSheathUIColor(hex: beamColorHex, intensity: 1))]
            )
            sheath.name = "\(name)_sheath_\(index)"
            sheath.orientation = beamOrientation
            sheath.position = center
            container.addChild(sheath)
        }

        rig.addChild(container)
    }

    /// A laser beam's emissive colour: the cue's hex dimmed by intensity, kept slightly translucent so
    /// overlapping beams build brightness like real laser haze.
    private static func laserBeamUIColor(hex: String, intensity: Double) -> UIColor {
        let rgb = (RGBComponents(hex: hex) ?? .white).dimmed(by: max(0, min(intensity, 1)))
        return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 0.85)
    }

    /// The white-hot beam core colour (cue hue lerped toward white). See `LaserScatterMath.coreRGBA`.
    private static func laserCoreUIColor(hex: String, intensity: Double) -> UIColor {
        let c = LaserScatterMath.coreRGBA(hex: hex, intensity: intensity)
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// The low-alpha glow-sheath colour (saturated cue hue). See `LaserScatterMath.sheathRGBA`.
    private static func laserSheathUIColor(hex: String, intensity: Double) -> UIColor {
        let c = LaserScatterMath.sheathRGBA(hex: hex, intensity: intensity)
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    /// Per-cue update for a laser: recolor both beam layers (core + sheath) to the resolved cue colour
    /// and hide the beams when the fixture is effectively off (the emitter body stays). The cone spilling
    /// colour onto surfaces is still driven by the fixture's `spot_<id>` in `updateSpotLight`.
    private static func updateLaserProjector(named name: String, in root: Entity, colorHex: String, intensity: Double) {
        guard let container = root.findEntity(named: name) else {
            return
        }

        let beamsVisible = LaserScatterMath.beamsVisible(intensity)
        let coreColor = laserCoreUIColor(hex: colorHex, intensity: intensity)
        let sheathColor = laserSheathUIColor(hex: colorHex, intensity: intensity)
        let apertureColor = laserBeamUIColor(hex: colorHex, intensity: max(0.3, intensity))
        for child in container.children {
            guard let model = child as? ModelEntity else { continue }
            if child.name.contains("_beam_") {
                child.isEnabled = beamsVisible
                model.model?.materials = [UnlitMaterial(color: coreColor)]
            } else if child.name.contains("_sheath_") {
                child.isEnabled = beamsVisible
                model.model?.materials = [UnlitMaterial(color: sheathColor)]
            } else if child.name.hasSuffix("_aperture") {
                child.isEnabled = beamsVisible
                model.model?.materials = [UnlitMaterial(color: apertureColor)]
            }
        }
    }

    // MARK: - Volumetric spotlight beam (haze)

    /// Builds a non-laser fixture's visible aerial cone: a SINGLE translucent outer shell (the wider
    /// "sheath" cone) so the beam path reads as light in the air, not just a spot landing on a surface
    /// (SPEC 19). It is deliberately one thin hollow cone, not a filled/stacked volume: two co-axial cones
    /// (the old core + sheath) plus overlap from neighbouring fixtures stacked enough alpha to read opaque
    /// and occlude the stage behind the beam. One low-alpha shell lets the viewer see straight through the
    /// cone to the stage. It is its own light source (a `UnlitMaterial`, so it doesn't depend on the room
    /// being lit) and follows the same `restingDir` as the `model_<id>`/`spot_<id>`. Recolored/gated per cue
    /// by `updateSpotBeam`. No particles (see CLAUDE.md). (The inner-core colour/geometry math in
    /// `SpotBeamScatterMath` is retained — it is smoke-test-pinned — but no longer rendered.)
    private static func addSpotBeamCone(
        name: String,
        to rig: Entity,
        source: Vector3Meters,
        aim: SIMD3<Float>,
        throwMeters: Double,
        beamAngleDegrees: Double,
        colorHex: String,
        isFaint: Bool
    ) {
        let container = Entity()
        container.name = name

        // The cone tip sits on the fixture and its base must land on the *actual* aim target (the deck /
        // performer), NOT a fixed distance: a hardcoded 9 m overshot the deck by metres, so the fat end of
        // every front-light cone reached the viewer at the origin and filled the field of view. Derive the
        // length from the throw (fixture → aim target) and floor it so a very short throw still shows a stub.
        let beamLengthMeters = max(throwMeters, 1.0)
        let length = sceneLength(beamLengthMeters)
        let apex = scenePoint(source)
        // The cone mesh has its apex at the local origin and opens toward +Y, so aim that +Y axis along the
        // resting direction and seat the apex on the fixture — cone tip at the light, opening toward aim.
        let direction = simd_length(aim) > 0.0001 ? simd_normalize(aim) : SIMD3<Float>(0, -1, 0)
        let coneOrientation = orientation(from: SIMD3<Float>(0, 1, 0), to: direction)

        // A single outer shell — the wider "sheath" cone. Its radius scales with the derived length so the
        // cone stays the right girth for its (now shorter) throw instead of the old 9 m spread. The core
        // (inner, brighter) cone was dropped: a lone low-alpha shell reads see-through so the stage stays
        // visible behind the beam, whereas core + sheath stacked to near-opaque.
        let sheathRadius = sceneLength(SpotBeamScatterMath.sheathBaseRadius(lengthMeters: beamLengthMeters, beamAngleDegrees: beamAngleDegrees))
        let sheath = ModelEntity(
            mesh: beamConeMesh(length: length, baseRadius: sheathRadius),
            materials: [spotBeamSheathMaterial(hex: colorHex, intensity: 1, beamAngleDegrees: beamAngleDegrees, isFaint: isFaint)]
        )
        sheath.name = "\(name)_sheath"
        sheath.position = apex
        sheath.orientation = coneOrientation
        container.addChild(sheath)

        // Pure visual: no shadow marking (the cone must not block the beam) and no input/collision (it must
        // not be selectable or steal the `lightpick_<n>` hit).
        rig.addChild(container)
    }

    /// A hand-built cone mesh: apex at the local origin, base ring of `segments` points at radius
    /// `baseRadius` and y = `length`, joined apex→ring[i]→ring[i+1] as a triangle fan side surface (the
    /// base cap is omitted — the side surface alone reads as the beam). Modelled on `torusMesh` /
    /// selection_ring's `MeshDescriptor` idiom because RealityKit ships no `generateCone`; falls back to a
    /// cylinder if descriptor generation fails.
    private static func beamConeMesh(length: Float, baseRadius: Float, segments: Int = 24) -> MeshResource {
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0)] // apex at index 0
        for i in 0..<segments {
            let theta = Float(i) / Float(segments) * 2 * .pi
            positions.append(SIMD3<Float>(cos(theta) * baseRadius, length, sin(theta) * baseRadius))
        }
        var indices: [UInt32] = []
        for i in 0..<segments {
            indices.append(contentsOf: [0, UInt32(1 + i), UInt32(1 + (i + 1) % segments)])
        }
        var descriptor = MeshDescriptor(name: "spot_beam_cone")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? .generateCylinder(height: length, radius: baseRadius)
    }

    /// The cone sheath material (saturated cue hue). See `SpotBeamScatterMath.sheathRGBA`. When `isFaint`
    /// (front-of-house key / side fixtures — `RigPlacement.AerialBeamConeVisibility.faint`), the alpha is
    /// scaled down by `SpotBeamScatterConfig.faintAlphaScale` so the cone reads as a see-through veil.
    /// **Material footgun:** on visionOS 26, an `UnlitMaterial` tint's alpha channel does NOT alpha-blend
    /// on its own — the cone rendered as a fully opaque wedge despite a ~0.02 tint alpha. Translucency must
    /// be requested via `blending = .transparent(opacity:)`, so this helper returns the whole material
    /// (opaque tint + transparent blending) rather than a UIColor.
    private static func spotBeamSheathMaterial(hex: String, intensity: Double, beamAngleDegrees: Double, isFaint: Bool) -> UnlitMaterial {
        let c = SpotBeamScatterMath.sheathRGBA(hex: hex, intensity: intensity, beamAngleDegrees: beamAngleDegrees)
        let alpha = isFaint ? c.alpha * SpotBeamScatterConfig.default.faintAlphaScale : c.alpha
        var material = UnlitMaterial(color: UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: Float(alpha)))
        return material
    }

    /// Per-cue update for a spotlight's volumetric cone: recolor the single outer shell to the resolved cue
    /// colour and hide it when the fixture is effectively off. Like the laser, the `UnlitMaterial` swap
    /// hard-cuts (it is not an implicitly-animatable component) — the `spot_<id>` surface spill still
    /// cross-fades in `updateSpotLight` (footgun ②).
    private static func updateSpotBeam(named name: String, in root: Entity, colorHex: String, intensity: Double, beamAngleDegrees: Double, isFaint: Bool) {
        guard let container = root.findEntity(named: name) else {
            return
        }

        let visible = SpotBeamScatterMath.beamVisible(intensity)
        let sheathMaterial = spotBeamSheathMaterial(hex: colorHex, intensity: intensity, beamAngleDegrees: beamAngleDegrees, isFaint: isFaint)
        for child in container.children {
            guard let model = child as? ModelEntity else { continue }
            child.isEnabled = visible
            model.model?.materials = [sheathMaterial]
        }
    }

    /// Relights every fixture in the cue: each `FixtureGroup` drives its own `spot_<id>` spotlight
    /// (built by `syncRig`). Dynamic over any number/type of fixtures. Per-light manual overrides
    /// (keyed by the 1-based light number = cue order) are layered on top — "close the light 3"
    /// fades that one fixture to 0 over the same transition.
    private static func apply(_ cue: LightingCue, overrides: [Int: LightOverride], groupMasters: [Int: Double] = [:], to root: Entity, manualLightNumber: Int? = nil) {
        // The per-fixture effects (AI-authored override > per-type default), from the same shared Plan the
        // debug readout uses, so the rendered movement and the debug panel can never drift. The Plan does
        // the cue-level energy gate internally: a bright/punchy look brings the rig alive (sweeps, strobe,
        // chase) while a calm cue holds the beams steady.
        let effects = LightEffectPlan.effects(for: cue)

        for (index, fixture) in cue.fixtureGroups.enumerated() {
            let override = overrides[index + 1] ?? LightOverride()
            // Fold the group submaster (SPEC 08) into the same resolution: it scales a light with no
            // explicit per-light intensity override; per-light overrides still win. Default 1.0 = no ride.
            let resolved = override.resolved(
                cueColor: fixture.color.value,
                cueIntensity: fixture.intensity,
                groupMaster: groupMasters[index + 1] ?? 1.0
            )
            updateSpotLight(
                named: "spot_\(fixture.id)",
                in: root,
                model: fixture.renderModel,
                color: resolved.color,
                intensity: resolved.intensity,
                beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees,
                // Only the fixture under manual control relights with the snappy transition (so a slider /
                // pinch-drag on IT feels live); every other fixture keeps the cue's cross-fade, so a GO
                // while a light is selected no longer hard-snaps the WHOLE rig over 0.12s.
                transition: (manualLightNumber == index + 1) ? CueTransition(duration: 0.12, easing: "easeOut") : cue.transition
            )

            // Refresh this fixture's dynamic effect + base brightness for the per-frame LightEffectSystem.
            // The resting aim was captured when the spotlight was built, so sweeps modulate around it; a
            // fixture turned dark (override / enabled=false) carries 0 lumens so its strobe/chase stays off.
            if let spot = root.findEntity(named: "spot_\(fixture.id)") as? SpotLight,
               var effectComponent = spot.components[LightEffectComponent.self] {
                effectComponent.effect = effects[index]
                effectComponent.baseLumens = Float(SpotLightRenderMath.lumens(forIntensity: resolved.intensity, model: fixture.renderModel)) * lumenScaleCompensation
                spot.components.set(effectComponent)
            }

            // Lasers drive their visible beam fan (recolor + on/off) on top of the cone spill; every other
            // fixture drives its volumetric cone (SPEC 19) — same source values as the `spot_<id>`, so the
            // cone reflects blackout/override/group-master exactly. Both hard-cut (UnlitMaterial).
            if fixture.renderModel == .laser {
                updateLaserProjector(named: "laser_\(fixture.id)", in: root, colorHex: resolved.color, intensity: resolved.intensity)
            } else {
                updateSpotBeam(
                    named: "spotbeam_\(fixture.id)",
                    in: root,
                    colorHex: resolved.color,
                    intensity: resolved.intensity,
                    beamAngleDegrees: fixture.effectiveFineControl.beamAngleDegrees,
                    isFaint: RigPlacement.aerialBeamConeVisibility(model: fixture.renderModel, zone: fixture.zone) == .faint
                )
            }

        }
    }

    /// Maps a cue transition's `easing` string to the SwiftUI animation that cross-fades the
    /// spotlights. `linear` is the stage default — a steady fade with no ease-in/out ramp, which reads
    /// as a real lighting console crossfade rather than a UI animation.
    private static func animation(for transition: CueTransition) -> Animation {
        switch transition.easing {
        case "linear": return .linear(duration: transition.duration)
        case "easeIn": return .easeIn(duration: transition.duration)
        case "easeOut": return .easeOut(duration: transition.duration)
        default: return .easeInOut(duration: transition.duration)
        }
    }

    // Drives a real RealityKit spotlight from a cue's fixture values. The mutation runs inside a
    // SwiftUI animation transaction so `SpotLightComponent` (an `_ImplicitlyAnimatableBuiltinComponent`)
    // cross-fades color/intensity/cone over the cue's transition instead of hard-cutting.
    private static func updateSpotLight(
        named name: String,
        in root: Entity,
        model: LightingFixtureVisualModel,
        color: String,
        intensity: Double,
        beamAngleDegrees: Double,
        transition: CueTransition
    ) {
        guard let spot = root.findEntity(named: name) as? SpotLight else {
            return
        }

        let rgb = RGBComponents(hex: color) ?? .white
        let lumens = Float(SpotLightRenderMath.lumens(forIntensity: intensity, model: model)) * lumenScaleCompensation
        let cone = SpotLightRenderMath.coneAngles(beamAngleDegrees: beamAngleDegrees)

        withAnimation(Self.animation(for: transition)) {
            spot.light.color = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            spot.light.intensity = lumens
            spot.light.innerAngleInDegrees = Float(cone.inner)
            spot.light.outerAngleInDegrees = Float(cone.outer)
        }

        // Soft-shadow tuning (`Shadow.lightSize` penumbra + per-role `quality`) and digital gobos
        // (`SpotLightComponent.ProjectiveTexture`) are visionOS 27 APIs. On visionOS 26 the default
        // `Shadow()` set at fixture creation is the only shadow config, and `FixtureGroup.gobo`
        // stays data-only (validated and persisted, but not projected).
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

    /// Marks every `ModelEntity` in a subtree as a shadow caster — used for the fixture-type models
    /// (`makeStageFixture`), which are containers of nested mesh entities rather than a single mesh.
    private static func markShadowCasterRecursively(_ entity: Entity) {
        forEachDescendant(of: entity) { node in
            if node is ModelEntity {
                node.components.set(DynamicLightShadowComponent(castsShadow: true))
            }
        }
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
