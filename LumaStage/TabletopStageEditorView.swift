//
//  TabletopStageEditorView.swift
//  LumaStage
//

import SwiftUI

#if os(visionOS)
import RealityKit
import ARKit
import UIKit
import simd

/// The "tabletop" stage editor: a small 3D twin of the project's `StageLayout` that **rests on the user's
/// real table**. It runs in its own MIXED (passthrough) immersive space, and ARKit's
/// `PlaneDetectionProvider` finds a real horizontal table to seat the diorama on — until then the model
/// floats at table height in front of the user (the chosen fallback). The user drags pieces to reposition
/// them and swaps stage/truss presets; edits persist through `AppModel.saveStageLayout`, so the full-scale
/// immersive stage reflects them on return.
///
/// Manipulation rides on the per-object container entities (named `stageobj_<id>`); each piece's meshes
/// carry their own `InputTargetComponent` + collision so hit-testing is precise, and the gestures walk up
/// to the container so the whole object moves/selects as a unit. The body eagerly reads the layout +
/// selection so a model change re-runs the RealityView `update:` closure (a RealityView update closure
/// forms no Observation dependencies of its own — see CLAUDE.md).
struct TabletopStageEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    /// The resting container the diorama hangs under. ARKit moves THIS entity (translation only) onto a
    /// detected table; the control bar is parented here too so it stays put while the model spins. Starts at
    /// the floating-in-front fallback pose until a table is found.
    @State private var placement = Entity()
    /// A turntable under `placement` that holds the diorama and spins it (Y-axis) — separate from
    /// `placement` so rotating the model doesn't carry the control bar around with it. The assembly is
    /// seated on this node's origin.
    @State private var turntable = Entity()
    /// Accumulated turntable yaw in degrees (persists across rebuilds; the ± buttons step it).
    @State private var stageYaw: Double = 0
    // `@GestureState` so the grab offset auto-resets when a drag ends or is cancelled.
    @GestureState private var dragGrabOffset: SIMD3<Float>? = nil

    /// Where the diorama floats (world metres) before a real table is detected: ~table height, an arm's
    /// length in front of the user. Tune on device.
    private static let floatingPlacement = SIMD3<Float>(0, 0.72, -0.6)
    /// A nominal head position for the "nearest surface" tiebreak in `TabletopSurfaceSelection`.
    private static let viewerPosition = Vector3Meters(x: 0, y: 1.2, z: 0)

    var body: some View {
        // Eager reads so a layout- or selection-driven change re-evaluates this body and re-runs the
        // RealityView `update:` closure below. Without them the model would never reflect edits.
        let _ = appModel.stageLayout
        let _ = appModel.selectedStageObjectId

        RealityView { content, attachments in
            placement.name = "tabletop_placement"
            placement.position = Self.floatingPlacement
            turntable.name = "tabletop_turntable"
            placement.addChild(turntable)
            content.add(placement)
            TabletopStageScene.sync(turntable, layout: appModel.stageLayout, selectedId: appModel.selectedStageObjectId)
            TabletopStageScene.seatAssemblyOnSurface(in: turntable)

            if let controls = attachments.entity(for: "controls") {
                // Float the control bar just above and in front of the model. It hangs off `placement`, not
                // the turntable, so it stays facing the user while the model spins.
                controls.position = SIMD3<Float>(0, 0.34, 0.18)
                placement.addChild(controls)
            }
        } update: { _, _ in
            TabletopStageScene.sync(turntable, layout: appModel.stageLayout, selectedId: appModel.selectedStageObjectId)
            TabletopStageScene.seatAssemblyOnSurface(in: turntable)
        } attachments: {
            Attachment(id: "controls") {
                controlBar
            }
        }
        .gesture(selectTap)
        .gesture(moveDrag)
        .task {
            await detectTableAndRest()
        }
        .onAppear {
            appModel.immersiveSpaceState = .open
            // Dismiss the launch/project window for the duration of editing (same reason as the stage
            // space — visionOS otherwise leaves it behind as an empty, draggable system bar).
            dismissWindow(id: AppModel.mainWindowID)
        }
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            openWindow(id: AppModel.mainWindowID)
            // If the editor was closed via system chrome (not the Done button), still end the session so
            // `ContentView` reopens the 1:1 stage space.
            if appModel.isEditingTabletopStage {
                appModel.exitTabletopEditing()
            }
        }
    }

    // MARK: - Real-table detection

    /// Runs ARKit horizontal-plane detection and rests the diorama on the best real table (largest, then
    /// nearest). The model keeps floating in front of the user until a qualifying table appears — and stays
    /// put if the table later drops out of tracking. Degrades silently (model just floats) when plane
    /// detection is unsupported or unauthorized, so the simulator and permission-denied cases still work.
    @MainActor
    private func detectTableAndRest() async {
        guard PlaneDetectionProvider.isSupported else { return }

        let session = ARKitSession()
        let planes = PlaneDetectionProvider(alignments: [.horizontal])
        do {
            try await session.run([planes])
        } catch {
            return
        }

        var surfaces: [UUID: DetectedHorizontalSurface] = [:]
        for await update in planes.anchorUpdates {
            switch update.event {
            case .added, .updated:
                surfaces[update.anchor.id] = Self.surface(from: update.anchor)
            case .removed:
                surfaces[update.anchor.id] = nil
            }

            if let best = TabletopSurfaceSelection.bestSurface(from: Array(surfaces.values), viewer: Self.viewerPosition) {
                placement.position = SIMD3<Float>(Float(best.center.x), Float(best.center.y), Float(best.center.z))
            }
        }
    }

    /// Reduces an ARKit plane anchor to the Foundation-only facts `TabletopSurfaceSelection` needs: its
    /// world-space centre, its footprint, whether ARKit classified it as a table, and whether it faces up.
    /// The plane lies in the anchor's local X-Z plane, so its normal is the anchor's local +Y; rotating that
    /// into world space and checking the Y sign tells an up-facing table/floor from a down-facing ceiling —
    /// which is what keeps the diorama off the ceiling even if ARKit's classification is imperfect.
    private static func surface(from anchor: PlaneAnchor) -> DetectedHorizontalSurface {
        let world = anchor.originFromAnchorTransform
        let extentCenter = anchor.geometry.extent.anchorFromExtentTransform.columns.3
        let worldCenter = world * SIMD4<Float>(extentCenter.x, extentCenter.y, extentCenter.z, 1)
        let worldNormal = world * SIMD4<Float>(0, 1, 0, 0)
        return DetectedHorizontalSurface(
            center: Vector3Meters(x: Double(worldCenter.x), y: Double(worldCenter.y), z: Double(worldCenter.z)),
            width: Double(anchor.geometry.extent.width),
            depth: Double(anchor.geometry.extent.height),
            isTable: anchor.classification == .table,
            facesUp: worldNormal.y > 0
        )
    }

    // MARK: - Gestures

    /// Tap a piece to select it (selecting a different piece switches the selection).
    private var selectTap: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                appModel.selectStageObject(id: TabletopStageScene.objectId(of: value.entity))
            }
    }

    /// Drag a piece across the tabletop. Movement is constrained to the ground plane (the piece's height
    /// stays fixed). As a truss nears another truss's connector node it snaps onto it live — a glowing
    /// marker shows the node it locked onto — instead of only snapping on release. On release the final
    /// position is snapped + persisted by `AppModel` (same `trussNodeSnap` rule, so the commit matches the
    /// preview).
    private var moveDrag: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .updating($dragGrabOffset) { value, state, _ in
                guard let container = TabletopStageScene.objectContainer(of: value.entity),
                      let id = TabletopStageScene.objectId(of: value.entity),
                      let parent = container.parent else { return }
                let grab = value.convert(value.location3D, from: .local, to: parent)
                let offset = state ?? (container.position - grab)
                state = offset
                let target = grab + offset
                let free = SIMD3<Float>(target.x, container.position.y, target.z)
                let resolved = TabletopStageScene.resolveDrag(in: appModel.stageLayout, objectId: id, toScene: free)
                container.position = resolved.position
                TabletopStageScene.updateSnapIndicator(in: turntable, at: resolved.snapNode)
            }
            .onEnded { value in
                TabletopStageScene.updateSnapIndicator(in: turntable, at: nil)
                guard let container = TabletopStageScene.objectContainer(of: value.entity),
                      let id = TabletopStageScene.objectId(of: value.entity) else { return }
                let meters = TabletopStageScene.sceneToMeters(container.position)
                appModel.moveStageObject(id: id, toX: meters.x, z: meters.z)
            }
    }

    // MARK: - Controls (floating attachment)

    private var controlBar: some View {
        HStack(spacing: 14) {
            Picker("舞台尺寸", selection: stageSizeBinding) {
                Text("小").tag(StagePlatformPreset.small4x2)
                Text("中").tag(StagePlatformPreset.medium6x3)
                Text("大").tag(StagePlatformPreset.large8x4)
            }
            .pickerStyle(.segmented)
            .frame(width: 210)

            Picker("桁架", selection: portalBinding) {
                Text("4×3").tag(StagePortalPreset.portal4x3)
                Text("6×5").tag(StagePortalPreset.portal6x5)
                Text("8×4").tag(StagePortalPreset.portal8x4)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            Divider().frame(height: 26)

            Menu {
                Button("1 公尺桁架", systemImage: "plus") { appModel.addStageObject(assetId: .truss1m) }
                Button("2 公尺桁架", systemImage: "plus") { appModel.addStageObject(assetId: .truss2m) }
            } label: {
                Label("新增桁架", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .help("加入一段桁架，拖到既有節點附近會自動對齊接上")

            // Turntable: spin the WHOLE model so the user can look at any side (distinct from "旋轉所選",
            // which rotates only the selected piece). 45° steps → 8 covers a full turn.
            Button("舞台左轉", systemImage: "arrow.counterclockwise.circle") {
                rotateStage(by: -45)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            Button("舞台右轉", systemImage: "arrow.clockwise.circle") {
                rotateStage(by: 45)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            Divider().frame(height: 26)

            Button("旋轉所選", systemImage: "rotate.right.fill") {
                appModel.rotateSelectedStageObject()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(appModel.selectedStageObjectId == nil)

            Button("刪除所選", systemImage: "trash") {
                appModel.removeSelectedStageObject()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(appModel.selectedStageObjectId == nil)

            Button("重置舞台", systemImage: "arrow.counterclockwise") {
                appModel.resetStageLayoutToDefault()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)

            Button("完成", systemImage: "checkmark") {
                finishEditing()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
    }

    private var stageSizeBinding: Binding<StagePlatformPreset> {
        Binding(
            get: { TabletopStageEditing.currentStagePlatformPreset(of: appModel.stageLayout) ?? .medium6x3 },
            set: { appModel.setStagePlatformPreset($0) }
        )
    }

    private var portalBinding: Binding<StagePortalPreset> {
        Binding(
            get: { TabletopStageEditing.currentTrussPortalPreset(of: appModel.stageLayout) ?? .portal6x5 },
            set: { appModel.setTrussPortalPreset($0) }
        )
    }

    /// Spins the whole diorama by `degrees` about its vertical axis, animated. The yaw lives on the
    /// `turntable` entity (not `placement`), so the model turns while the ARKit table anchoring and the
    /// control bar stay put. `stageYaw` accumulates so repeated taps keep turning.
    private func rotateStage(by degrees: Double) {
        stageYaw += degrees
        let yaw = Float(stageYaw * .pi / 180)
        let target = Transform(rotation: simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)))
        turntable.move(to: target, relativeTo: turntable.parent, duration: 0.3)
    }

    /// Done: leave editing and return to the 1:1 stage space. Sets the desired scene back to the stage and
    /// dismisses this editor space; `ContentView` reopens the stage once the main window is back.
    private func finishEditing() {
        Task { @MainActor in
            appModel.exitTabletopEditing() // desiredImmersiveScene = .stage
            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }
        }
    }
}

/// Builds and maintains the tabletop stage geometry: one selectable container entity per
/// `StageObject` (`stageobj_<id>`), connector decoration, and a ground plate, all at a small "diorama"
/// scale. Foundation-shaped where it can be, but RealityKit-bound, so it lives in the view file rather
/// than the testable core. The pure preset/selection/snap logic it relies on is in `StageBuilderModels`.
enum TabletopStageScene {
    /// meters → tabletop scene units. Tuned so a large 8m stage fits the ~0.9m volume; retune freely
    /// from a device preview without affecting logic (move/select math derives from this constant).
    static let scale: Float = 0.07
    /// Drops the model so the deck rests low in the volume and the portal is comfortably framed.
    static let origin = SIMD3<Float>(0, -0.16, 0.03)

    static func scenePoint(_ meters: Vector3Meters) -> SIMD3<Float> {
        SIMD3<Float>(Float(meters.x), Float(meters.y), Float(meters.z)) * scale + origin
    }

    /// Inverse of `scenePoint`, for mapping a dragged container's position back to model meters.
    static func sceneToMeters(_ point: SIMD3<Float>) -> Vector3Meters {
        let v = (point - origin) / scale
        return Vector3Meters(x: Double(v.x), y: Double(v.y), z: Double(v.z))
    }

    /// A relative offset (no origin shift), for placing lattice members inside a movable container.
    static func sceneOffset(_ meters: Vector3Meters) -> SIMD3<Float> {
        SIMD3<Float>(Float(meters.x), Float(meters.y), Float(meters.z)) * scale
    }

    static func sceneLength(_ meters: Double) -> Float { Float(meters) * scale }

    static func objectEntityName(_ id: String) -> String { "stageobj_\(id)" }

    private static let snapIndicatorName = "tabletop_snap_node"

    // MARK: - Live drag snapping

    /// Resolves where a dragged piece should sit (scene units): node-snapped onto a nearby truss
    /// connector if one is within reach, else the free finger target. Returns the snap node (scene units)
    /// when a snap is active so the caller can show a marker. Mirrors `StageLayout.snappedObject`'s rule
    /// via the pure, smoke-tested `trussNodeSnap`, but for the in-flight drag. Height is preserved (the
    /// drag is ground-plane constrained), so only X/Z move.
    static func resolveDrag(in layout: StageLayout, objectId: String, toScene point: SIMD3<Float>) -> (position: SIMD3<Float>, snapNode: SIMD3<Float>?) {
        guard let object = layout.object(id: objectId) else {
            return (point, nil)
        }

        let meters = sceneToMeters(point)
        var candidate = object
        candidate.position = Vector3Meters(x: meters.x, y: object.position.y, z: meters.z)

        guard let snap = layout.trussNodeSnap(for: candidate) else {
            return (point, nil)
        }

        let snapped = scenePoint(snap.position)
        return (SIMD3<Float>(snapped.x, point.y, snapped.z), scenePoint(snap.node))
    }

    /// Shows/moves a glowing marker at the connector node a dragged truss is snapping to, or hides it when
    /// no snap is active. The marker is parented to the assembly (not `root`) so it shares the scene-unit
    /// coordinate space the snap-node position is expressed in — and stays correct when the assembly is
    /// seated on the table with a vertical offset. The assembly isn't rebuilt mid-drag (the layout signature
    /// only changes on release), so a child marker survives the drag.
    static func updateSnapIndicator(in root: Entity, at scenePosition: SIMD3<Float>?) {
        let host = root.children.first(where: { $0.name.hasPrefix("tabletop_layout_") }) ?? root

        guard let scenePosition else {
            host.findEntity(named: snapIndicatorName)?.isEnabled = false
            return
        }

        let indicator: Entity
        if let existing = host.findEntity(named: snapIndicatorName) {
            indicator = existing
        } else {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: sceneLength(0.12)),
                materials: [material(hex: "#3FB6FF")]
            )
            marker.name = snapIndicatorName
            host.addChild(marker)
            indicator = marker
        }
        indicator.position = scenePosition
        indicator.isEnabled = true
    }

    /// Walks up from a hit entity to its owning `stageobj_<id>` container.
    static func objectContainer(of entity: Entity) -> Entity? {
        var node: Entity? = entity
        while let current = node {
            if current.name.hasPrefix("stageobj_") {
                return current
            }
            node = current.parent
        }
        return nil
    }

    static func objectId(of entity: Entity) -> String? {
        guard let container = objectContainer(of: entity) else { return nil }
        return String(container.name.dropFirst("stageobj_".count))
    }

    // MARK: - Build / sync

    /// Rebuilds the geometry only when the layout signature changes, then refreshes the selection
    /// marker. Cheap to call every `update:` pass.
    static func sync(_ root: Entity, layout: StageLayout, selectedId: String?) {
        let signature = ImmersiveStageGeometryPlan.make(from: layout).layoutSignature
        let wantName = "tabletop_layout_\(abs(signature.hashValue))"

        if !root.children.contains(where: { $0.name == wantName }) {
            for child in root.children where child.name.hasPrefix("tabletop_layout_") {
                child.removeFromParent()
            }
            root.addChild(makeAssembly(named: wantName, layout: layout))
        }

        applySelection(in: root, selectedId: selectedId)
    }

    /// Seats the assembly so its visual bottom rests exactly on the placement container's origin — i.e. on
    /// the detected real table (or the floating fallback pose). The diorama geometry is authored around a
    /// fixed `origin` offset, so its lowest point is below 0; this lifts it to sit on the surface. Cheap to
    /// re-run every `update:` pass (idempotent: it resets the y before measuring).
    static func seatAssemblyOnSurface(in root: Entity) {
        guard let assembly = root.children.first(where: { $0.name.hasPrefix("tabletop_layout_") }) else {
            return
        }
        assembly.position.y = 0
        let bottom = assembly.visualBounds(relativeTo: root).min.y
        assembly.position.y = -bottom
    }

    private static func applySelection(in root: Entity, selectedId: String?) {
        guard let assembly = root.children.first(where: { $0.name.hasPrefix("tabletop_layout_") }) else {
            return
        }
        let selectedName = selectedId.map(objectEntityName)
        for container in assembly.children where container.name.hasPrefix("stageobj_") {
            container.findEntity(named: "selection_highlight")?.isEnabled = (container.name == selectedName)
        }
    }

    private static func makeAssembly(named name: String, layout: StageLayout) -> Entity {
        let assembly = Entity()
        assembly.name = name

        assembly.addChild(groundPlate(for: layout))

        for object in layout.objects {
            switch object.type {
            case .stageBase:
                assembly.addChild(stageBaseEntity(object))
            case .trussSegment:
                assembly.addChild(trussSegmentEntity(object))
            case .stageDeck:
                break // decks are embedded in the stage base; not shown separately
            }
        }

        for block in layout.trussConnectorBlocks {
            assembly.addChild(connectorEntity(block))
        }

        return assembly
    }

    // MARK: - Per-object geometry

    private static func stageBaseEntity(_ object: StageObject) -> Entity {
        let container = Entity()
        container.name = objectEntityName(object.id)
        container.position = scenePoint(object.position)
        container.orientation = yRotation(object.rotation)

        guard let size = object.size else {
            return container
        }

        let width = sceneLength(size.width)
        let height = sceneLength(size.height)
        let depth = sceneLength(size.depth)

        let body = ModelEntity(
            mesh: .generateBox(width: width, height: height, depth: depth, cornerRadius: sceneLength(0.02)),
            materials: [material(hex: "#26282B")]
        )
        addInteraction(body)
        container.addChild(body)

        let top = ModelEntity(
            mesh: .generateBox(width: width * 0.98, height: sceneLength(0.05), depth: depth * 0.98),
            materials: [material(hex: "#C30010")]
        )
        top.position = SIMD3<Float>(0, height / 2, 0)
        addInteraction(top)
        container.addChild(top)

        addSelectionMarker(to: container)
        return container
    }

    private static func trussSegmentEntity(_ object: StageObject) -> Entity {
        let container = Entity()
        container.name = objectEntityName(object.id)
        container.position = scenePoint(object.position)
        // The lattice members are already rotated into world meters, so place them relative to the
        // object's position (no extra container rotation) and let the container carry the position.

        for member in object.trussLattice.allMembers {
            let start = sceneOffset(member.start - object.position)
            let end = sceneOffset(member.end - object.position)
            if let rod = rod(fromLocal: start, toLocal: end, radius: sceneLength(0.035), hex: "#D6D8D5") {
                addInteraction(rod)
                container.addChild(rod)
            }
        }

        addSelectionMarker(to: container)
        return container
    }

    private static func connectorEntity(_ block: TrussConnectorBlock) -> Entity {
        let size = sceneLength(block.size)
        let entity = ModelEntity(
            mesh: .generateBox(width: size, height: size, depth: size),
            materials: [material(hex: "#C9CBC8", metallic: true)]
        )
        entity.name = "tabletop_connector_\(block.id)"
        entity.position = scenePoint(block.position)
        return entity // decoration only — not selectable/movable
    }

    /// A faint plate beneath the stage so the model reads as resting on the table.
    private static func groundPlate(for layout: StageLayout) -> Entity {
        let baseSize = layout.objects.first(where: { $0.type == .stageBase })?.size
        let width = (baseSize?.width ?? 6) + 1.5
        let depth = (baseSize?.depth ?? 3) + 2.5
        let plate = ModelEntity(
            mesh: .generateBox(width: sceneLength(width), height: sceneLength(0.05), depth: sceneLength(depth), cornerRadius: sceneLength(0.05)),
            materials: [material(hex: "#0C0D10")]
        )
        plate.name = "tabletop_ground"
        plate.position = scenePoint(Vector3Meters(x: 0, y: -0.03, z: -0.5))
        return plate
    }

    // MARK: - Helpers

    /// Gives a mesh precise per-mesh collision + makes it a drag/tap target.
    private static func addInteraction(_ entity: ModelEntity) {
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(InputTargetComponent())
    }

    /// A glowing footprint plate placed just under the object; toggled on while it is selected.
    private static func addSelectionMarker(to container: Entity) {
        let bounds = container.visualBounds(relativeTo: container)
        guard bounds.extents.x > 0, bounds.extents.z > 0 else {
            return
        }
        let marker = ModelEntity(
            mesh: .generateBox(width: bounds.extents.x * 1.08, height: sceneLength(0.04), depth: bounds.extents.z * 1.08),
            materials: [material(hex: "#3FB6FF")]
        )
        marker.name = "selection_highlight"
        marker.position = SIMD3<Float>(bounds.center.x, bounds.min.y - sceneLength(0.04), bounds.center.z)
        marker.isEnabled = false
        container.addChild(marker)
    }

    private static func rod(fromLocal start: SIMD3<Float>, toLocal end: SIMD3<Float>, radius: Float, hex: String) -> ModelEntity? {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.0001 else {
            return nil
        }
        let entity = ModelEntity(
            mesh: .generateCylinder(height: length, radius: radius),
            materials: [material(hex: hex, metallic: true)]
        )
        entity.position = (start + end) / 2
        entity.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: direction / length)
        return entity
    }

    private static func yRotation(_ rotation: Vector3Degrees) -> simd_quatf {
        simd_quatf(angle: Float(rotation.y) * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
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

    private static func material(hex: String, metallic: Bool = false) -> SimpleMaterial {
        let rgb = RGBComponents(hex: hex) ?? .white
        return SimpleMaterial(
            color: UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1),
            isMetallic: metallic
        )
    }
}

#Preview(immersionStyle: .mixed) {
    TabletopStageEditorView()
        .environment(AppModel())
}
#endif
