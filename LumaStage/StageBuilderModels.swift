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
    case portal6x3 = "portal_6x3"
    case portal8x4 = "portal_8x4"

    var displayName: String {
        switch self {
        case .portal4x3:
            return "4m x 3m Portal Truss"
        case .portal6x3:
            return "6m x 3m Portal Truss"
        case .portal8x4:
            return "8m x 4m Portal Truss"
        }
    }

    var width: Double {
        switch self {
        case .portal4x3:
            return 4
        case .portal6x3:
            return 6
        case .portal8x4:
            return 8
        }
    }

    var height: Double {
        switch self {
        case .portal4x3, .portal6x3:
            return 3
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
                    size: StagePlatformPreset.small4x2.stageBaseSize
                )
            ],
            metadata: StageLayoutMetadata(createdFromPreset: "portal_4x3", updatedAt: Self.timestamp())
        )
        layout.objects.append(contentsOf: trussPortalPreset(.portal4x3))
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

    static func trussPortalPreset(_ preset: StagePortalPreset) -> [StageObject] {
        let halfWidth = preset.width / 2
        let z = -1.25
        var objects: [StageObject] = []

        for side in [("left", -halfWidth), ("right", halfWidth)] {
            objects.append(
                .trussSegment(
                    id: "\(preset.rawValue)_\(side.0)_2m",
                    assetId: .truss2m,
                    position: Vector3Meters(x: side.1, y: 0, z: z),
                    rotation: Vector3Degrees(x: 0, y: 0, z: 90)
                )
            )

            let remainingHeight = preset.height - 2
            if remainingHeight > 0 {
                objects.append(
                    .trussSegment(
                        id: "\(preset.rawValue)_\(side.0)_top_\(Int(remainingHeight))m",
                        assetId: remainingHeight == 1 ? .truss1m : .truss2m,
                        position: Vector3Meters(x: side.1, y: 2, z: z),
                        rotation: Vector3Degrees(x: 0, y: 0, z: 90)
                    )
                )
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

    func snappedObject(_ object: StageObject) -> StageObject {
        guard object.type == .trussSegment else {
            var snapped = gridSnapped(object)
            if object.type == .stageBase, let height = object.size?.height {
                snapped.position.y = height / 2
            }
            return snapped
        }

        let candidateEndpoints = object.trussEndpoints
        let existingEndpoints = objects.flatMap(\.trussEndpoints)

        for candidateEndpoint in candidateEndpoints {
            if let targetEndpoint = existingEndpoints.first(where: { $0.distance(to: candidateEndpoint) <= Self.connectorSnapThreshold }) {
                var snapped = object
                snapped.position = snapped.position + (targetEndpoint - candidateEndpoint)
                return snapped
            }
        }

        return gridSnapped(object)
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
