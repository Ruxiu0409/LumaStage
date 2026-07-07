import Foundation

enum StageUnits: String, Codable, CaseIterable {
    case meters
}

enum StageObjectType: String, Codable, CaseIterable {
    case stageBase
    case stageDeck
    case trussSegment
}

enum StageAssetId: String, Codable, CaseIterable {
    case stageBase = "stage_base"
    case stageDeck1x1 = "stage_deck_1x1"
    case stageDeck2x1 = "stage_deck_2x1"
    case stageDeck2x2 = "stage_deck_2x2"
    case truss1m = "truss_1m"
    case truss2m = "truss_2m"

    var displayName: String {
        switch self {
        case .stageBase:
            return "Stage Base"
        case .stageDeck1x1:
            return "Small Stage Deck"
        case .stageDeck2x1:
            return "Long Stage Deck"
        case .stageDeck2x2:
            return "Standard Stage Deck"
        case .truss1m:
            return "1m Truss"
        case .truss2m:
            return "2m Truss"
        }
    }

    var objectType: StageObjectType {
        switch self {
        case .stageBase:
            return .stageBase
        case .stageDeck1x1, .stageDeck2x1, .stageDeck2x2:
            return .stageDeck
        case .truss1m, .truss2m:
            return .trussSegment
        }
    }

    var deckSize: StageObjectSize? {
        switch self {
        case .stageBase:
            return StageObjectSize(width: 4, depth: 2, height: 0.8)
        case .stageDeck1x1:
            return StageObjectSize(width: 1, depth: 1, height: 0.8)
        case .stageDeck2x1:
            return StageObjectSize(width: 2, depth: 1, height: 0.8)
        case .stageDeck2x2:
            return StageObjectSize(width: 2, depth: 2, height: 0.8)
        case .truss1m, .truss2m:
            return nil
        }
    }

    var trussLength: Double? {
        switch self {
        case .truss1m:
            return 1
        case .truss2m:
            return 2
        case .stageBase, .stageDeck1x1, .stageDeck2x1, .stageDeck2x2:
            return nil
        }
    }
}

enum StagePortalPreset: String, Codable, CaseIterable {
    case portal4x3 = "portal_4x3"
    case portal6x5 = "portal_6x5"
    case portal8x4 = "portal_8x4"

    var displayName: String {
        switch self {
        case .portal4x3:
            return "4m x 3m Portal Truss"
        case .portal6x5:
            return "6m x 5m Portal Truss"
        case .portal8x4:
            return "8m x 4m Portal Truss"
        }
    }

    var width: Double {
        switch self {
        case .portal4x3:
            return 4
        case .portal6x5:
            return 6
        case .portal8x4:
            return 8
        }
    }

    var height: Double {
        switch self {
        case .portal4x3:
            return 3
        case .portal6x5:
            return 5
        case .portal8x4:
            return 4
        }
    }
}

enum StagePlatformPreset: String, Codable, CaseIterable {
    case small4x2 = "stage_preset_4x2"
    case medium6x3 = "stage_preset_6x3"
    case large8x4 = "stage_preset_8x4"

    var displayName: String {
        switch self {
        case .small4x2:
            return "Small Stage"
        case .medium6x3:
            return "Medium Stage"
        case .large8x4:
            return "Large Stage"
        }
    }

    var stageBaseSize: StageObjectSize {
        switch self {
        case .small4x2:
            return StageObjectSize(width: 4, depth: 2, height: 0.8)
        case .medium6x3:
            return StageObjectSize(width: 6, depth: 3, height: 0.8)
        case .large8x4:
            return StageObjectSize(width: 8, depth: 4, height: 0.8)
        }
    }
}

struct Vector3Meters: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3Meters(x: 0, y: 0, z: 0)

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    func distance(to other: Vector3Meters) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    static func + (lhs: Vector3Meters, rhs: Vector3Meters) -> Vector3Meters {
        Vector3Meters(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func - (lhs: Vector3Meters, rhs: Vector3Meters) -> Vector3Meters {
        Vector3Meters(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    func scaled(by factor: Double) -> Vector3Meters {
        Vector3Meters(x: x * factor, y: y * factor, z: z * factor)
    }
}

struct Vector3Degrees: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3Degrees(x: 0, y: 0, z: 0)

    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }

    var isRightAngleAligned: Bool {
        [x, y, z].allSatisfy { angle in
            abs(angle / 90 - round(angle / 90)) < 0.0001
        }
    }
}

struct StageObjectSize: Codable, Equatable {
    var width: Double
    var depth: Double
    var height: Double
}

enum StageBaseFaceKind: String, Equatable {
    case top
    case bottom
    case front
    case back
    case left
    case right
}

struct StageBaseFace: Equatable {
    var kind: StageBaseFaceKind
    var vertices: [Vector3Meters]
}

struct StageBaseSolid: Equatable {
    var vertices: [Vector3Meters]
    var faces: [StageBaseFace]
}

enum StageDeckFaceKind: String, Equatable {
    case topSurface
    case underside
    case frontFrameSkirt
    case backFrameSkirt
    case leftFrameSkirt
    case rightFrameSkirt

    var isFrameSkirt: Bool {
        switch self {
        case .frontFrameSkirt, .backFrameSkirt, .leftFrameSkirt, .rightFrameSkirt:
            return true
        case .topSurface, .underside:
            return false
        }
    }
}

struct StageDeckFace: Equatable {
    var kind: StageDeckFaceKind
    var vertices: [Vector3Meters]
}

struct StageDeckSupportLeg: Equatable {
    var top: Vector3Meters
    var bottom: Vector3Meters
    var radius: Double
}

struct StageDeckAssembly: Equatable {
    var faces: [StageDeckFace]
    var frameRails: [TrussVisualMember]
    var supportLegs: [StageDeckSupportLeg]
    var crossBraces: [TrussVisualMember]
}

struct StageBuilderPanelLayout: Equatable {
    var usesStackedPanels: Bool
    var usesScrollableLibraryPanel: Bool
    var libraryWidth: Double
    var inspectorWidth: Double
    var bottomPanelWidth: Double
    var minimumViewportWidth: Double
    var spacing: Double

    static func make(availableWidth: Double) -> StageBuilderPanelLayout {
        let spacing = 14.0
        let minimumViewportWidth = 420.0

        if availableWidth < 900 {
            let panelWidth = max(220, (availableWidth - spacing) / 2)
            return StageBuilderPanelLayout(
                usesStackedPanels: true,
                usesScrollableLibraryPanel: true,
                libraryWidth: panelWidth,
                inspectorWidth: panelWidth,
                bottomPanelWidth: panelWidth,
                minimumViewportWidth: min(availableWidth, minimumViewportWidth),
                spacing: spacing
            )
        }

        let libraryWidth = min(230, max(200, availableWidth * 0.22))
        let inspectorWidth = min(290, max(250, availableWidth * 0.27))
        return StageBuilderPanelLayout(
            usesStackedPanels: false,
            usesScrollableLibraryPanel: true,
            libraryWidth: libraryWidth,
            inspectorWidth: inspectorWidth,
            bottomPanelWidth: 0,
            minimumViewportWidth: minimumViewportWidth,
            spacing: spacing
        )
    }
}

enum IPadRootLayout {
    static let projectSelectionHorizontalPadding = 24.0

    static func projectSelectionWidth(availableWidth: Double) -> Double {
        max(0, availableWidth - projectSelectionHorizontalPadding * 2)
    }
}

enum StageBuilderZoom {
    static let minimum = 0.65
    static let maximum = 1.6

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    static func scaled(base: Double, magnification: Double) -> Double {
        clamped(base * magnification)
    }
}

enum StageBuilderPickerPresentation {
    case menu
    case segmented
}

enum StageBuilderToolbarLayout {
    static let cameraPickerPresentation: StageBuilderPickerPresentation = .menu
    static let showsZoomStepper = false
    static let showsLayoutSummaryChips = false
}

struct StageBuilderGroundLine: Equatable {
    var start: Vector3Meters
    var end: Vector3Meters
    var isMajor: Bool
}

enum StageBuilderViewportGround {
    static let extent = 7.0
    static let step = 0.5
    static let majorInterval = 2.0

    static var usesProjectedWorldPlane: Bool {
        true
    }

    static func referenceLines() -> [StageBuilderGroundLine] {
        stride(from: -extent, through: extent, by: step).flatMap { coordinate in
            let isMajor = abs((coordinate / majorInterval).rounded() - coordinate / majorInterval) < 0.0001
            return [
                StageBuilderGroundLine(
                    start: Vector3Meters(x: -extent, y: 0, z: coordinate),
                    end: Vector3Meters(x: extent, y: 0, z: coordinate),
                    isMajor: isMajor
                ),
                StageBuilderGroundLine(
                    start: Vector3Meters(x: coordinate, y: 0, z: -extent),
                    end: Vector3Meters(x: coordinate, y: 0, z: extent),
                    isMajor: isMajor
                )
            ]
        }
    }
}

enum StageBuilderRenderLayer {
    case behindStageBase
    case scene
}

enum StageBuilderRenderOrder {
    static func objectsForIsometricViewport(_ objects: [StageObject]) -> [StageObject] {
        objects.sorted { lhs, rhs in
            if lhsRenderDepth(lhs) == lhsRenderDepth(rhs) {
                return lhs.id < rhs.id
            }
            return lhsRenderDepth(lhs) < lhsRenderDepth(rhs)
        }
    }

    static func connectorLayer(position: Vector3Meters, stageBase: StageObject?) -> StageBuilderRenderLayer {
        guard
            let stageBase,
            let stageSize = stageBase.size
        else {
            return .scene
        }

        let stageBackEdge = stageBase.position.z - stageSize.depth / 2
        return position.z <= stageBackEdge ? .behindStageBase : .scene
    }

    static func shouldRenderConnectorBlock(_ block: TrussConnectorBlock, stageBase: StageObject?) -> Bool {
        guard connectorLayer(position: block.position, stageBase: stageBase) == .behindStageBase else {
            return true
        }

        guard let stageTopY = stageTopY(stageBase: stageBase) else {
            return true
        }

        return block.position.y >= stageTopY
    }

    static func trussOcclusionMinimumY(for object: StageObject, stageBase: StageObject?) -> Double? {
        guard
            object.type == .trussSegment,
            let stageBase,
            connectorLayer(position: object.position, stageBase: stageBase) == .behindStageBase
        else {
            return nil
        }

        return stageTopY(stageBase: stageBase)
    }

    static func clipMembers(_ members: [TrussVisualMember], minimumY: Double?) -> [TrussVisualMember] {
        guard let minimumY else {
            return members
        }

        return members.compactMap { clipMember($0, minimumY: minimumY) }
    }

    private static func clipMember(_ member: TrussVisualMember, minimumY: Double) -> TrussVisualMember? {
        let startVisible = member.start.y >= minimumY
        let endVisible = member.end.y >= minimumY

        if startVisible && endVisible {
            return member
        }

        if !startVisible && !endVisible {
            return nil
        }

        let dy = member.end.y - member.start.y
        guard abs(dy) > 0.0001 else {
            return nil
        }

        let t = (minimumY - member.start.y) / dy
        let clippedPoint = Vector3Meters(
            x: member.start.x + (member.end.x - member.start.x) * t,
            y: minimumY,
            z: member.start.z + (member.end.z - member.start.z) * t
        )

        if startVisible {
            return TrussVisualMember(start: member.start, end: clippedPoint)
        } else {
            return TrussVisualMember(start: clippedPoint, end: member.end)
        }
    }

    private static func stageTopY(stageBase: StageObject?) -> Double? {
        guard let stageBase, let size = stageBase.size else {
            return nil
        }

        return stageBase.position.y + size.height / 2
    }

    private static func lhsRenderDepth(_ object: StageObject) -> Double {
        switch object.type {
        case .trussSegment:
            return object.position.z - 0.15
        case .stageBase, .stageDeck:
            return object.position.z
        }
    }
}

enum StageBuilderInspectorPolicy {
    static func isVisible(selectedObjectId: String?) -> Bool {
        selectedObjectId != nil
    }
}

enum StageBuilderSelectionPolicy {
    static func selectedObjectIdAfterViewportTap(currentSelectionId: String?, hitObjectId: String?) -> String? {
        hitObjectId
    }
}

/// Foundation-only editing operations for the tabletop stage editor: swapping the stage-platform
/// and truss-portal presets, and reflecting which preset a layout currently matches so the editor's
/// controls can show the active selection. Pure (each `applying…` returns a new `StageLayout`) so the
/// smoke tests can pin the swap/reflect behavior without a RealityKit volume. The visionOS
/// `TabletopStageEditorView` is the only consumer; results are persisted through
/// `AppModel.saveStageLayout`, which runs `StageLayout.validate()`.
enum TabletopStageEditing {
    /// Replaces the layout's single stage base with one sized to `preset`, preserving the base's id
    /// and x/z position (its y is reseated to `height / 2` by the stage-base factory). Adds a base at
    /// the origin if the layout somehow has none.
    static func applyingStagePlatformPreset(_ preset: StagePlatformPreset, to layout: StageLayout) -> StageLayout {
        var layout = layout
        let size = preset.stageBaseSize
        if let index = layout.objects.firstIndex(where: { $0.type == .stageBase }) {
            let existing = layout.objects[index]
            layout.objects[index] = .stageBase(
                id: existing.id,
                displayName: existing.displayName,
                position: Vector3Meters(x: existing.position.x, y: 0, z: existing.position.z),
                size: size
            )
        } else {
            layout.objects.append(.stageBase(id: "stage_base_default", position: .zero, size: size))
        }
        return layout
    }

    /// Replaces every truss segment with a fresh portal of `preset`, seated just behind the stage
    /// base's upstage edge (matching `defaultStudentOutdoor`'s 0.25m stand-off).
    static func applyingTrussPortalPreset(_ preset: StagePortalPreset, to layout: StageLayout) -> StageLayout {
        var layout = layout
        layout.objects.removeAll { $0.type == .trussSegment }
        let stageDepth = layout.objects.first(where: { $0.type == .stageBase })?.size?.depth ?? 3
        let upstageZ = -(stageDepth / 2) - 0.25
        layout.objects.append(contentsOf: StageLayout.trussPortalPreset(preset, upstageZ: upstageZ))
        return layout
    }

    /// The platform preset whose footprint matches the layout's stage base (by width × depth), if any.
    static func currentStagePlatformPreset(of layout: StageLayout) -> StagePlatformPreset? {
        guard let size = layout.objects.first(where: { $0.type == .stageBase })?.size else {
            return nil
        }
        return StagePlatformPreset.allCases.first {
            abs($0.stageBaseSize.width - size.width) < 0.01 && abs($0.stageBaseSize.depth - size.depth) < 0.01
        }
    }

    /// The portal preset whose span matches the layout's truss endpoints (by width × height), if any.
    static func currentTrussPortalPreset(of layout: StageLayout) -> StagePortalPreset? {
        let endpoints = layout.objects.filter { $0.type == .trussSegment }.flatMap(\.trussEndpoints)
        guard let minX = endpoints.map(\.x).min(),
              let maxX = endpoints.map(\.x).max(),
              let maxY = endpoints.map(\.y).max() else {
            return nil
        }
        let width = maxX - minX
        return StagePortalPreset.allCases.first {
            abs($0.width - width) < 0.3 && abs($0.height - maxY) < 0.3
        }
    }
}

/// Foundation-only：桌面編輯器「方向微調鍵 + 座標讀數」的純邏輯（#17）。
/// 小尺度 diorama（scale 0.07）上要拖到精準位置很難，也沒有數值回饋，故提供：
///   1. 固定步距的軸向位移（現位置 + 帶號步距 → 新位置），落地交給 `AppModel.moveFixture`。
///   2. 座標讀數字串（model 公尺 x/z → 「x 1.50・z −2.00」，2 位小數、負號用真正的減號 U+2212）。
/// view（`TabletopStageEditorView`）只是薄消費者：微調鍵用 `nudged` 算出新 x/z 再呼叫 `moveFixture`，
/// 選取狀態列用 `readout` 顯示目前解析位置。
enum TabletopNudge {
    /// 每按一次微調鍵的位移量（model 公尺）。
    static let stepMeters: Double = 0.25

    enum Axis { case x, z }

    /// 目前座標沿指定軸位移 `sign * stepMeters`（`sign` 只看正負，>=0 視為 +1，其餘 -1），
    /// 未指定的軸原樣保留。
    static func nudged(x: Double, z: Double, axis: Axis, sign: Double) -> (x: Double, z: Double) {
        let delta = sign >= 0 ? stepMeters : -stepMeters
        switch axis {
        case .x: return (x + delta, z)
        case .z: return (x, z + delta)
        }
    }

    /// 「x 1.50・z −2.00」——2 位小數、CJK 間隔號分隔、負號用真正的 U+2212 減號（比 hyphen 好讀）。
    static func readout(x: Double, z: Double) -> String {
        "x \(component(x))・z \(component(z))"
    }

    /// 單一座標分量：四捨五入到 2 位後再判號，避免出現 "−0.00"；負值前綴真正的減號 U+2212。
    private static func component(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let magnitude = String(format: "%.2f", abs(rounded))
        return rounded < 0 ? "−\(magnitude)" : magnitude
    }
}

struct StageEditingSnapshot: Equatable {
    var layout: StageLayout
    var lightingLook: LightingLook
}

struct StageEditingUndoStack: Equatable {
    private var latestSnapshot: StageEditingSnapshot?

    var canUndo: Bool {
        latestSnapshot != nil
    }

    mutating func push(layout: StageLayout, lightingLook: LightingLook) {
        latestSnapshot = StageEditingSnapshot(layout: layout, lightingLook: lightingLook)
    }

    mutating func pop() -> StageEditingSnapshot? {
        defer { latestSnapshot = nil }
        return latestSnapshot
    }

    mutating func clear() {
        latestSnapshot = nil
    }
}

enum StageBuilderStageLibraryAssets {
    static let stageTab: [StageAssetId] = [.stageBase]
}

enum StageBuilderObjectLayerHitTesting {
    static func allowsDirectLayerTap(for type: StageObjectType) -> Bool {
        switch type {
        case .stageBase, .stageDeck, .trussSegment:
            return false
        }
    }
}

/// A horizontal surface ARKit reported, reduced to the Foundation-only facts the tabletop editor needs to
/// decide where to rest the diorama. `center` is the surface centre in world metres; `width`/`depth` are
/// its extents (metres); `isTable` is true when ARKit classified it as a table (vs. floor/ceiling/seat/
/// unknown); `facesUp` is true when the surface normal points up (a table/floor) rather than down (a
/// ceiling).
struct DetectedHorizontalSurface: Equatable {
    var center: Vector3Meters
    var width: Double
    var depth: Double
    var isTable: Bool
    var facesUp: Bool

    var area: Double { width * depth }
}

/// Decides which detected real-world surface the tabletop diorama should rest on. Pure (no ARKit), so the
/// rule is smoke-tested without a device — `TabletopStageEditorView` feeds it the surfaces ARKit's
/// `PlaneDetectionProvider` reports and rests the model on the winner, or keeps the model floating in front
/// of the user when nothing qualifies.
enum TabletopSurfaceSelection {
    /// Minimum footprint (metres, each side) a surface must have to host the diorama — smaller surfaces
    /// (shelves, a mug) are ignored so the model doesn't snap onto something it would overhang.
    static let minimumExtent: Double = 0.3

    /// Picks the **real table** to rest on (largest, then nearest to `viewer`). Only up-facing,
    /// table-classified surfaces meeting the minimum footprint qualify — so the model never lands on the
    /// floor, a down-facing ceiling, or any other horizontal plane. Returns `nil` when no table qualifies,
    /// so the caller keeps the diorama floating in front of the user until a real table appears (the chosen
    /// fallback). This is what stops `PlaneDetectionProvider`'s large horizontal ceiling/floor planes from
    /// being picked.
    static func bestSurface(from surfaces: [DetectedHorizontalSurface], viewer: Vector3Meters) -> DetectedHorizontalSurface? {
        let eligible = surfaces.filter {
            $0.isTable && $0.facesUp && $0.width >= minimumExtent && $0.depth >= minimumExtent
        }
        // `max(by:)` keeps the element for which the closure returns false against all others, i.e. the
        // "greatest" under our preference order. The closure returns true when `lhs` is the lesser pick.
        return eligible.max { lhs, rhs in
            if abs(lhs.area - rhs.area) > 0.0001 {
                return lhs.area < rhs.area // larger footprint wins
            }
            return lhs.center.distance(to: viewer) > rhs.center.distance(to: viewer) // nearer wins
        }
    }
}

enum StageBuilderDropPlanner {
    static func object(
        assetId: StageAssetId,
        id: String,
        existingObjects: [StageObject],
        dropPosition: Vector3Meters?
    ) -> StageObject? {
        let fallbackPosition = defaultPosition(assetId: assetId, existingObjects: existingObjects)
        let placement = dropPosition ?? fallbackPosition

        switch assetId.objectType {
        case .stageBase:
            return .stageBase(
                id: id,
                position: Vector3Meters(x: placement.x, y: 0, z: placement.z),
                size: StageObjectSize(width: 4, depth: 2, height: 0.8)
            )
        case .stageDeck:
            return nil
        case .trussSegment:
            return .trussSegment(
                id: id,
                assetId: assetId,
                position: Vector3Meters(x: placement.x, y: 3, z: placement.z),
                rotation: .zero
            )
        }
    }

    private static func defaultPosition(assetId: StageAssetId, existingObjects: [StageObject]) -> Vector3Meters {
        switch assetId.objectType {
        case .stageBase:
            let baseCount = existingObjects.filter { $0.type == .stageBase }.count
            return Vector3Meters(x: 0, y: 0, z: Double(baseCount) * 0.5)
        case .stageDeck:
            let deckCount = existingObjects.filter { $0.type == .stageDeck }.count
            return Vector3Meters(x: Double(deckCount % 4) - 1.5, y: 0, z: Double(deckCount / 4))
        case .trussSegment:
            let trussCount = existingObjects.filter { $0.type == .trussSegment }.count
            return Vector3Meters(x: Double(trussCount % 4) - 2, y: 3, z: -1.25)
        }
    }
}

struct TrussVisualMember: Equatable {
    var start: Vector3Meters
    var end: Vector3Meters
}

struct TrussEndCap: Equatable {
    var members: [TrussVisualMember]
}

struct TrussLattice: Equatable {
    var chords: [TrussVisualMember]
    var braces: [TrussVisualMember]
    var endCaps: [TrussEndCap]

    static let empty = TrussLattice(chords: [], braces: [], endCaps: [])

    var allMembers: [TrussVisualMember] {
        chords + braces + endCaps.flatMap(\.members)
    }
}

struct TrussConnectorBlock: Equatable, Identifiable {
    var id: String
    var position: Vector3Meters
    var size: Double
}

/// A live connector-node snap: where a dragged truss should sit (`position`) so one of its endpoints
/// lands exactly on an existing truss endpoint (`node`). Surfaced from `StageLayout.trussNodeSnap` so the
/// tabletop editor can both reposition the piece and mark the node it locked onto while the user drags.
struct TrussNodeSnap: Equatable {
    var position: Vector3Meters
    var node: Vector3Meters
}

struct ImmersiveStageGeometryPlan: Equatable {
    var stageBases: [StageObject]
    var trussMembers: [TrussVisualMember]
    var connectorBlocks: [TrussConnectorBlock]
    var layoutSignature: String

    static let usesSharedStageLayout = true

    static func make(from layout: StageLayout) -> ImmersiveStageGeometryPlan {
        let stageBases = layout.objects.filter { $0.type == .stageBase }
        let trussMembers = layout.objects
            .filter { $0.type == .trussSegment }
            .flatMap { $0.trussLattice.allMembers }
        let connectorBlocks = layout.trussConnectorBlocks

        return ImmersiveStageGeometryPlan(
            stageBases: stageBases,
            trussMembers: trussMembers,
            connectorBlocks: connectorBlocks,
            layoutSignature: signature(for: layout, connectorBlocks: connectorBlocks)
        )
    }

    private static func signature(for layout: StageLayout, connectorBlocks: [TrussConnectorBlock]) -> String {
        let objectSignature = layout.objects.map { object in
            [
                object.id,
                object.type.rawValue,
                object.assetId.rawValue,
                value(object.position.x),
                value(object.position.y),
                value(object.position.z),
                value(object.rotation.x),
                value(object.rotation.y),
                value(object.rotation.z),
                value(object.size?.width),
                value(object.size?.depth),
                value(object.size?.height),
                value(object.length)
            ].joined(separator: ",")
        }.joined(separator: "|")

        let connectorSignature = connectorBlocks.map { block in
            [
                block.id,
                value(block.position.x),
                value(block.position.y),
                value(block.position.z),
                value(block.size)
            ].joined(separator: ",")
        }.joined(separator: "|")

        return "\(layout.stageLayoutId)#\(objectSignature)#\(connectorSignature)"
    }

    private static func value(_ number: Double?) -> String {
        guard let number else {
            return "-"
        }

        return String(format: "%.4f", number)
    }
}

/// Foundation-only skeleton + segment plan for the procedural performer mannequin. Given the feet
/// point (on the deck), a total height in metres and a facing, it computes every joint position and
/// the bone/slab list the immersive renderer builds from. Pure value type so the proportions stay
/// pinned by a smoke test without RealityKit — `ImmersiveView.addPerformerStandIn` is the only consumer.
///
/// Coordinate convention: `+x` is stage-right of the stand point, `+y` is up from the deck, `+z` is
/// downstage (toward the audience). Authored against a 1.75 m / 7.5-head canon and scaled uniformly to
/// any `totalHeight`, so the head top lands at exactly `feet.y + totalHeight` (`headCenter.y + headRadius`).
/// Foundation-only build plan for the performer figure, modelled on the **Meccha Chameleon** game
/// character: a smooth, pure-white, friendly chunky biped (big round head, rounded egg torso, smooth
/// thick limbs, rounded hand/foot stubs, blank face). Given the feet point on the deck it computes the
/// rounded body masses (`blobs` — scaled spheres for head/torso/hips/feet) and the smooth limbs
/// (`bones` — capsule-style cylinders) plus their rounding `joints`. Pure value type so the proportions
/// stay pinned by a smoke test without RealityKit; `ImmersiveView.addPerformerStandIn` is the only consumer.
///
/// Coordinate convention: `+x` is stage-right of the stand point, `+y` is up from the deck, `+z` is
/// downstage (toward the audience). Authored against a ~1.70 m, big-headed (~4.5-head) cartoon canon and
/// scaled uniformly to any `totalHeight`, so the head top lands at exactly `feet.y + totalHeight`.
struct HumanoidFigurePlan: Equatable {
    enum BoneRole: String { case upperArm, forearm, thigh, shin }

    /// A rounding sphere at a joint (or a rounded hand/foot stub). Its radius matches the adjoining limb
    /// so the figure reads as one smooth surface, not a stack of beads.
    struct Joint: Equatable {
        var id: String
        var position: Vector3Meters
        var capRadius: Double
    }

    /// A smooth limb: a cylinder between two joints, rendered with rounded (sphere) end caps.
    struct Bone: Equatable {
        var role: BoneRole
        var a: Vector3Meters
        var b: Vector3Meters
        var radius: Double
    }

    /// A rounded body mass: a unit sphere of `radius` stretched per-axis by `scale` (dimensionless
    /// factors, not metres) into an ovoid — head, torso, hips, feet. This gives the character its
    /// smooth, blobby silhouette instead of boxes.
    struct Blob: Equatable {
        var id: String
        var center: Vector3Meters
        var radius: Double
        var scale: Vector3Meters
    }

    var totalHeight: Double
    var headCenter: Vector3Meters
    var headRadius: Double
    var joints: [Joint]
    var bones: [Bone]
    var blobs: [Blob]

    static func make(
        feet: Vector3Meters,
        totalHeight: Double = 1.70,
        contrapposto: Double = 0
    ) -> HumanoidFigurePlan {
        // Author against the ~1.70 m, big-headed cartoon canon, then scale uniformly so the proportions
        // hold at any height.
        let s = totalHeight / 1.70
        func p(_ dx: Double, _ dy: Double, _ dz: Double) -> Vector3Meters {
            feet + Vector3Meters(x: dx * s, y: dy * s, z: dz * s)
        }
        func factors(_ x: Double, _ y: Double, _ z: Double) -> Vector3Meters {
            Vector3Meters(x: x, y: y, z: z)   // per-axis sphere scale, dimensionless
        }
        // Optional weight shift: drop the left-side joints a few millimetres. Default 0 is a clean,
        // symmetric stance (on-brand for the cheerful mascot); the smoke test exercises a non-zero value.
        let cp = max(0, min(contrapposto, 1)) * 0.012 * s

        // Big round head; its bottom overlaps the torso top so there is no neck gap.
        let headRadius = 0.19 * s
        let headCenter = p(0, 1.70 - 0.19, 0)

        let shoulderR = Joint(id: "shoulder_r", position: p(0.205, 1.28 - cp, 0), capRadius: 0.085 * s)
        let shoulderL = Joint(id: "shoulder_l", position: p(-0.205, 1.28, 0), capRadius: 0.085 * s)
        let elbowR = Joint(id: "elbow_r", position: p(0.235, 0.99 - cp, 0.02), capRadius: 0.075 * s)
        let elbowL = Joint(id: "elbow_l", position: p(-0.235, 0.99, 0.02), capRadius: 0.075 * s)
        let handR = Joint(id: "hand_r", position: p(0.225, 0.74 - cp, 0.05), capRadius: 0.088 * s)
        let handL = Joint(id: "hand_l", position: p(-0.225, 0.74, 0.05), capRadius: 0.088 * s)
        let hipR = Joint(id: "hip_r", position: p(0.105, 0.72, 0), capRadius: 0.105 * s)
        let hipL = Joint(id: "hip_l", position: p(-0.105, 0.72 - cp, 0), capRadius: 0.105 * s)
        let kneeR = Joint(id: "knee_r", position: p(0.110, 0.40, 0.02), capRadius: 0.100 * s)
        let kneeL = Joint(id: "knee_l", position: p(-0.110, 0.40 - cp, 0.02), capRadius: 0.100 * s)
        // Feet stay planted (no weight shift) so both keep solid deck contact.
        let ankleR = Joint(id: "ankle_r", position: p(0.105, 0.07, 0), capRadius: 0.095 * s)
        let ankleL = Joint(id: "ankle_l", position: p(-0.105, 0.07, 0), capRadius: 0.095 * s)

        let joints = [
            shoulderR, shoulderL, elbowR, elbowL, handR, handL,
            hipR, hipL, kneeR, kneeL, ankleR, ankleL
        ]

        let bones = [
            Bone(role: .upperArm, a: shoulderR.position, b: elbowR.position, radius: 0.080 * s),
            Bone(role: .upperArm, a: shoulderL.position, b: elbowL.position, radius: 0.080 * s),
            Bone(role: .forearm, a: elbowR.position, b: handR.position, radius: 0.072 * s),
            Bone(role: .forearm, a: elbowL.position, b: handL.position, radius: 0.072 * s),
            Bone(role: .thigh, a: hipR.position, b: kneeR.position, radius: 0.100 * s),
            Bone(role: .thigh, a: hipL.position, b: kneeL.position, radius: 0.100 * s),
            Bone(role: .shin, a: kneeR.position, b: ankleR.position, radius: 0.092 * s),
            Bone(role: .shin, a: kneeL.position, b: ankleL.position, radius: 0.092 * s)
        ]

        // Rounded masses. Torso is a smooth egg; hips a flattened sphere bridging torso and legs; feet
        // are small, flattened, forward-stretched spheres giving a believable contact footprint.
        let blobs = [
            Blob(id: "torso", center: p(0, 1.05, 0), radius: 0.215 * s, scale: factors(1.0, 1.42, 0.85)),
            Blob(id: "hips", center: p(0, 0.73, 0), radius: 0.190 * s, scale: factors(1.05, 0.72, 0.90)),
            Blob(id: "foot_r", center: p(0.105, 0.04, 0.055), radius: 0.085 * s, scale: factors(1.05, 0.55, 1.70)),
            Blob(id: "foot_l", center: p(-0.105, 0.04, 0.055), radius: 0.085 * s, scale: factors(1.05, 0.55, 1.70))
        ]

        return HumanoidFigurePlan(
            totalHeight: totalHeight,
            headCenter: headCenter,
            headRadius: headRadius,
            joints: joints,
            bones: bones,
            blobs: blobs
        )
    }
}

struct StageObject: Codable, Equatable, Identifiable {
    var id: String
    var type: StageObjectType
    var assetId: StageAssetId
    var displayName: String
    var position: Vector3Meters
    var rotation: Vector3Degrees
    var size: StageObjectSize?
    var length: Double?
    var connectorIds: [String]
    var locked: Bool

    static func stageDeck(
        id: String,
        assetId: StageAssetId,
        displayName: String? = nil,
        position: Vector3Meters,
        rotation: Vector3Degrees = .zero
    ) -> StageObject {
        StageObject(
            id: id,
            type: .stageDeck,
            assetId: assetId,
            displayName: displayName ?? assetId.displayName,
            position: position,
            rotation: rotation,
            size: assetId.deckSize,
            length: nil,
            connectorIds: [],
            locked: false
        )
    }

    static func stageBase(
        id: String,
        displayName: String? = nil,
        position: Vector3Meters,
        size: StageObjectSize = StageObjectSize(width: 4, depth: 2, height: 0.8)
    ) -> StageObject {
        StageObject(
            id: id,
            type: .stageBase,
            assetId: .stageBase,
            displayName: displayName ?? StageAssetId.stageBase.displayName,
            position: Vector3Meters(x: position.x, y: size.height / 2, z: position.z),
            rotation: .zero,
            size: size,
            length: nil,
            connectorIds: [],
            locked: false
        )
    }

    static func trussSegment(
        id: String,
        assetId: StageAssetId,
        displayName: String? = nil,
        position: Vector3Meters,
        rotation: Vector3Degrees = .zero
    ) -> StageObject {
        StageObject(
            id: id,
            type: .trussSegment,
            assetId: assetId,
            displayName: displayName ?? assetId.displayName,
            position: position,
            rotation: rotation,
            size: nil,
            length: assetId.trussLength,
            connectorIds: ["\(id)_a", "\(id)_b"],
            locked: false
        )
    }

    var trussEndpoints: [Vector3Meters] {
        guard type == .trussSegment, let length else {
            return []
        }

        let direction: Vector3Meters
        if abs(rotation.z).truncatingRemainder(dividingBy: 180) == 90 {
            direction = Vector3Meters(x: 0, y: length, z: 0)
        } else if abs(rotation.y).truncatingRemainder(dividingBy: 180) == 90 {
            direction = Vector3Meters(x: 0, y: 0, z: length)
        } else {
            direction = Vector3Meters(x: length, y: 0, z: 0)
        }

        return [position, position + direction]
    }

    var stageBaseSolid: StageBaseSolid? {
        guard type == .stageBase, let size else {
            return nil
        }

        let halfWidth = size.width / 2
        let halfDepth = size.depth / 2
        let topY = position.y + size.height / 2
        let bottomY = position.y - size.height / 2

        let bottomBackLeft = Vector3Meters(x: position.x - halfWidth, y: bottomY, z: position.z - halfDepth)
        let bottomBackRight = Vector3Meters(x: position.x + halfWidth, y: bottomY, z: position.z - halfDepth)
        let bottomFrontRight = Vector3Meters(x: position.x + halfWidth, y: bottomY, z: position.z + halfDepth)
        let bottomFrontLeft = Vector3Meters(x: position.x - halfWidth, y: bottomY, z: position.z + halfDepth)
        let topBackLeft = Vector3Meters(x: position.x - halfWidth, y: topY, z: position.z - halfDepth)
        let topBackRight = Vector3Meters(x: position.x + halfWidth, y: topY, z: position.z - halfDepth)
        let topFrontRight = Vector3Meters(x: position.x + halfWidth, y: topY, z: position.z + halfDepth)
        let topFrontLeft = Vector3Meters(x: position.x - halfWidth, y: topY, z: position.z + halfDepth)

        let vertices = [
            bottomBackLeft,
            bottomBackRight,
            bottomFrontRight,
            bottomFrontLeft,
            topBackLeft,
            topBackRight,
            topFrontRight,
            topFrontLeft
        ]

        return StageBaseSolid(
            vertices: vertices,
            faces: [
                StageBaseFace(kind: .bottom, vertices: [bottomBackLeft, bottomBackRight, bottomFrontRight, bottomFrontLeft]),
                StageBaseFace(kind: .back, vertices: [bottomBackLeft, topBackLeft, topBackRight, bottomBackRight]),
                StageBaseFace(kind: .right, vertices: [bottomBackRight, topBackRight, topFrontRight, bottomFrontRight]),
                StageBaseFace(kind: .front, vertices: [bottomFrontLeft, bottomFrontRight, topFrontRight, topFrontLeft]),
                StageBaseFace(kind: .left, vertices: [bottomBackLeft, bottomFrontLeft, topFrontLeft, topBackLeft]),
                StageBaseFace(kind: .top, vertices: [topBackLeft, topBackRight, topFrontRight, topFrontLeft])
            ]
        )
    }

    var stageDeckAssembly: StageDeckAssembly? {
        guard type == .stageDeck, let size else {
            return nil
        }

        let halfWidth = size.width / 2
        let halfDepth = size.depth / 2
        let topY = position.y + size.height / 2
        let groundY = max(0, position.y - size.height / 2)
        let deckThickness = min(0.14, max(0.08, size.height * 0.16))
        let bottomY = topY - deckThickness

        let topBackLeft = Vector3Meters(x: position.x - halfWidth, y: topY, z: position.z - halfDepth)
        let topBackRight = Vector3Meters(x: position.x + halfWidth, y: topY, z: position.z - halfDepth)
        let topFrontRight = Vector3Meters(x: position.x + halfWidth, y: topY, z: position.z + halfDepth)
        let topFrontLeft = Vector3Meters(x: position.x - halfWidth, y: topY, z: position.z + halfDepth)
        let bottomBackLeft = Vector3Meters(x: position.x - halfWidth, y: bottomY, z: position.z - halfDepth)
        let bottomBackRight = Vector3Meters(x: position.x + halfWidth, y: bottomY, z: position.z - halfDepth)
        let bottomFrontRight = Vector3Meters(x: position.x + halfWidth, y: bottomY, z: position.z + halfDepth)
        let bottomFrontLeft = Vector3Meters(x: position.x - halfWidth, y: bottomY, z: position.z + halfDepth)

        let faces = [
            StageDeckFace(kind: .underside, vertices: [bottomBackLeft, bottomBackRight, bottomFrontRight, bottomFrontLeft]),
            StageDeckFace(kind: .backFrameSkirt, vertices: [bottomBackLeft, topBackLeft, topBackRight, bottomBackRight]),
            StageDeckFace(kind: .rightFrameSkirt, vertices: [bottomBackRight, topBackRight, topFrontRight, bottomFrontRight]),
            StageDeckFace(kind: .frontFrameSkirt, vertices: [bottomFrontLeft, bottomFrontRight, topFrontRight, topFrontLeft]),
            StageDeckFace(kind: .leftFrameSkirt, vertices: [bottomBackLeft, bottomFrontLeft, topFrontLeft, topBackLeft]),
            StageDeckFace(kind: .topSurface, vertices: [topBackLeft, topBackRight, topFrontRight, topFrontLeft])
        ]

        let railCorners = [bottomBackLeft, bottomBackRight, bottomFrontRight, bottomFrontLeft]
        let frameRails = zip(railCorners, railCorners.dropFirst() + [railCorners[0]]).map {
            TrussVisualMember(start: $0.0, end: $0.1)
        }

        let legInset = min(0.22, max(0.12, min(size.width, size.depth) * 0.12))
        let legPositions = [
            Vector3Meters(x: position.x - halfWidth + legInset, y: bottomY, z: position.z - halfDepth + legInset),
            Vector3Meters(x: position.x + halfWidth - legInset, y: bottomY, z: position.z - halfDepth + legInset),
            Vector3Meters(x: position.x + halfWidth - legInset, y: bottomY, z: position.z + halfDepth - legInset),
            Vector3Meters(x: position.x - halfWidth + legInset, y: bottomY, z: position.z + halfDepth - legInset)
        ]
        let supportLegs = legPositions.map { top in
            StageDeckSupportLeg(
                top: top,
                bottom: Vector3Meters(x: top.x, y: groundY, z: top.z),
                radius: 0.035
            )
        }

        let crossBraces = [
            TrussVisualMember(start: supportLegs[0].bottom, end: supportLegs[1].top),
            TrussVisualMember(start: supportLegs[1].bottom, end: supportLegs[0].top),
            TrussVisualMember(start: supportLegs[3].bottom, end: supportLegs[2].top),
            TrussVisualMember(start: supportLegs[2].bottom, end: supportLegs[3].top),
            TrussVisualMember(start: supportLegs[0].bottom, end: supportLegs[3].top),
            TrussVisualMember(start: supportLegs[3].bottom, end: supportLegs[0].top),
            TrussVisualMember(start: supportLegs[1].bottom, end: supportLegs[2].top),
            TrussVisualMember(start: supportLegs[2].bottom, end: supportLegs[1].top)
        ]

        return StageDeckAssembly(
            faces: faces,
            frameRails: frameRails,
            supportLegs: supportLegs,
            crossBraces: crossBraces
        )
    }

    var trussLattice: TrussLattice {
        guard type == .trussSegment, let length else {
            return .empty
        }

        let basis = trussBasis(length: length)
        let halfWidth = 0.14
        let panelCount = max(2, Int((length / 0.5).rounded()))
        let panelLength = length / Double(panelCount)

        func point(distance: Double, crossA: Double, crossB: Double) -> Vector3Meters {
            position
                + basis.axis.scaled(by: distance)
                + basis.crossA.scaled(by: crossA * halfWidth)
                + basis.crossB.scaled(by: crossB * halfWidth)
        }

        let cornerSigns = [
            (-1.0, -1.0),
            (-1.0, 1.0),
            (1.0, -1.0),
            (1.0, 1.0)
        ]

        let chords = cornerSigns.map { crossA, crossB in
            TrussVisualMember(
                start: point(distance: 0, crossA: crossA, crossB: crossB),
                end: point(distance: length, crossA: crossA, crossB: crossB)
            )
        }

        let endCaps = [0.0, length].map { distance in
            TrussEndCap(
                members: [
                    TrussVisualMember(start: point(distance: distance, crossA: -1, crossB: -1), end: point(distance: distance, crossA: -1, crossB: 1)),
                    TrussVisualMember(start: point(distance: distance, crossA: -1, crossB: 1), end: point(distance: distance, crossA: 1, crossB: 1)),
                    TrussVisualMember(start: point(distance: distance, crossA: 1, crossB: 1), end: point(distance: distance, crossA: 1, crossB: -1)),
                    TrussVisualMember(start: point(distance: distance, crossA: 1, crossB: -1), end: point(distance: distance, crossA: -1, crossB: -1))
                ]
            )
        }

        var braces: [TrussVisualMember] = []
        for panel in 0..<panelCount {
            let startDistance = Double(panel) * panelLength
            let endDistance = Double(panel + 1) * panelLength
            let startSign = panel.isMultiple(of: 2) ? -1.0 : 1.0
            let endSign = -startSign

            braces.append(
                TrussVisualMember(
                    start: point(distance: startDistance, crossA: startSign, crossB: -1),
                    end: point(distance: endDistance, crossA: endSign, crossB: -1)
                )
            )
            braces.append(
                TrussVisualMember(
                    start: point(distance: startDistance, crossA: startSign, crossB: 1),
                    end: point(distance: endDistance, crossA: endSign, crossB: 1)
                )
            )
            braces.append(
                TrussVisualMember(
                    start: point(distance: startDistance, crossA: -1, crossB: startSign),
                    end: point(distance: endDistance, crossA: -1, crossB: endSign)
                )
            )
            braces.append(
                TrussVisualMember(
                    start: point(distance: startDistance, crossA: 1, crossB: startSign),
                    end: point(distance: endDistance, crossA: 1, crossB: endSign)
                )
            )
        }

        return TrussLattice(chords: chords, braces: braces, endCaps: endCaps)
    }

    private func trussBasis(length: Double) -> (axis: Vector3Meters, crossA: Vector3Meters, crossB: Vector3Meters) {
        if abs(rotation.z).truncatingRemainder(dividingBy: 180) == 90 {
            return (
                axis: Vector3Meters(x: 0, y: 1, z: 0),
                crossA: Vector3Meters(x: 1, y: 0, z: 0),
                crossB: Vector3Meters(x: 0, y: 0, z: 1)
            )
        } else if abs(rotation.y).truncatingRemainder(dividingBy: 180) == 90 {
            return (
                axis: Vector3Meters(x: 0, y: 0, z: 1),
                crossA: Vector3Meters(x: 1, y: 0, z: 0),
                crossB: Vector3Meters(x: 0, y: 1, z: 0)
            )
        } else {
            return (
                axis: Vector3Meters(x: 1, y: 0, z: 0),
                crossA: Vector3Meters(x: 0, y: 1, z: 0),
                crossB: Vector3Meters(x: 0, y: 0, z: 1)
            )
        }
    }
}

struct StageLayoutMetadata: Codable, Equatable {
    var createdFromPreset: String?
    var updatedAt: String
}

struct StageSummary: Codable, Equatable {
    var stageSize: StageObjectSize
    var trussPortals: [TrussPortalSummary]
    var availableLightingPositions: [String]
}

struct TrussPortalSummary: Codable, Equatable {
    var width: Double
    var height: Double
    var position: String
}

struct StageLayout: Codable, Equatable, Identifiable {
    var schemaVersion: String
    var stageLayoutId: String
    var name: String
    var units: StageUnits
    var gridSize: Double
    var objects: [StageObject]
    var metadata: StageLayoutMetadata

    var id: String { stageLayoutId }

    static let connectorSnapThreshold = 0.15

    var trussConnectorBlocks: [TrussConnectorBlock] {
        var connectorPositions: [Vector3Meters] = []

        for endpoint in objects.flatMap(\.trussEndpoints) {
            if !connectorPositions.contains(where: { $0.distance(to: endpoint) <= 0.001 }) {
                connectorPositions.append(endpoint)
            }
        }

        return connectorPositions.enumerated().map { index, position in
            TrussConnectorBlock(
                id: "truss_connector_\(index)",
                position: position,
                size: 0.34
            )
        }
    }

    static func empty(name: String) -> StageLayout {
        StageLayout(
            schemaVersion: "1.0",
            stageLayoutId: "layout_\(UUID().uuidString)",
            name: name,
            units: .meters,
            gridSize: 0.5,
            objects: [],
            metadata: StageLayoutMetadata(createdFromPreset: nil, updatedAt: Self.timestamp())
        )
    }

    static func defaultStudentOutdoor() -> StageLayout {
        // A realistic mid-size student-event stage: a 6m x 3m deck under a 6m-wide, 5m-tall portal truss.
        // Real vendor stages rig the upstage truss well above the performers, so the portal stands 5m
        // high rather than hugging the deck.
        let stageSize = StagePlatformPreset.medium6x3.stageBaseSize
        // Sit the portal truss just behind the (now deeper) deck's back edge, keeping the original 0.25m
        // stand-off so the upstage truss reads as standing behind the performers rather than on the deck.
        let upstageZ = -(stageSize.depth / 2) - 0.25
        var layout = StageLayout(
            schemaVersion: "1.0",
            stageLayoutId: "layout_student_outdoor_001",
            name: "Student Outdoor Stage",
            units: .meters,
            gridSize: 0.5,
            objects: [
                .stageBase(
                    id: "stage_base_default",
                    position: Vector3Meters(x: 0, y: 0, z: 0),
                    size: stageSize
                )
            ],
            metadata: StageLayoutMetadata(createdFromPreset: "portal_6x5", updatedAt: Self.timestamp())
        )
        layout.objects.append(contentsOf: trussPortalPreset(.portal6x5, upstageZ: upstageZ))
        return layout
    }

    static func stagePlatformPreset(_ preset: StagePlatformPreset) -> [StageObject] {
        [
            .stageBase(
                id: "\(preset.rawValue)_base",
                displayName: preset.displayName,
                position: .zero,
                size: preset.stageBaseSize
            )
        ]
    }

    static func trussPortalPreset(_ preset: StagePortalPreset, upstageZ: Double = -1.25) -> [StageObject] {
        let halfWidth = preset.width / 2
        let z = upstageZ
        var objects: [StageObject] = []

        // Tile each vertical leg from the ground to the portal's full height with stacked 2m segments,
        // capped by a 1m piece when the height is odd. This mirrors the horizontal-beam loop below and
        // handles tall portals (e.g. the 5m student-stage truss) instead of topping out at one segment.
        for side in [("left", -halfWidth), ("right", halfWidth)] {
            var currentY = 0.0
            var legIndex = 1
            while currentY < preset.height - 0.0001 {
                let remainingHeight = preset.height - currentY
                let assetId: StageAssetId = remainingHeight >= 2 ? .truss2m : .truss1m
                objects.append(
                    .trussSegment(
                        id: "\(preset.rawValue)_\(side.0)_leg_\(legIndex)",
                        assetId: assetId,
                        position: Vector3Meters(x: side.1, y: currentY, z: z),
                        rotation: Vector3Degrees(x: 0, y: 0, z: 90)
                    )
                )
                currentY += assetId.trussLength ?? 1
                legIndex += 1
            }
        }

        var currentX = -halfWidth
        var topIndex = 1
        while currentX < halfWidth - 0.0001 {
            let remainingWidth = halfWidth - currentX
            let assetId: StageAssetId = remainingWidth >= 2 ? .truss2m : .truss1m
            objects.append(
                .trussSegment(
                    id: "\(preset.rawValue)_top_\(topIndex)",
                    assetId: assetId,
                    position: Vector3Meters(x: currentX, y: preset.height, z: z),
                    rotation: .zero
                )
            )
            currentX += assetId.trussLength ?? 1
            topIndex += 1
        }

        return objects
    }

    mutating func addObject(_ object: StageObject) throws {
        guard !objects.contains(where: { $0.id == object.id }) else {
            throw StageLayoutValidationError.duplicateObjectId(object.id)
        }

        let snapped = snappedObject(object)
        try validate(snapped)
        objects.append(snapped)
        metadata.updatedAt = Self.timestamp()
    }

    mutating func updateObject(_ object: StageObject) throws {
        guard let index = objects.firstIndex(where: { $0.id == object.id }) else {
            throw StageLayoutValidationError.missingObject(object.id)
        }
        guard !objects[index].locked else {
            throw StageLayoutValidationError.lockedObject(object.id)
        }

        try validate(object)
        objects[index] = object
        metadata.updatedAt = Self.timestamp()
    }

    mutating func removeObject(id: String) throws {
        guard let index = objects.firstIndex(where: { $0.id == id }) else {
            throw StageLayoutValidationError.missingObject(id)
        }
        guard !objects[index].locked else {
            throw StageLayoutValidationError.lockedObject(id)
        }

        objects.remove(at: index)
        metadata.updatedAt = Self.timestamp()
    }

    func object(id: String?) -> StageObject? {
        guard let id else {
            return nil
        }
        return objects.first(where: { $0.id == id })
    }

    /// The connector-node snap that engages for `object` at its current position: non-nil when any of its
    /// truss endpoints sits within `connectorSnapThreshold` of another object's endpoint. Pure, so both the
    /// committed snap (`snappedObject`) and the live tabletop drag preview share the exact same rule — the
    /// dragged truss "clicks" onto a node the instant it comes within reach. Returns `nil` for non-truss
    /// objects (no connector endpoints) and when no node is in range.
    func trussNodeSnap(for object: StageObject) -> TrussNodeSnap? {
        guard object.type == .trussSegment else {
            return nil
        }

        let candidateEndpoints = object.trussEndpoints
        // Exclude the object's OWN endpoints: when re-positioning an existing truss, its stale entry
        // is still in `objects`, and snapping a small move back onto its own previous endpoint would
        // silently cancel the move. New objects (not yet in `objects`) are unaffected by the filter.
        let existingEndpoints = objects.filter { $0.id != object.id }.flatMap(\.trussEndpoints)

        for candidateEndpoint in candidateEndpoints {
            if let targetEndpoint = existingEndpoints.first(where: { $0.distance(to: candidateEndpoint) <= Self.connectorSnapThreshold }) {
                return TrussNodeSnap(
                    position: object.position + (targetEndpoint - candidateEndpoint),
                    node: targetEndpoint
                )
            }
        }

        return nil
    }

    func snappedObject(_ object: StageObject) -> StageObject {
        if let snap = trussNodeSnap(for: object) {
            var snapped = object
            snapped.position = snap.position
            return snapped
        }

        var snapped = gridSnapped(object)
        if object.type == .stageBase, let height = object.size?.height {
            snapped.position.y = height / 2
        }
        return snapped
    }

    func stageSummary() -> StageSummary {
        if let base = objects.first(where: { $0.type == .stageBase }), let size = base.size {
            let trussHeight = objects.flatMap(\.trussEndpoints).map(\.y).max() ?? 3
            return StageSummary(
                stageSize: size,
                trussPortals: [
                    TrussPortalSummary(width: size.width, height: trussHeight, position: "upstage")
                ],
                availableLightingPositions: ["frontTruss", "topTruss", "stageLeft", "stageRight"]
            )
        }

        let decks = objects.filter { $0.type == .stageDeck }
        let minX = decks.map { $0.position.x - (($0.size?.width ?? 0) / 2) }.min() ?? -2
        let maxX = decks.map { $0.position.x + (($0.size?.width ?? 0) / 2) }.max() ?? 2
        let minZ = decks.map { $0.position.z - (($0.size?.depth ?? 0) / 2) }.min() ?? -1
        let maxZ = decks.map { $0.position.z + (($0.size?.depth ?? 0) / 2) }.max() ?? 1
        let maxHeight = decks.map { $0.size?.height ?? 0.8 }.max() ?? 0.8
        let trussHeight = objects.flatMap(\.trussEndpoints).map(\.y).max() ?? 3

        return StageSummary(
            stageSize: StageObjectSize(width: maxX - minX, depth: maxZ - minZ, height: maxHeight),
            trussPortals: [
                TrussPortalSummary(width: maxX - minX, height: trussHeight, position: "upstage")
            ],
            availableLightingPositions: ["frontTruss", "topTruss", "stageLeft", "stageRight"]
        )
    }

    func validate() throws {
        guard schemaVersion == "1.0" else {
            throw StageLayoutValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard units == .meters else {
            throw StageLayoutValidationError.unsupportedUnits(units.rawValue)
        }
        guard gridSize > 0, gridSize.isFinite else {
            throw StageLayoutValidationError.invalidGridSize(gridSize)
        }

        var ids = Set<String>()
        for object in objects {
            guard ids.insert(object.id).inserted else {
                throw StageLayoutValidationError.duplicateObjectId(object.id)
            }
            try validate(object)
        }
    }

    private func validate(_ object: StageObject) throws {
        guard object.assetId.objectType == object.type else {
            throw StageLayoutValidationError.assetTypeMismatch(object.assetId.rawValue)
        }
        guard object.position.isFinite else {
            throw StageLayoutValidationError.invalidPosition(object.id)
        }
        guard object.rotation.isFinite, object.rotation.isRightAngleAligned else {
            throw StageLayoutValidationError.invalidRotation(object.id)
        }

        switch object.type {
        case .stageBase, .stageDeck:
            guard let size = object.size else {
                throw StageLayoutValidationError.missingSize(object.id)
            }
            guard size.width > 0, size.depth > 0, size.height > 0, size.width.isFinite, size.depth.isFinite, size.height.isFinite else {
                throw StageLayoutValidationError.invalidSize(object.id)
            }
            guard object.position.y - size.height / 2 >= -0.0001 else {
                throw StageLayoutValidationError.objectBelowGround(object.id)
            }
        case .trussSegment:
            guard object.length != nil else {
                throw StageLayoutValidationError.missingLength(object.id)
            }
            guard object.trussEndpoints.allSatisfy({ $0.y >= -0.0001 }) else {
                throw StageLayoutValidationError.objectBelowGround(object.id)
            }
        }
    }

    private func gridSnapped(_ object: StageObject) -> StageObject {
        var snapped = object
        snapped.position = Vector3Meters(
            x: (object.position.x / gridSize).rounded() * gridSize,
            y: (object.position.y / gridSize).rounded() * gridSize,
            z: (object.position.z / gridSize).rounded() * gridSize
        )
        return snapped
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum StageLayoutValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(String)
    case unsupportedUnits(String)
    case invalidGridSize(Double)
    case duplicateObjectId(String)
    case missingObject(String)
    case lockedObject(String)
    case assetTypeMismatch(String)
    case invalidPosition(String)
    case invalidRotation(String)
    case missingSize(String)
    case invalidSize(String)
    case missingLength(String)
    case objectBelowGround(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported stage layout version: \(version)"
        case .unsupportedUnits(let units):
            return "Unsupported stage units: \(units)"
        case .invalidGridSize(let size):
            return "Invalid stage grid size: \(size)"
        case .duplicateObjectId(let id):
            return "Duplicate stage object ID: \(id)"
        case .missingObject(let id):
            return "Stage object not found: \(id)"
        case .lockedObject(let id):
            return "Stage object is locked: \(id)"
        case .assetTypeMismatch(let assetId):
            return "Stage asset type does not match object type: \(assetId)"
        case .invalidPosition(let id):
            return "Invalid stage object position: \(id)"
        case .invalidRotation(let id):
            return "Stage object rotation must use 90-degree increments: \(id)"
        case .missingSize(let id):
            return "Stage object is missing size: \(id)"
        case .invalidSize(let id):
            return "Invalid stage object size: \(id)"
        case .missingLength(let id):
            return "Truss segment is missing length: \(id)"
        case .objectBelowGround(let id):
            return "Stage object is below ground: \(id)"
        }
    }
}

/// How the immersive scene presents: a full-immersion night-stage digital twin, or a passthrough
/// "spill onto room" mode where the virtual stage spotlights illuminate the user's real room via
/// `SpotLightComponent.SurroundingsLight` (visionOS 27). `.fullStage` is the default product.
enum StageImmersionMode: String, Codable, CaseIterable {
    case fullStage
    case roomSpill

    var displayName: String {
        switch self {
        case .fullStage: return "Full Stage"
        case .roomSpill: return "Spill onto Room"
        }
    }
}

/// Foundation-only policy for the passthrough spill mode, so the decision is testable without
/// RealityKit. The view layer reads this to gate geometry per mode.
enum SurroundingsLightPolicy {
    /// Opaque venue meshes (concrete floor, black backdrop) are shown only in full immersion; in
    /// room-spill mode they would occlude passthrough and defeat the effect.
    static func includesOpaqueVenue(in mode: StageImmersionMode) -> Bool {
        mode == .fullStage
    }
}

/// Foundation-only retry pacing for reopening an immersive space during the stage↔editor swap.
/// visionOS intermittently rejects an `openImmersiveSpace` issued while the previous space's dismiss
/// transition is still winding down (the same class of system flakiness as the documented
/// intermittently-dropped `dismissWindow`), which stranded the user on a blank window after 完成.
/// `ContentView.reconcileImmersiveScene` retries on this backoff before giving up visibly.
enum ImmersiveSceneReopenPolicy {
    /// Total open attempts (the first try + the retries the backoff below allows).
    static let maxAttempts = 4

    /// Backoff to sleep after failed attempt `attempt` (1-based) before trying again, or nil to
    /// give up. Doubles from 0.3s so the whole cycle stays under ~2.5s — long enough to outlive a
    /// dismiss transition, short enough that a genuinely broken open surfaces quickly.
    static func retryDelayNanoseconds(afterFailedAttempt attempt: Int) -> UInt64? {
        guard attempt >= 1, attempt < maxAttempts else {
            return nil
        }
        return 300_000_000 << (attempt - 1)
    }
}

/// Spatial placement for the draggable in-space AI composer attachment. Foundation-only so the
/// drag → position mapping (and its clamping) stays testable without RealityKit.
enum AIComposerPlacement {
    /// Where the composer sits when the immersive stage first opens (metres, scene space).
    static let defaultPosition = SIMD3<Float>(0, 1.45, -1.15)

    /// Keeps a dragged position within comfortable reach in front of the viewer, so the box can
    /// never be flung behind the user (z must stay negative) or so far it can't be grabbed back.
    static func clamped(_ position: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            min(max(position.x, -2.0), 2.0),
            min(max(position.y, 0.6), 2.6),
            min(max(position.z, -3.0), -0.4)
        )
    }
}
