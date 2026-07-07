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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // RealityView `update:` closure below. Without them the model would never reflect edits. The
        // `lightingLook` + `selectedFixtureId` reads are what let the fixture (light) proxies rebuild when
        // a fixture is added/removed/moved and re-highlight on selection — same Observation footgun.
        let _ = appModel.stageLayout
        let _ = appModel.selectedStageObjectId
        let _ = appModel.lightingLook
        let _ = appModel.selectedFixtureId

        RealityView { content, attachments in
            placement.name = "tabletop_placement"
            placement.position = Self.floatingPlacement
            turntable.name = "tabletop_turntable"
            placement.addChild(turntable)
            content.add(placement)
            TabletopStageScene.sync(turntable, layout: appModel.stageLayout, selectedId: appModel.selectedStageObjectId)
            TabletopStageScene.syncFixtures(turntable, look: appModel.lightingLook, layout: appModel.stageLayout, selectedFixtureId: appModel.selectedFixtureId)
            TabletopStageScene.seatAssemblyOnSurface(in: turntable)

            if let controls = attachments.entity(for: "controls") {
                // Float the control bar just above and in front of the model. It hangs off `placement`, not
                // the turntable, so it stays facing the user while the model spins.
                controls.position = SIMD3<Float>(0, 0.34, 0.18)
                placement.addChild(controls)
            }
        } update: { _, _ in
            TabletopStageScene.sync(turntable, layout: appModel.stageLayout, selectedId: appModel.selectedStageObjectId)
            TabletopStageScene.syncFixtures(turntable, look: appModel.lightingLook, layout: appModel.stageLayout, selectedFixtureId: appModel.selectedFixtureId)
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

    /// Tap a piece to select it (selecting a different piece switches the selection). Routes by entity
    /// prefix: a tapped light proxy (`tabletopfixture_<id>`) selects a rig fixture; anything else falls
    /// back to the existing `stageobj_` (truss/deck) selection. Selecting one clears the other so only a
    /// single thing is ever highlighted.
    private var selectTap: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let fixtureId = TabletopStageScene.fixtureId(of: value.entity) {
                    appModel.selectStageObject(id: nil)
                    appModel.selectFixture(id: fixtureId)
                } else {
                    appModel.selectFixture(id: nil)
                    appModel.selectStageObject(id: TabletopStageScene.objectId(of: value.entity))
                }
            }
    }

    /// Drag a piece across the tabletop, constrained to the ground plane in XZ. A truss/deck piece keeps its
    /// height and snaps onto a nearby connector node live (a glowing marker shows the node) — the commit
    /// matches the preview via the same `trussNodeSnap` rule. A light proxy instead has its Y decided by the
    /// dragged XZ (#19 Option A): inside the truss footprint it auto-snaps up to hanging height (and hangs),
    /// outside it drops to floor-stand height — the shared `RigPlacement.resolvedDragPosition` rule, so the
    /// live preview matches what `AppModel.moveFixture` persists on release.
    private var moveDrag: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .updating($dragGrabOffset) { value, state, _ in
                // A light proxy: free XZ drag (no truss node-snap); the dragged XZ decides Y (#19 Option A).
                if let fixtureContainer = TabletopStageScene.fixtureContainer(of: value.entity),
                   let parent = fixtureContainer.parent {
                    let grab = value.convert(value.location3D, from: .local, to: parent)
                    let offset = state ?? (fixtureContainer.position - grab)
                    state = offset
                    let target = grab + offset
                    // #19: inside the truss footprint the light auto-snaps up to hanging height (and hangs);
                    // outside it drops to floor-stand height. Same pure rule the on-release commit uses, so
                    // the live preview (position + #15 hang↔stand toggle) matches what gets persisted.
                    let draggedXZ = TabletopStageScene.sceneToMeters(target)
                    let resolved = RigPlacement.resolvedDragPosition(x: draggedXZ.x, z: draggedXZ.z,
                                                                     layout: appModel.stageLayout)
                    fixtureContainer.position = TabletopStageScene.scenePoint(resolved)
                    TabletopStageScene.syncFixtureStand(in: fixtureContainer,
                                                        position: resolved,
                                                        layout: appModel.stageLayout)
                    return
                }
                // Otherwise a truss/deck piece: ground-plane drag with live connector-node snapping.
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
                // Light proxy: commit the footprint-aware Y (hang vs floor) from the final XZ, in every cue.
                // Recompute via the shared `resolvedDragPosition` so the persisted Y matches the live preview.
                // Lasers are unaffected — `AppModel.moveFixture` re-clamps them onto the truss (stay hanging).
                if let fixtureContainer = TabletopStageScene.fixtureContainer(of: value.entity),
                   let fixtureId = TabletopStageScene.fixtureId(of: value.entity) {
                    let meters = TabletopStageScene.sceneToMeters(fixtureContainer.position)
                    let resolved = RigPlacement.resolvedDragPosition(x: meters.x, z: meters.z,
                                                                     layout: appModel.stageLayout)
                    appModel.moveFixture(id: fixtureId, toX: resolved.x, y: resolved.y, z: resolved.z)
                    return
                }
                guard let container = TabletopStageScene.objectContainer(of: value.entity),
                      let id = TabletopStageScene.objectId(of: value.entity) else { return }
                let meters = TabletopStageScene.sceneToMeters(container.position)
                appModel.moveStageObject(id: id, toX: meters.x, z: meters.z)
            }
    }

    // MARK: - Controls (floating attachment)

    private var controlBar: some View {
        HStack(spacing: 14) {
            // Keep a visible readout of the current selection; the 3D highlight alone is easy to miss.
            selectionStatus

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
            .lumaGazeTarget()
            .help("加入一段桁架，拖到既有節點附近會自動對齊接上")

            Menu {
                ForEach(Self.addableFixtureModels, id: \.self) { model in
                    if model == .laser {
                        Button {
                            appModel.addFixtureToRig(model: model, zone: .stageBack)
                        } label: {
                            Label("\(Self.fixtureModelName(model)) (固定於上舞台桁架)", systemImage: "lightbulb")
                        }
                    } else {
                        Menu {
                            ForEach(StageZone.allCases, id: \.self) { zone in
                                Button {
                                    appModel.addFixtureToRig(model: model, zone: zone)
                                } label: {
                                    Text(Self.zoneName(zone))
                                }
                            }
                        } label: {
                            Label(Self.fixtureModelName(model), systemImage: "lightbulb")
                        }
                    }
                }
            } label: {
                Label("新增燈具", systemImage: "lightbulb.fill")
            }
            .buttonStyle(.bordered)
            .lumaGazeTarget()
            .disabled(rigIsFull)
            .help(rigIsFull ? "燈具數量已達上限" : "加入一盞燈具到舞台前緣，可拖移到任意位置")

            Button("刪除所選燈具", systemImage: "lightbulb.slash") {
                appModel.removeSelectedFixture()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(appModel.selectedFixtureId == nil)
            .help("刪除選取的燈具")

            Button("複製所選燈具", systemImage: "plus.square.on.square") {
                appModel.duplicateSelectedFixture()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(appModel.selectedFixtureId == nil || rigIsFull)
            .help(rigIsFull ? "燈具數量已達上限" : "複製選取的燈具")

            Button("鏡射所選燈具", systemImage: "flip.horizontal") {
                appModel.mirrorSelectedFixture()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(appModel.selectedFixtureId == nil || rigIsFull)
            .help(rigIsFull ? "燈具數量已達上限" : "以舞台中線為軸，鏡像複製選取的燈具")

            // #23: one-tap re-aim the selected light back at the stage centre. After a manual move the aim
            // stays zone-derived (often pointing the wrong way), so this solves the `aimOffset` that re-aims
            // the beam + head at centre stage and writes it (rig identity, all cues).
            Button("瞄準舞台中心", systemImage: "scope") {
                aimSelectedFixtureAtStageCenter()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(appModel.selectedFixtureId == nil)
            .help("將選取燈具的光束方向對回舞台中心")

            // #17: precise direction-nudge keys for the selected light — each press shifts it a fixed
            // 0.25 m along ±X/±Z via the shared `moveFixture`, so exact placement doesn't rely on dragging
            // the tiny diorama. Only shown when a fixture is selected.
            if appModel.selectedFixtureId != nil {
                Divider().frame(height: 26)
                HStack(spacing: 6) {
                    nudgeButton("−X", axis: .x, sign: -1, help: "所選燈具往 −X 方向移動 0.25 公尺")
                    nudgeButton("+X", axis: .x, sign: 1, help: "所選燈具往 +X 方向移動 0.25 公尺")
                    nudgeButton("−Z", axis: .z, sign: -1, help: "所選燈具往 −Z 方向移動 0.25 公尺")
                    nudgeButton("+Z", axis: .z, sign: 1, help: "所選燈具往 +Z 方向移動 0.25 公尺")
                }
            }

            // Turntable: spin the WHOLE model so the user can look at any side (distinct from "旋轉所選",
            // which rotates only the selected piece). 45° steps → 8 covers a full turn.
            Button("舞台左轉", systemImage: "arrow.counterclockwise.circle") {
                rotateStage(by: -45)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .help("將整個舞台模型向左轉 45°，方便檢視其他角度")

            Button("舞台右轉", systemImage: "arrow.clockwise.circle") {
                rotateStage(by: 45)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .help("將整個舞台模型向右轉 45°，方便檢視其他角度")

            Divider().frame(height: 26)

            Button("旋轉所選", systemImage: "rotate.right.fill") {
                appModel.rotateSelectedStageObject()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(appModel.selectedStageObjectId == nil)
            .help("將選取的物件旋轉 90°")

            Button("刪除所選", systemImage: "trash") {
                appModel.removeSelectedStageObject()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(appModel.selectedStageObjectId == nil)
            .help("刪除選取的物件")

            Button("撤銷上一個編輯", systemImage: "arrow.uturn.backward") {
                appModel.undoStageEdit()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(!appModel.canUndoStageEdit)
            .help("撤銷上一個舞台或燈具編輯")

            Button("重置舞台", systemImage: "arrow.counterclockwise") {
                appModel.resetStageLayoutToDefault()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .help("還原成預設的舞台佈局與燈具")

            Button("完成", systemImage: "checkmark") {
                finishEditing()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .help("儲存佈局並返回 1:1 沉浸式舞台")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassBackgroundEffect()
    }

    /// A compact, always-visible status pill telling the user which piece is selected.
    private var selectionStatus: some View {
        // 燈具與物件選取互斥：優先顯示選取的燈具（"N · 型號"），否則回退物件（桁架／台座），皆無 → 未選取。
        let statusText: String
        if let fixture = selectedFixtureLabel {
            statusText = "已選取：\(fixture)"
        } else if let object = selectedObjectTypeName {
            statusText = "已選取：\(object)"
        } else {
            statusText = "未選取"
        }
        let hasSelection = selectedFixtureLabel != nil || selectedObjectTypeName != nil
        return HStack(spacing: 6) {
            Image(systemName: hasSelection ? "checkmark.circle.fill" : "hand.tap")
                .font(.callout)
                .foregroundStyle(hasSelection ? LumaStageDesign.coolBlue : LumaStageDesign.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)
                    .lineLimit(1)
                // #17: numeric feedback — the selected fixture's resolved model-metre X/Z, so the user
                // knows where the light actually sits (drag has no readout on the tiny diorama).
                if let position = selectedFixtureResolvedPosition {
                    Text(TabletopNudge.readout(x: position.x, z: position.z))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// The selected rig fixture's addressable "N · 型號" label (from the current cue, else the first), or
    /// nil when no fixture is selected. The number is the fixture's 1-based index in cue order — the SAME
    /// "Light N" the 1:1 stage, the floating proxy caption, and voice commands use — so all agree.
    private var selectedFixtureLabel: String? {
        guard let id = appModel.selectedFixtureId else { return nil }
        let look = appModel.lightingLook
        let fixtures = (look.cues.first(where: { $0.id == look.selectedCueId }) ?? look.cues.first)?.fixtureGroups ?? []
        guard let index = fixtures.firstIndex(where: { $0.id == id }) else { return nil }
        let modelName = LightingFixtureCatalog.item(for: fixtures[index].renderModel)?.displayName ?? fixtures[index].renderModel.rawValue
        return StageLightLabel.tabletopLabel(number: index + 1, modelName: modelName)
    }

    /// The selected fixture's RESOLVED model-metre position — the SAME `RigPlacement.resolvedPlacement`
    /// the renderer (`ImmersiveView.syncRig`) and `TabletopStageScene.syncFixtures` seat it at, so the
    /// readout and the nudge buttons operate on exactly where the light sits (its `manualPosition` if it
    /// was dragged, else the zone-derived slot). The per-zone slot/count counting mirrors `syncFixtures`.
    private var selectedFixtureResolvedPosition: Vector3Meters? {
        selectedFixtureResolvedPlacement?.position
    }

    /// The selected fixture's full RESOLVED placement — position AND zone-derived aim point — via the same
    /// `RigPlacement.resolvedPlacement` the renderer uses. The aim point feeds the "瞄準舞台中心" button:
    /// its zone-derived direction is the `base` the aim-offset solver rotates onto the stage centre.
    private var selectedFixtureResolvedPlacement: (position: Vector3Meters, aim: Vector3Meters)? {
        guard let id = appModel.selectedFixtureId else { return nil }
        let look = appModel.lightingLook
        let fixtures = (look.cues.first(where: { $0.id == look.selectedCueId }) ?? look.cues.first)?.fixtureGroups ?? []
        guard let index = fixtures.firstIndex(where: { $0.id == id }) else { return nil }
        let fixture = fixtures[index]
        var zoneTotals: [StageZone: Int] = [:]
        for f in fixtures { zoneTotals[f.zone, default: 0] += 1 }
        var slot = 0
        for f in fixtures.prefix(index) where f.zone == fixture.zone { slot += 1 }
        return RigPlacement.resolvedPlacement(
            fixture: fixture,
            slot: slot,
            count: zoneTotals[fixture.zone] ?? 1,
            layout: appModel.stageLayout
        )
    }

    /// One-tap re-aim (#23): solve the `aimOffset` that points the selected fixture at the stage centre and
    /// write it via `AppModel.setFixtureAim` (rig identity → validated + persisted; the live 1:1 stage
    /// reflects it because `aimOffset` is in `syncRig`'s rebuild signature). The offset comes from the
    /// Foundation-only `FixtureAimMath.offset` — the mathematical inverse of the renderer's resting-aim
    /// rotation — using the fixture's zone-derived direction as the base and the stage centre as the target.
    private func aimSelectedFixtureAtStageCenter() {
        guard let id = appModel.selectedFixtureId,
              let placement = selectedFixtureResolvedPlacement else { return }
        let center = RigPlacement.stageCenterTarget(layout: appModel.stageLayout)
        func vec(_ m: Vector3Meters) -> SIMD3<Float> { SIMD3<Float>(Float(m.x), Float(m.y), Float(m.z)) }
        let base = vec(placement.aim) - vec(placement.position)
        let desired = vec(center) - vec(placement.position)
        let (pan, tilt) = FixtureAimMath.offset(base: base, desired: desired)
        appModel.setFixtureAim(id: id, panDegrees: pan, tiltDegrees: tilt)
    }

    /// Moves the selected fixture one fixed step along X or Z via the shared `AppModel.moveFixture`
    /// (rig identity → validated + persisted; lasers re-clamped to the truss). Starts from the fixture's
    /// current RESOLVED position, so the first press nudges from where it visually sits (#17).
    private func nudgeSelectedFixture(axis: TabletopNudge.Axis, sign: Double) {
        guard let id = appModel.selectedFixtureId, let position = selectedFixtureResolvedPosition else { return }
        let moved = TabletopNudge.nudged(x: position.x, z: position.z, axis: axis, sign: sign)
        appModel.moveFixture(id: id, toX: moved.x, y: position.y, z: moved.z)
    }

    /// One compact ±X/±Z nudge key for the control bar (#17).
    private func nudgeButton(_ title: String, axis: TabletopNudge.Axis, sign: Double, help: String) -> some View {
        Button(title) {
            nudgeSelectedFixture(axis: axis, sign: sign)
        }
        .buttonStyle(.bordered)
        .lumaGazeTarget()
        .help(help)
    }

    /// The selected `StageObject`'s type rendered in Traditional Chinese, or `nil` when nothing is
    /// selected. `StageObject.displayName` is an English data value, so the type name is mapped here for
    /// the user-facing status rather than surfaced raw.
    private var selectedObjectTypeName: String? {
        guard let object = appModel.stageLayout.object(id: appModel.selectedStageObjectId) else {
            return nil
        }
        switch object.type {
        case .stageBase:
            return "舞台台座"
        case .stageDeck:
            return "舞台平台"
        case .trussSegment:
            return "桁架段"
        }
    }

    /// True when the rig is already at `AppModel.maxRigFixtureCount`, so the add-light control is disabled.
    private var rigIsFull: Bool {
        (appModel.lightingLook.cues.map(\.fixtureGroups.count).max() ?? 0) >= AppModel.maxRigFixtureCount
    }

    /// A small menu of fixture models the user can drop onto the tabletop rig. A representative spread of
    /// the real-world product fixtures (not the abstract role-teaching ones).
    private static let addableFixtureModels: [LightingFixtureVisualModel] = [
        .movingHeadBeam, .ledPar, .ledStrobeBar, .ledFresnel, .laser
    ]

    /// The Traditional-Chinese display name for a fixture model, from the catalog (falls back to the raw
    /// identifier if a model isn't catalogued).
    private static func fixtureModelName(_ model: LightingFixtureVisualModel) -> String {
        LightingFixtureCatalog.item(for: model)?.displayName ?? model.rawValue
    }

    /// The Traditional-Chinese display name for a StageZone.
    private static func zoneName(_ zone: StageZone) -> String {
        switch zone {
        case .stageFront: return "台前"
        case .stageBack: return "台後"
        case .stageLeft: return "台左"
        case .stageRight: return "台右"
        case .fullStage: return "全場"
        }
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
        // Reduce Motion: snap to the new yaw instead of spinning the whole diorama — a moving 3D scene is
        // exactly the vestibular trigger Reduce Motion targets, so gate this RealityKit animation the same
        // way the sweep gates SwiftUI motion.
        if reduceMotion {
            turntable.transform = target
        } else {
            turntable.move(to: target, relativeTo: turntable.parent, duration: 0.3)
        }
    }

    /// Done: leave editing and return to the 1:1 stage space. Sets the desired scene back to the stage and
    /// dismisses this editor space; `ContentView` reopens the stage once the main window is back.
    private func finishEditing() {
        Task { @MainActor in
            appModel.exitTabletopEditing() // desiredImmersiveScene = .stage
            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
                // Second line of defence: `onDisappear` reopens the main window, but a window request
                // issued during a space transition is intermittently dropped by the system (same class
                // as the documented dropped `dismissWindow`), and the reconciler that reopens the 1:1
                // stage lives in that window. Re-issuing the open here is idempotent.
                openWindow(id: AppModel.mainWindowID)
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

    static func fixtureEntityName(_ id: String) -> String { "tabletopfixture_\(id)" }

    /// Walks up from a hit entity to its owning `tabletopfixture_<id>` container (light proxy).
    static func fixtureContainer(of entity: Entity) -> Entity? {
        var node: Entity? = entity
        while let current = node {
            if current.name.hasPrefix("tabletopfixture_") {
                return current
            }
            node = current.parent
        }
        return nil
    }

    static func fixtureId(of entity: Entity) -> String? {
        guard let container = fixtureContainer(of: entity) else { return nil }
        return String(container.name.dropFirst("tabletopfixture_".count))
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

    /// Builds/refreshes the selectable, draggable light proxies for the look's rig fixtures, parented under
    /// the SAME assembly the `stageobj_` containers live in (so `scenePoint`/`sceneToMeters` and the seat
    /// offset apply identically). Reconciles by fixture id: removes proxies whose fixture is gone, adds new
    /// ones, and repositions surviving ones to their resolved placement (so add/remove/move all reflect).
    /// Cheap to call every `update:` pass.
    static func syncFixtures(_ root: Entity, look: LightingLook, layout: StageLayout, selectedFixtureId: String?) {
        guard let assembly = root.children.first(where: { $0.name.hasPrefix("tabletop_layout_") }) else {
            return
        }

        // Fixtures carry rig identity (same set/positions across cues), so any cue gives the same answer;
        // use the selected cue, else the first.
        let fixtures = (look.cues.first(where: { $0.id == look.selectedCueId }) ?? look.cues.first)?.fixtureGroups ?? []

        // Per-zone slot/count, mirroring `ImmersiveView.syncRig`: a fixture's slot is its index among the
        // fixtures sharing its zone; count is how many share it.
        var zoneTotals: [StageZone: Int] = [:]
        for fixture in fixtures {
            zoneTotals[fixture.zone, default: 0] += 1
        }

        let wantIds = Set(fixtures.map(\.id))
        for child in assembly.children where child.name.hasPrefix("tabletopfixture_") {
            let id = String(child.name.dropFirst("tabletopfixture_".count))
            if !wantIds.contains(id) {
                child.removeFromParent()
            }
        }

        var zoneSlots: [StageZone: Int] = [:]
        for (index, fixture) in fixtures.enumerated() {
            let slot = zoneSlots[fixture.zone, default: 0]
            zoneSlots[fixture.zone] = slot + 1
            let placement = RigPlacement.resolvedPlacement(
                fixture: fixture,
                slot: slot,
                count: zoneTotals[fixture.zone] ?? 1,
                layout: layout
            )
            let scenePos = scenePoint(placement.position)

            let name = fixtureEntityName(fixture.id)
            let container: Entity
            if let existing = assembly.findEntity(named: name) {
                container = existing
            } else {
                // Aim the mini model exactly like `ImmersiveView.addRigFixture`: the zone-derived direction
                // rotated by the fixture's authored `aimOffset` (SPEC 13). Built once with the proxy — the
                // model is only rebuilt when the fixture id is new (regeneration), matching the old cone.
                let baseDir = scenePoint(placement.aim) - scenePoint(placement.position)
                let baseUnit = simd_length(baseDir) > 0.0001 ? simd_normalize(baseDir) : SIMD3<Float>(0, 0, -1)
                let offset = fixture.aimOffset ?? .zero
                let aimDir = LightEffectSystem.aim(base: baseUnit,
                                                   panDegrees: offset.panDegrees,
                                                   tiltDegrees: offset.tiltDegrees)
                container = makeFixtureProxy(named: name,
                                             model: fixture.renderModel,
                                             hex: fixture.color.value,
                                             aim: aimDir)
                assembly.addChild(container)
            }
            container.position = scenePos
            container.findEntity(named: "fixture_selection_highlight")?.isEnabled = (fixture.id == selectedFixtureId)

            // #14: recolour the emissive lens to the CURRENT cue's colour on every pass — the proxy is
            // built once, but the cue colour changes when the user switches cue or recolours the fixture.
            (container.findEntity(named: "fixture_lens") as? ModelEntity)?.model?.materials = [lensMaterial(hex: fixture.color.value)]

            // #13: a floating "N · 型號" caption. The number is this fixture's 1-based index in cue order —
            // the SAME "Light N" the 1:1 stage and voice commands use — and the model name is the catalog name.
            let modelName = LightingFixtureCatalog.item(for: fixture.renderModel)?.displayName ?? fixture.renderModel.rawValue
            syncFixtureLabel(in: container, text: StageLightLabel.tabletopLabel(number: index + 1, modelName: modelName))

            // Same support policy as the 1:1 stage: a fixture under the truss footprint (and high enough)
            // hangs; anything else grows a floor stand up to it — so no light floats on the diorama either.
            // The stand is a child of the container, so it follows XZ drags and stays under the light.
            syncFixtureStand(in: container, position: placement.position, layout: layout)
        }
    }

    /// Builds/refreshes a fixture proxy's floating "N · 型號" caption (#13). The caption faces the viewer
    /// via `BillboardComponent` (so the turntable spin doesn't turn it away), and — to avoid rebuilding 12
    /// text meshes every `update:` pass — the wanted string is encoded into the caption child's name
    /// (`fixture_caption_<want>`): if that child already exists the string is current and we bail; otherwise
    /// stale captions are removed and the new one is built. The caption carries no `InputTargetComponent`/
    /// collision, so it never intercepts a tap/drag meant for the fixture body.
    static func syncFixtureLabel(in container: Entity, text want: String) {
        let labelHostName = "fixture_label"
        let host: Entity
        if let existing = container.findEntity(named: labelHostName) {
            host = existing
        } else {
            let e = Entity()
            e.name = labelHostName
            // Above the (downward) cone body, in the un-scaled assembly space (font is a scene-unit size,
            // not the 0.12 of the 1:1 stage — tune on device, see Caveats).
            e.position = SIMD3<Float>(0, sceneLength(0.4), 0)
            e.components.set(BillboardComponent())
            container.addChild(e)
            host = e
        }

        let captionName = "fixture_caption_\(want)"
        if host.findEntity(named: captionName) != nil {
            return // the current caption already shows the wanted string — no rebuild
        }
        for child in host.children where child.name.hasPrefix("fixture_caption_") {
            child.removeFromParent()
        }
        host.addChild(makeFixtureCaption(named: captionName, text: want))
    }

    /// One caption entity: unlit white `generateText` glyphs on a dark backing plate, recentred on the
    /// glyph bounds (mirrors `ImmersiveView.makeLabelEntity`, scaled down for the diorama).
    private static func makeFixtureCaption(named name: String, text: String) -> Entity {
        let caption = Entity()
        caption.name = name

        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.02, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let textEntity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let bounds = textEntity.model?.mesh.bounds ?? mesh.bounds
        textEntity.position = SIMD3<Float>(-bounds.center.x, -bounds.center.y, 0.002)
        caption.addChild(textEntity)

        let backing = ModelEntity(
            mesh: .generatePlane(width: bounds.extents.x + 0.012, height: bounds.extents.y + 0.009, cornerRadius: 0.004),
            materials: [UnlitMaterial(color: UIColor(white: 0.05, alpha: 1.0))]
        )
        caption.addChild(backing)
        return caption
    }

    /// Adds/toggles a `"fixture_stand"` child cylinder on a fixture proxy container per `RigPlacement.support`.
    /// `.floorStand` → a slim grey post from the floor up to the fixture body (height = the container's scene
    /// height above the ground, i.e. `container.position.y`), centred locally so it reaches down to y = 0.
    /// `.hangFromTruss` → the stand is disabled (fixture hangs). Kept as a container child so an XZ drag
    /// carries it and it stays directly beneath the light. `static` (not `private`) so the live drag can
    /// re-run it mid-gesture (#15), keeping hang↔stand in step with the finger.
    static func syncFixtureStand(in container: Entity, position: Vector3Meters, layout: StageLayout) {
        let support = RigPlacement.support(forPosition: position, layout: layout)
        switch support {
        case .floorStand:
            let height = container.position.y // scene units from the ground to the fixture body
            let existing = container.findEntity(named: "fixture_stand") as? ModelEntity
            let stand = existing ?? {
                let m = ModelEntity(
                    mesh: .generateCylinder(height: max(height, sceneLength(0.05)), radius: sceneLength(0.035)),
                    materials: [material(hex: "#3A3D42")]
                )
                m.name = "fixture_stand"
                container.addChild(m)
                return m
            }()
            // Rebuild the mesh at the current height, then centre it locally so it spans y = 0 → fixture.
            stand.model?.mesh = .generateCylinder(height: max(height, sceneLength(0.05)), radius: sceneLength(0.035))
            stand.position = SIMD3<Float>(0, -height / 2, 0)
            stand.isEnabled = true
        case .hangFromTruss:
            container.findEntity(named: "fixture_stand")?.isEnabled = false
        }
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

    /// A small, cheap light proxy: a tilted cone "fixture body" with a glowing emissive lens, distinct from
    /// the grey truss rods. Carries collision + input target so it's tappable/draggable, plus a (hidden)
    /// selection ring toggled by `syncFixtures`. Coloured by the fixture's cue colour so it reads as "a
    /// light" rather than structure.
    private static func makeFixtureProxy(named name: String,
                                         model: LightingFixtureVisualModel,
                                         hex: String,
                                         aim: SIMD3<Float>) -> Entity {
        let container = Entity()
        container.name = name

        // Body: the fixture's real model-type geometry (moving head / PAR / strobe / laser …) shrunk to the
        // diorama and aimed front-first along `aim` — the SAME cached procedural model the 1:1 stage uses
        // (`ImmersiveView.addRigFixture`), so the desk rig reads at a glance and matches the immersive look.
        let body = FixtureRealityModel.makeStageFixture(for: model, targetHeight: sceneLength(0.4), aim: aim)
        body.name = "fixture_model"
        // The model is a container of nested meshes; make the whole subtree tappable/draggable with precise
        // per-mesh collision (mirrors the old cone's `addInteraction`, but recursive over the model tree).
        body.generateCollisionShapes(recursive: true)
        body.components.set(InputTargetComponent())
        container.addChild(body)

        // Lens: an emissive disc at the model's aim-front so the proxy glows in its colour — on the tabletop
        // there are no real spotlights, so this disc is the ONLY per-fixture colour cue. Named `"fixture_lens"`
        // so `syncFixtures` can recolour it to the CURRENT cue's colour every pass (#14).
        let aimUnit = simd_length(aim) > 0.0001 ? simd_normalize(aim) : SIMD3<Float>(0, -1, 0)
        let lens = ModelEntity(
            mesh: .generateCylinder(height: sceneLength(0.03), radius: sceneLength(0.13)),
            materials: [lensMaterial(hex: hex)]
        )
        lens.name = "fixture_lens"
        lens.orientation = orientation(from: SIMD3<Float>(0, 1, 0), to: aimUnit)
        lens.position = aimUnit * sceneLength(0.22)
        addInteraction(lens)
        container.addChild(lens)

        // Selection ring (hidden by default), toggled on while this fixture is selected.
        let ring = ModelEntity(
            mesh: .generateBox(width: sceneLength(0.6), height: sceneLength(0.05), depth: sceneLength(0.6), cornerRadius: sceneLength(0.05)),
            materials: [material(hex: "#3FB6FF")]
        )
        ring.name = "fixture_selection_highlight"
        ring.position = SIMD3<Float>(0, -sceneLength(0.3), 0)
        ring.isEnabled = false
        container.addChild(ring)

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

    /// The emissive lens `UnlitMaterial` for a fixture proxy, coloured by the fixture's CURRENT-cue colour
    /// hex. Shared by `makeFixtureProxy` (build) and `syncFixtures` (per-cue recolour, #14) so the built
    /// lens and the live recolour never drift.
    private static func lensMaterial(hex: String) -> UnlitMaterial {
        let rgb = RGBComponents(hex: hex) ?? .white
        var m = UnlitMaterial(color: UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1))
        m.blending = .opaque
        return m
    }
}

#Preview(immersionStyle: .mixed) {
    TabletopStageEditorView()
        .environment(AppModel())
}
#endif
