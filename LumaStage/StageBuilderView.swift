import SwiftUI

struct StageBuilderView: View {
    @Environment(AppModel.self) private var appModel

    @State private var selectedObjectId: String?
    @State private var activeLibraryTab: StageLibraryTab = .stage
    @State private var cameraPreset: StageCameraPreset = .isometric
    @State private var panOffset: CGSize = .zero
    @State private var panBaseOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var pinchBaseZoom: CGFloat = 1
    @State private var orbitDegrees: Double = 0
    @State private var undoStack: [StageLayout] = []
    @State private var redoStack: [StageLayout] = []

    var body: some View {
        GeometryReader { proxy in
            let panelLayout = StageBuilderPanelLayout.make(availableWidth: proxy.size.width)
            let showsInspector = StageBuilderInspectorPolicy.isVisible(selectedObjectId: selectedObjectId)

            if panelLayout.usesStackedPanels {
                VStack(spacing: CGFloat(panelLayout.spacing)) {
                    editorCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: CGFloat(panelLayout.spacing)) {
                        assetLibraryPanel(usesScroll: panelLayout.usesScrollableLibraryPanel)
                            .frame(width: CGFloat(panelLayout.libraryWidth))

                        if showsInspector {
                            ScrollView {
                                inspector
                            }
                            .frame(width: CGFloat(panelLayout.inspectorWidth))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: min(320, max(240, proxy.size.height * 0.38)))
                }
            } else {
                HStack(spacing: CGFloat(panelLayout.spacing)) {
                    assetLibraryPanel(usesScroll: panelLayout.usesScrollableLibraryPanel)
                        .frame(width: CGFloat(panelLayout.libraryWidth))

                    editorCanvas
                        .frame(minWidth: CGFloat(panelLayout.minimumViewportWidth), maxWidth: .infinity, maxHeight: .infinity)

                    if showsInspector {
                        inspector
                            .frame(width: CGFloat(panelLayout.inspectorWidth))
                    }
                }
            }
        }
        .foregroundStyle(LumaStageDesign.textPrimary)
    }

    private var editorCanvas: some View {
        VStack(spacing: 12) {
            toolbar
            stageViewport
        }
    }

    private var stageViewport: some View {
        StageBuilderViewport(
            layout: appModel.stageLayout,
            selectedObjectId: $selectedObjectId,
            cameraPreset: cameraPreset,
            panOffset: panOffset,
            zoom: zoom,
            orbitDegrees: orbitDegrees,
            onDropLibraryItem: dropLibraryItem
        )
        .clipShape(RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius)
                .stroke(LumaStageDesign.hairline, lineWidth: 1)
        }
        .simultaneousGesture(panGesture)
        .simultaneousGesture(pinchZoomGesture)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = CGSize(
                    width: panBaseOffset.width + value.translation.width,
                    height: panBaseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                panBaseOffset = panOffset
            }
    }

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                zoom = clampedZoom(pinchBaseZoom * scale)
            }
            .onEnded { scale in
                zoom = clampedZoom(pinchBaseZoom * scale)
                pinchBaseZoom = zoom
            }
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    undoLayoutChange()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .lumaGlassButton()
                .disabled(undoStack.isEmpty)
                .help("Undo")

                Button {
                    redoLayoutChange()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .lumaGlassButton()
                .disabled(redoStack.isEmpty)
                .help("Redo")

                cameraPicker

                HStack(spacing: 8) {
                    Image(systemName: "rotate.3d")
                        .foregroundStyle(LumaStageDesign.textSecondary)

                    Slider(value: $orbitDegrees, in: -90...90, step: 15)
                        .tint(LumaStageDesign.coolBlue)
                }
                .frame(width: 140)

                Button {
                    panOffset = .zero
                    panBaseOffset = .zero
                    zoom = 1
                    pinchBaseZoom = 1
                    orbitDegrees = 0
                    cameraPreset = .isometric
                } label: {
                    Image(systemName: "viewfinder")
                }
                .lumaGlassButton()
                .help("Reset View")
            }
        }
        .lumaPanel(padding: 12, tint: LumaStageDesign.nightBlack.opacity(0.20))
    }

    @ViewBuilder
    private var cameraPicker: some View {
        switch StageBuilderToolbarLayout.cameraPickerPresentation {
        case .menu:
            Picker("View: \(cameraPreset.displayName)", selection: $cameraPreset) {
                cameraPickerOptions
            }
            .pickerStyle(.menu)
            .frame(width: 132)
        case .segmented:
            Picker("View", selection: $cameraPreset) {
                cameraPickerOptions
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
        }
    }

    @ViewBuilder
    private var cameraPickerOptions: some View {
        ForEach(StageCameraPreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
        }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        CGFloat(StageBuilderZoom.clamped(Double(value)))
    }

    @ViewBuilder
    private func assetLibraryPanel(usesScroll: Bool) -> some View {
        if usesScroll {
            assetLibrary
        } else {
            assetLibraryContent
                .lumaPanel(tint: LumaStageDesign.nightBlack.opacity(0.20))
        }
    }

    private var assetLibrary: some View {
        ScrollView {
            assetLibraryContent
        }
        .scrollIndicators(.visible)
        .lumaPanel(tint: LumaStageDesign.nightBlack.opacity(0.20))
    }

    private var assetLibraryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaSectionHeader(
                title: "Stage Builder",
                subtitle: "Assemble an outdoor student stage with 3D blocks",
                systemImage: "shippingbox"
            )

            Picker("Library", selection: $activeLibraryTab) {
                ForEach(StageLibraryTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch activeLibraryTab {
            case .stage:
                ForEach(StageBuilderStageLibraryAssets.stageTab, id: \.rawValue) { assetId in
                    libraryAssetCard(assetId, tint: LumaStageDesign.magenta) {
                        addAsset(assetId)
                    }
                }

                Divider()
                    .overlay(LumaStageDesign.hairline)

                ForEach(StagePlatformPreset.allCases, id: \.rawValue) { preset in
                    libraryPlatformPresetCard(preset) {
                        addStagePreset(preset)
                    }
                }
            case .truss:
                libraryAssetCard(.truss1m, tint: LumaStageDesign.warmAmber) {
                    addAsset(.truss1m)
                }
                libraryAssetCard(.truss2m, tint: LumaStageDesign.warmAmber) {
                    addAsset(.truss2m)
                }
            case .presets:
                ForEach(StagePortalPreset.allCases, id: \.rawValue) { preset in
                    libraryPortalPresetCard(preset) {
                        addPortalPreset(preset)
                    }
                }

                Divider()
                    .overlay(LumaStageDesign.hairline)

                Button {
                    commitLayout(.defaultStudentOutdoor())
                    selectedObjectId = nil
                } label: {
                    Label("Reset Default Layout", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .lumaGlassButton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaSectionHeader(
                title: "Inspector",
                subtitle: selectedObject?.displayName ?? "Select an object in the editor",
                systemImage: "slider.horizontal.3"
            )

            if let selectedObject {
                LumaMetricRow(title: "Type", value: objectTypeLabel(selectedObject.type), tint: LumaStageDesign.coolBlue)
                LumaMetricRow(title: "Asset", value: selectedObject.assetId.displayName, tint: LumaStageDesign.textPrimary)
                LumaMetricRow(title: "X Position", value: meters(selectedObject.position.x), tint: LumaStageDesign.textPrimary)
                LumaMetricRow(title: "Y Position", value: meters(selectedObject.position.y), tint: LumaStageDesign.textPrimary)
                LumaMetricRow(title: "Z Position", value: meters(selectedObject.position.z), tint: LumaStageDesign.textPrimary)
                LumaMetricRow(title: "Z Rotation", value: degrees(selectedObject.rotation.z), tint: LumaStageDesign.textPrimary)

                Divider()
                    .overlay(LumaStageDesign.hairline)

                if selectedObject.type == .stageBase {
                    stageBaseSizeControls(selectedObject)

                    Divider()
                        .overlay(LumaStageDesign.hairline)
                }

                transformPad
                if selectedObject.type != .stageBase {
                    rotationControls
                }

                HStack {
                    Button {
                        duplicateSelectedObject()
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .lumaGlassButton()
                    .help("Duplicate")

                    Button(role: .destructive) {
                        deleteSelectedObject()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .lumaGlassButton(tint: .red.opacity(0.35))
                    .help("Delete")

                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    LumaStatusChip(title: "Grid Snap 0.5m", tint: LumaStageDesign.coolBlue)
                    LumaStatusChip(title: "Connector Snap 0.15m", tint: LumaStageDesign.warmAmber)

                    Text("Add a stage base, truss segment, or portal preset, then select objects in the editor to move and rotate them.")
                        .font(.caption)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .lumaPanel(tint: LumaStageDesign.nightBlack.opacity(0.20))
    }

    private var transformPad: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                transformButton(systemImage: "arrow.up", dx: 0, dy: 0, dz: -0.5)
                Spacer()
            }

            HStack {
                transformButton(systemImage: "arrow.left", dx: -0.5, dy: 0, dz: 0)
                transformButton(systemImage: "arrow.up.and.down", dx: 0, dy: 0.5, dz: 0)
                transformButton(systemImage: "arrow.right", dx: 0.5, dy: 0, dz: 0)
            }

            HStack {
                Spacer()
                transformButton(systemImage: "arrow.down", dx: 0, dy: 0, dz: 0.5)
                Spacer()
            }
        }
    }

    private var rotationControls: some View {
        HStack {
            Button {
                rotateSelected(axis: .x)
            } label: {
                Text("X 90")
                    .font(.caption.weight(.semibold))
            }
            .lumaGlassButton()

            Button {
                rotateSelected(axis: .y)
            } label: {
                Text("Y 90")
                    .font(.caption.weight(.semibold))
            }
            .lumaGlassButton()

            Button {
                rotateSelected(axis: .z)
            } label: {
                Text("Z 90")
                    .font(.caption.weight(.semibold))
            }
            .lumaGlassButton()
        }
    }

    private var selectedObject: StageObject? {
        appModel.stageLayout.object(id: selectedObjectId)
    }

    private func libraryAssetCard(_ assetId: StageAssetId, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LibraryPreviewCard(
                title: assetId.displayName,
                caption: assetCaption(assetId),
                tint: tint
            ) {
                StageAssetPreview(assetId: assetId, tint: tint)
            }
        }
        .buttonStyle(.plain)
        .draggable(libraryPayload(assetId)) {
            StageAssetPreview(assetId: assetId, tint: tint)
                .frame(width: 120, height: 84)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func libraryPlatformPresetCard(_ preset: StagePlatformPreset, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LibraryPreviewCard(
                title: preset.displayName,
                caption: "Drag a stage size",
                tint: LumaStageDesign.coolBlue
            ) {
                StagePlatformPresetPreview(preset: preset)
            }
        }
        .buttonStyle(.plain)
        .draggable(libraryPayload(preset)) {
            StagePlatformPresetPreview(preset: preset)
                .frame(width: 120, height: 84)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func libraryPortalPresetCard(_ preset: StagePortalPreset, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LibraryPreviewCard(
                title: preset.displayName,
                caption: "Drag a portal truss",
                tint: LumaStageDesign.magenta
            ) {
                StagePortalPresetPreview(preset: preset)
            }
        }
        .buttonStyle(.plain)
        .draggable(libraryPayload(preset)) {
            StagePortalPresetPreview(preset: preset)
                .frame(width: 120, height: 84)
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func libraryButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
        .lumaGlassButton(tint: tint.opacity(0.18))
        .tint(tint)
    }

    private func assetCaption(_ assetId: StageAssetId) -> String {
        switch assetId {
        case .stageBase:
            return "Solid base"
        case .stageDeck1x1, .stageDeck2x1, .stageDeck2x2:
            return "Stage block"
        case .truss1m, .truss2m:
            return "Box truss"
        }
    }

    private func transformButton(systemImage: String, dx: Double, dy: Double, dz: Double) -> some View {
        Button {
            moveSelected(dx: dx, dy: dy, dz: dz)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 30, height: 24)
        }
        .lumaGlassButton()
    }

    private func addAsset(_ assetId: StageAssetId, dropPosition: Vector3Meters? = nil) {
        var layout = appModel.stageLayout
        let id = "\(assetId.rawValue)_\(shortId())"
        guard let object = StageBuilderDropPlanner.object(
            assetId: assetId,
            id: id,
            existingObjects: layout.objects,
            dropPosition: dropPosition
        ) else {
            selectedObjectId = nil
            return
        }

        do {
            try layout.addObject(object)
            commitLayout(layout)
            selectedObjectId = object.id
        } catch {
            selectedObjectId = nil
        }
    }

    private func dropLibraryItem(_ payload: String, location: CGPoint, viewportSize: CGSize) -> Bool {
        if let assetId = parseAssetPayload(payload) {
            addAsset(assetId, dropPosition: stageDropPosition(from: location, in: viewportSize))
            return true
        }

        if let preset = parsePlatformPayload(payload) {
            addStagePreset(preset)
            return true
        }

        if let preset = parsePortalPayload(payload) {
            addPortalPreset(preset)
            return true
        }

        return false
    }

    private func stageDropPosition(from location: CGPoint, in size: CGSize) -> Vector3Meters {
        let scale = Double(min(size.width / 9.5, size.height / 6.5) * zoom)
        guard scale > 0 else {
            return .zero
        }

        let screenX = Double(location.x - size.width / 2 - panOffset.width)
        let screenY = Double(location.y - size.height * 0.62 - panOffset.height)
        let projected: Vector3Meters

        switch cameraPreset {
        case .front:
            projected = Vector3Meters(x: screenX / scale, y: 0, z: -1.25)
        case .top:
            projected = Vector3Meters(x: screenX / scale, y: 0, z: screenY / scale)
        case .left:
            projected = Vector3Meters(x: 0, y: 0, z: screenX / scale)
        case .right:
            projected = Vector3Meters(x: 0, y: 0, z: -screenX / scale)
        case .isometric:
            let difference = screenX / (scale * 0.74)
            let sum = screenY / (scale * 0.30)
            projected = Vector3Meters(x: (sum + difference) / 2, y: 0, z: (sum - difference) / 2)
        }

        let radians = orbitDegrees * Double.pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return Vector3Meters(
            x: projected.x * cosine + projected.z * sine,
            y: 0,
            z: -projected.x * sine + projected.z * cosine
        )
    }

    private func addStagePreset(_ preset: StagePlatformPreset) {
        var layout = appModel.stageLayout
        let suffix = shortId()

        do {
            layout.objects.removeAll { object in
                object.type == .stageBase || object.type == .stageDeck
            }
            var selectedBaseId: String?
            for original in StageLayout.stagePlatformPreset(preset) {
                var object = original
                object.id = "\(original.id)_\(suffix)"
                try layout.addObject(object)
                if object.type == .stageBase {
                    selectedBaseId = object.id
                }
            }
            layout.metadata.createdFromPreset = preset.rawValue
            commitLayout(layout)
            selectedObjectId = selectedBaseId
        } catch {
            selectedObjectId = nil
        }
    }

    private func addPortalPreset(_ preset: StagePortalPreset) {
        var layout = appModel.stageLayout
        let suffix = shortId()

        do {
            for original in StageLayout.trussPortalPreset(preset) {
                var object = original
                object.id = "\(original.id)_\(suffix)"
                object.connectorIds = ["\(object.id)_a", "\(object.id)_b"]
                try layout.addObject(object)
            }
            layout.metadata.createdFromPreset = preset.rawValue
            commitLayout(layout)
        } catch {
            selectedObjectId = nil
        }
    }

    private func moveSelected(dx: Double, dy: Double, dz: Double) {
        mutateSelectedObject { object in
            object.position = Vector3Meters(
                x: object.position.x + dx,
                y: object.type == .stageBase ? (object.size?.height ?? 0.8) / 2 : max(0, object.position.y + dy),
                z: object.position.z + dz
            )
        }
    }

    private func stageBaseSizeControls(_ object: StageObject) -> some View {
        let size = object.size ?? StageObjectSize(width: 4, depth: 2, height: 0.8)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Stage Base")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LumaStageDesign.textSecondary)

            stageSizeStepper(title: "W", value: size.width, range: 1...16) { newValue in
                resizeSelectedStageBase(width: newValue)
            }

            stageSizeStepper(title: "D", value: size.depth, range: 1...12) { newValue in
                resizeSelectedStageBase(depth: newValue)
            }

            stageSizeStepper(title: "H", value: size.height, range: 0.2...2.4) { newValue in
                resizeSelectedStageBase(height: newValue)
            }
        }
    }

    private func stageSizeStepper(title: String, value: Double, range: ClosedRange<Double>, action: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(
            get: { value },
            set: { action(min(max($0, range.lowerBound), range.upperBound)) }
        ), in: range, step: 0.5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .frame(width: 18, alignment: .leading)

                Text(meters(value))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)

                Spacer()
            }
        }
    }

    private func resizeSelectedStageBase(width: Double? = nil, depth: Double? = nil, height: Double? = nil) {
        mutateSelectedObject { object in
            guard object.type == .stageBase else {
                return
            }

            let currentSize = object.size ?? StageObjectSize(width: 4, depth: 2, height: 0.8)
            let nextSize = StageObjectSize(
                width: width ?? currentSize.width,
                depth: depth ?? currentSize.depth,
                height: height ?? currentSize.height
            )
            object.size = nextSize
            object.position.y = nextSize.height / 2
        }
    }

    private func rotateSelected(axis: TransformAxis) {
        mutateSelectedObject { object in
            switch axis {
            case .x:
                object.rotation.x += 90
            case .y:
                object.rotation.y += 90
            case .z:
                object.rotation.z += 90
            }
        }
    }

    private func duplicateSelectedObject() {
        guard var object = selectedObject else {
            return
        }

        var layout = appModel.stageLayout
        object.id = "\(object.assetId.rawValue)_\(shortId())"
        object.connectorIds = object.type == .trussSegment ? ["\(object.id)_a", "\(object.id)_b"] : []
        object.position.x += layout.gridSize
        object.position.z += layout.gridSize

        do {
            try layout.addObject(object)
            commitLayout(layout)
            selectedObjectId = object.id
        } catch {
            selectedObjectId = nil
        }
    }

    private func deleteSelectedObject() {
        guard let selectedObjectId else {
            return
        }

        var layout = appModel.stageLayout
        do {
            try layout.removeObject(id: selectedObjectId)
            commitLayout(layout)
            self.selectedObjectId = nil
        } catch {
            self.selectedObjectId = nil
        }
    }

    private func mutateSelectedObject(_ mutation: (inout StageObject) -> Void) {
        guard var object = selectedObject else {
            return
        }

        var layout = appModel.stageLayout
        mutation(&object)

        do {
            try layout.updateObject(object)
            commitLayout(layout)
            selectedObjectId = object.id
        } catch {
            selectedObjectId = nil
        }
    }

    private func commitLayout(_ layout: StageLayout) {
        undoStack.append(appModel.stageLayout)
        redoStack.removeAll()
        appModel.saveStageLayout(layout)
    }

    private func undoLayoutChange() {
        guard let previous = undoStack.popLast() else {
            return
        }

        redoStack.append(appModel.stageLayout)
        appModel.saveStageLayout(previous)
        if previous.object(id: selectedObjectId) == nil {
            selectedObjectId = nil
        }
    }

    private func redoLayoutChange() {
        guard let next = redoStack.popLast() else {
            return
        }

        undoStack.append(appModel.stageLayout)
        appModel.saveStageLayout(next)
        if next.object(id: selectedObjectId) == nil {
            selectedObjectId = nil
        }
    }

    private func meters(_ value: Double) -> String {
        String(format: "%.1fm", value)
    }

    private func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    private func objectTypeLabel(_ type: StageObjectType) -> String {
        switch type {
        case .stageBase:
            return "Stage Base"
        case .stageDeck:
            return "Stage Deck"
        case .trussSegment:
            return "Truss Segment"
        }
    }

    private func shortId() -> String {
        String(UUID().uuidString.prefix(6)).lowercased()
    }

    private func libraryPayload(_ assetId: StageAssetId) -> String {
        "asset:\(assetId.rawValue)"
    }

    private func libraryPayload(_ preset: StagePlatformPreset) -> String {
        "platform:\(preset.rawValue)"
    }

    private func libraryPayload(_ preset: StagePortalPreset) -> String {
        "portal:\(preset.rawValue)"
    }

    private func parseAssetPayload(_ payload: String) -> StageAssetId? {
        guard payload.hasPrefix("asset:") else {
            return nil
        }

        return StageAssetId(rawValue: String(payload.dropFirst("asset:".count)))
    }

    private func parsePlatformPayload(_ payload: String) -> StagePlatformPreset? {
        guard payload.hasPrefix("platform:") else {
            return nil
        }

        return StagePlatformPreset(rawValue: String(payload.dropFirst("platform:".count)))
    }

    private func parsePortalPayload(_ payload: String) -> StagePortalPreset? {
        guard payload.hasPrefix("portal:") else {
            return nil
        }

        return StagePortalPreset(rawValue: String(payload.dropFirst("portal:".count)))
    }
}

private struct LibraryPreviewCard<Preview: View>: View {
    let title: String
    let caption: String
    let tint: Color
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        HStack(spacing: 10) {
            preview()
                .frame(width: 72, height: 54)
                .background(LumaStageDesign.nightBlack.opacity(0.42), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .lumaNativeGlass(tint: tint.opacity(0.13), radius: LumaStageDesign.cornerRadius, interactive: true, fallbackOpacity: 0.32)
        .overlay {
            RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.26), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius, style: .continuous))
    }
}

private struct StageAssetPreview: View {
    let assetId: StageAssetId
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch assetId {
                case .stageBase:
                    stageBase(in: proxy.size)
                case .stageDeck1x1, .stageDeck2x1, .stageDeck2x2:
                    deck(in: proxy.size)
                case .truss1m, .truss2m:
                    truss(in: proxy.size)
                }
            }
        }
    }

    private func stageBase(in size: CGSize) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.34))
                path.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.24))
                path.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.48))
                path.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.62))
                path.closeSubpath()
            }
            .fill(Color(red: 0.64, green: 0.04, blue: 0.06))

            Path { path in
                path.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.62))
                path.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.48))
                path.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.66))
                path.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.82))
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.86))
        }
    }

    private func deck(in size: CGSize) -> some View {
        let deckWidth: CGFloat = assetId == .stageDeck1x1 ? 0.42 : 0.68
        let deckDepth: CGFloat = assetId == .stageDeck2x1 ? 0.32 : 0.48
        let left = size.width * (0.52 - deckWidth / 2)
        let right = size.width * (0.52 + deckWidth / 2)
        let backLeft = CGPoint(x: left + size.width * 0.10, y: size.height * 0.30)
        let backRight = CGPoint(x: right + size.width * 0.04, y: size.height * 0.38)
        let frontRight = CGPoint(x: right - size.width * 0.08, y: size.height * (0.38 + deckDepth))
        let frontLeft = CGPoint(x: left - size.width * 0.08, y: size.height * (0.30 + deckDepth))
        let skirtDrop = max(5, size.height * 0.12)
        let legTopY = max(frontLeft.y, frontRight.y) + skirtDrop * 0.28
        let legBottomY = min(size.height * 0.86, legTopY + size.height * 0.22)

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: frontLeft.x + size.width * 0.08, y: legBottomY))
                path.addLine(to: CGPoint(x: backLeft.x + size.width * 0.08, y: legTopY))
                path.move(to: CGPoint(x: frontRight.x - size.width * 0.08, y: legBottomY))
                path.addLine(to: CGPoint(x: backRight.x - size.width * 0.08, y: legTopY))
                path.move(to: CGPoint(x: backLeft.x + size.width * 0.08, y: legBottomY))
                path.addLine(to: CGPoint(x: frontLeft.x + size.width * 0.08, y: legTopY))
                path.move(to: CGPoint(x: backRight.x - size.width * 0.08, y: legBottomY))
                path.addLine(to: CGPoint(x: frontRight.x - size.width * 0.08, y: legTopY))
            }
            .stroke(Color(red: 0.68, green: 0.70, blue: 0.70), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: backLeft.x + size.width * 0.08, y: legTopY))
                path.addLine(to: CGPoint(x: backLeft.x + size.width * 0.08, y: legBottomY))
                path.move(to: CGPoint(x: backRight.x - size.width * 0.08, y: legTopY))
                path.addLine(to: CGPoint(x: backRight.x - size.width * 0.08, y: legBottomY))
                path.move(to: CGPoint(x: frontRight.x - size.width * 0.08, y: legTopY))
                path.addLine(to: CGPoint(x: frontRight.x - size.width * 0.08, y: legBottomY))
                path.move(to: CGPoint(x: frontLeft.x + size.width * 0.08, y: legTopY))
                path.addLine(to: CGPoint(x: frontLeft.x + size.width * 0.08, y: legBottomY))
            }
            .stroke(Color(red: 0.78, green: 0.80, blue: 0.80), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            Path { path in
                path.move(to: frontLeft)
                path.addLine(to: frontRight)
                path.addLine(to: CGPoint(x: frontRight.x, y: frontRight.y + skirtDrop))
                path.addLine(to: CGPoint(x: frontLeft.x, y: frontLeft.y + skirtDrop))
                path.closeSubpath()
            }
            .fill(Color(red: 0.42, green: 0.44, blue: 0.44))

            Path { path in
                path.move(to: backLeft)
                path.addLine(to: backRight)
                path.addLine(to: frontRight)
                path.addLine(to: frontLeft)
                path.closeSubpath()
            }
            .fill(Color(red: 0.11, green: 0.12, blue: 0.12))
            .overlay {
                Path { path in
                    path.move(to: backLeft)
                    path.addLine(to: backRight)
                    path.addLine(to: frontRight)
                    path.addLine(to: frontLeft)
                    path.closeSubpath()
                    path.move(to: CGPoint(x: (backLeft.x + frontLeft.x) / 2, y: (backLeft.y + frontLeft.y) / 2))
                    path.addLine(to: CGPoint(x: (backRight.x + frontRight.x) / 2, y: (backRight.y + frontRight.y) / 2))
                    path.move(to: CGPoint(x: (backLeft.x + backRight.x) / 2, y: (backLeft.y + backRight.y) / 2))
                    path.addLine(to: CGPoint(x: (frontLeft.x + frontRight.x) / 2, y: (frontLeft.y + frontRight.y) / 2))
                }
                .stroke(tint.opacity(0.72), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func truss(in size: CGSize) -> some View {
        Path { path in
            let left = size.width * 0.16
            let right = size.width * 0.86
            let top = size.height * 0.34
            let bottom = size.height * 0.66
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: right, y: bottom))

            let panels = assetId == .truss1m ? 3 : 5
            for panel in 0..<panels {
                let x0 = left + (right - left) * CGFloat(panel) / CGFloat(panels)
                let x1 = left + (right - left) * CGFloat(panel + 1) / CGFloat(panels)
                if panel.isMultiple(of: 2) {
                    path.move(to: CGPoint(x: x0, y: bottom))
                    path.addLine(to: CGPoint(x: x1, y: top))
                } else {
                    path.move(to: CGPoint(x: x0, y: top))
                    path.addLine(to: CGPoint(x: x1, y: bottom))
                }
            }
        }
        .stroke(tint.opacity(0.92), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
}

private struct StagePlatformPresetPreview: View {
    let preset: StagePlatformPreset

    var body: some View {
        GeometryReader { proxy in
            let columns = preset == .large8x4 ? 4 : preset == .medium6x3 ? 3 : 2
            let rows = preset == .small4x2 ? 1 : 2
            VStack(spacing: 3) {
                ForEach(0..<rows, id: \.self) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<columns, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.22, green: 0.24, blue: 0.25))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(LumaStageDesign.coolBlue.opacity(0.65), lineWidth: 1)
                                }
                        }
                    }
                }
            }
            .padding(proxy.size.width * 0.14)
        }
    }
}

private struct StagePortalPresetPreview: View {
    let preset: StagePortalPreset

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let left = proxy.size.width * 0.18
                let right = proxy.size.width * 0.84
                let top = proxy.size.height * 0.18
                let bottom = proxy.size.height * 0.80
                path.move(to: CGPoint(x: left, y: bottom))
                path.addLine(to: CGPoint(x: left, y: top))
                path.addLine(to: CGPoint(x: right, y: top))
                path.addLine(to: CGPoint(x: right, y: bottom))
                for index in 0..<8 {
                    let t0 = CGFloat(index) / 8
                    let t1 = CGFloat(index + 1) / 8
                    path.move(to: CGPoint(x: left + (right - left) * t0, y: top + 8))
                    path.addLine(to: CGPoint(x: left + (right - left) * t1, y: top - 8))
                }
            }
            .stroke(LumaStageDesign.magenta.opacity(0.86), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct StageBuilderViewport: View {
    let layout: StageLayout
    @Binding var selectedObjectId: String?
    let cameraPreset: StageCameraPreset
    let panOffset: CGSize
    let zoom: CGFloat
    let orbitDegrees: Double
    let onDropLibraryItem: (String, CGPoint, CGSize) -> Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                viewportBackground
                groundPlane(in: proxy.size)

                ForEach(trussConnectorBlocks(in: .behindStageBase)) { block in
                    connectorBlockLayer(block, in: proxy.size)
                }

                ForEach(StageBuilderRenderOrder.objectsForIsometricViewport(layout.objects)) { object in
                    objectLayer(object, in: proxy.size)
                        .allowsHitTesting(StageBuilderObjectLayerHitTesting.allowsDirectLayerTap(for: object.type))
                }

                ForEach(trussConnectorBlocks(in: .scene)) { block in
                    connectorBlockLayer(block, in: proxy.size)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(viewportTapGesture(in: proxy.size))
            .dropDestination(for: String.self) { items, location in
                guard let payload = items.first else {
                    return false
                }

                return onDropLibraryItem(payload, location, proxy.size)
            } isTargeted: { _ in }
        }
    }

    private func trussConnectorBlocks(in layer: StageBuilderRenderLayer) -> [TrussConnectorBlock] {
        let stageBase = layout.objects.first(where: { $0.type == .stageBase })
        return layout.trussConnectorBlocks.filter { block in
            StageBuilderRenderOrder.connectorLayer(position: block.position, stageBase: stageBase) == layer
                && StageBuilderRenderOrder.shouldRenderConnectorBlock(block, stageBase: stageBase)
        }
    }

    private func viewportTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                selectedObjectId = StageBuilderSelectionPolicy.selectedObjectIdAfterViewportTap(
                    currentSelectionId: selectedObjectId,
                    hitObjectId: objectId(at: value.location, in: size)
                )
            }
    }

    private var viewportBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.039, blue: 0.047),
                Color(red: 0.070, green: 0.076, blue: 0.088)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func groundPlane(in size: CGSize) -> some View {
        let lines = StageBuilderViewportGround.referenceLines()
        return ZStack {
            groundPlaneShape(in: size)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.105, green: 0.118, blue: 0.132).opacity(0.34),
                            Color(red: 0.035, green: 0.041, blue: 0.050).opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    groundPlaneShape(in: size)
                        .stroke(Color.white.opacity(0.045), lineWidth: 1)
                }

            groundLinePath(lines.filter { !$0.isMajor }, in: size)
                .stroke(Color.white.opacity(0.055), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            groundLinePath(lines.filter(\.isMajor), in: size)
                .stroke(LumaStageDesign.coolBlue.opacity(0.16), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

            groundAxisPath(in: size)
                .stroke(LumaStageDesign.warmAmber.opacity(0.18), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        .allowsHitTesting(false)
    }

    private func groundPlaneShape(in size: CGSize) -> Path {
        Path { path in
            let extent = StageBuilderViewportGround.extent
            let corners = [
                Vector3Meters(x: -extent, y: 0, z: -extent),
                Vector3Meters(x: extent, y: 0, z: -extent),
                Vector3Meters(x: extent, y: 0, z: extent),
                Vector3Meters(x: -extent, y: 0, z: extent)
            ].map { project($0, in: size) }

            guard let first = corners.first else {
                return
            }

            path.move(to: first)
            for corner in corners.dropFirst() {
                path.addLine(to: corner)
            }
            path.closeSubpath()
        }
    }

    private func groundLinePath(_ lines: [StageBuilderGroundLine], in size: CGSize) -> Path {
        Path { path in
            for line in lines {
                path.move(to: project(line.start, in: size))
                path.addLine(to: project(line.end, in: size))
            }
        }
    }

    private func groundAxisPath(in size: CGSize) -> Path {
        let extent = StageBuilderViewportGround.extent
        return groundLinePath(
            [
                StageBuilderGroundLine(
                    start: Vector3Meters(x: -extent, y: 0, z: 0),
                    end: Vector3Meters(x: extent, y: 0, z: 0),
                    isMajor: true
                ),
                StageBuilderGroundLine(
                    start: Vector3Meters(x: 0, y: 0, z: -extent),
                    end: Vector3Meters(x: 0, y: 0, z: extent),
                    isMajor: true
                )
            ],
            in: size
        )
    }

    private func objectId(at location: CGPoint, in size: CGSize) -> String? {
        layout.objects.reversed().first { object in
            objectHitFrame(object, in: size).contains(location)
        }?.id
    }

    private func objectHitFrame(_ object: StageObject, in size: CGSize) -> CGRect {
        switch object.type {
        case .stageBase:
            let solid = object.stageBaseSolid ?? StageObject.stageBase(id: object.id, position: object.position).stageBaseSolid!
            return bounds(for: solid.vertices.map { project($0, in: size) }, padding: 12)
        case .stageDeck:
            let point = project(object.position, in: size)
            let objectSize = object.size ?? StageObjectSize(width: 1, depth: 1, height: 0.8)
            let scale = projectionScale(in: size)
            let width = max(54, CGFloat(objectSize.width) * scale)
            let height = max(42, CGFloat(objectSize.depth) * scale * cameraPreset.deckDepthScale)
            return CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height).insetBy(dx: -10, dy: -10)
        case .trussSegment:
            let points = object.trussLattice.allMembers.flatMap { member in
                [project(member.start, in: size), project(member.end, in: size)]
            }
            return bounds(for: points, padding: 16)
        }
    }

    private func bounds(for points: [CGPoint], padding: CGFloat) -> CGRect {
        guard let first = points.first else {
            return .null
        }

        let rawBounds = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
        return rawBounds.insetBy(dx: -padding, dy: -padding)
    }

    @ViewBuilder
    private func objectLayer(_ object: StageObject, in size: CGSize) -> some View {
        switch object.type {
        case .stageBase:
            stageBaseLayer(object, in: size)
        case .stageDeck:
            deckLayer(object, in: size)
        case .trussSegment:
            trussLayer(object, in: size)
        }
    }

    private func stageBaseLayer(_ object: StageObject, in size: CGSize) -> some View {
        let solid = object.stageBaseSolid ?? StageObject.stageBase(id: object.id, position: object.position).stageBaseSolid!
        let selected = object.id == selectedObjectId
        let topFace = solid.faces.first(where: { $0.kind == .top })

        return ZStack {
            ForEach(Array(stageBaseRenderFaces(solid).enumerated()), id: \.offset) { _, face in
                stageBaseFacePath(face, in: size)
                    .fill(stageBaseFaceColor(face.kind))
            }

            if let topFace {
                stageBaseFacePath(topFace, in: size)
                    .stroke(selected ? LumaStageDesign.coolBlue : Color.white.opacity(0.18), lineWidth: selected ? 3 : 1)
            }

            if let frontFace = solid.faces.first(where: { $0.kind == .front }) {
                let projected = frontFace.vertices.map { project($0, in: size) }
                if projected.count >= 2 {
                    Path { path in
                        path.move(to: projected[2])
                        path.addLine(to: projected[3])
                    }
                    .stroke(Color.black.opacity(0.56), lineWidth: 4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedObjectId = object.id
        }
    }

    private func stageBaseRenderFaces(_ solid: StageBaseSolid) -> [StageBaseFace] {
        [.back, .left, .right, .front, .top].compactMap { kind in
            solid.faces.first(where: { $0.kind == kind })
        }
    }

    private func stageBaseFacePath(_ face: StageBaseFace, in size: CGSize) -> Path {
        Path { path in
            guard let firstVertex = face.vertices.first else {
                return
            }

            path.move(to: project(firstVertex, in: size))
            for vertex in face.vertices.dropFirst() {
                path.addLine(to: project(vertex, in: size))
            }
            path.closeSubpath()
        }
    }

    private func stageBaseFaceColor(_ kind: StageBaseFaceKind) -> Color {
        switch kind {
        case .top:
            return Color(red: 0.65, green: 0.04, blue: 0.06)
        case .front:
            return Color.black.opacity(0.90)
        case .right, .left:
            return Color.black.opacity(0.78)
        case .back:
            return Color.black.opacity(0.68)
        case .bottom:
            return Color.black.opacity(0.92)
        }
    }

    private func deckLayer(_ object: StageObject, in size: CGSize) -> some View {
        let assembly = object.stageDeckAssembly ?? StageObject.stageDeck(
            id: object.id,
            assetId: object.assetId,
            position: object.position
        ).stageDeckAssembly!
        let selected = object.id == selectedObjectId
        let scale = projectionScale(in: size)
        let topFace = assembly.faces.first(where: { $0.kind == .topSurface })

        return ZStack {
            trussMemberPath(assembly.crossBraces, in: size)
                .stroke(Color(red: 0.58, green: 0.60, blue: 0.61).opacity(0.78), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            ForEach(Array(assembly.supportLegs.enumerated()), id: \.offset) { _, leg in
                Path { path in
                    path.move(to: project(leg.bottom, in: size))
                    path.addLine(to: project(leg.top, in: size))
                }
                .stroke(
                    Color(red: 0.72, green: 0.73, blue: 0.72),
                    style: StrokeStyle(lineWidth: max(3, CGFloat(leg.radius) * scale * 1.8), lineCap: .round)
                )
            }

            ForEach(Array(stageDeckRenderFaces(assembly).enumerated()), id: \.offset) { _, face in
                stageDeckFacePath(face, in: size)
                    .fill(stageDeckFaceColor(face.kind))
            }

            trussMemberPath(assembly.frameRails, in: size)
                .stroke(Color(red: 0.76, green: 0.78, blue: 0.78), style: StrokeStyle(lineWidth: selected ? 4.2 : 3.2, lineCap: .round, lineJoin: .round))

            if let topFace {
                stageDeckSurfaceSeams(topFace, in: size)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, lineCap: .round))

                stageDeckFacePath(topFace, in: size)
                    .stroke(selected ? LumaStageDesign.coolBlue : Color.white.opacity(0.18), lineWidth: selected ? 3 : 1)
            }
        }
        .shadow(color: .black.opacity(0.34), radius: 8, y: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedObjectId = object.id
        }
    }

    private func stageDeckRenderFaces(_ assembly: StageDeckAssembly) -> [StageDeckFace] {
        [.backFrameSkirt, .leftFrameSkirt, .rightFrameSkirt, .frontFrameSkirt, .topSurface].compactMap { kind in
            assembly.faces.first(where: { $0.kind == kind })
        }
    }

    private func stageDeckFacePath(_ face: StageDeckFace, in size: CGSize) -> Path {
        Path { path in
            guard let firstVertex = face.vertices.first else {
                return
            }

            path.move(to: project(firstVertex, in: size))
            for vertex in face.vertices.dropFirst() {
                path.addLine(to: project(vertex, in: size))
            }
            path.closeSubpath()
        }
    }

    private func stageDeckFaceColor(_ kind: StageDeckFaceKind) -> Color {
        switch kind {
        case .topSurface:
            return Color(red: 0.115, green: 0.118, blue: 0.112)
        case .frontFrameSkirt:
            return Color(red: 0.46, green: 0.48, blue: 0.48)
        case .rightFrameSkirt, .leftFrameSkirt:
            return Color(red: 0.36, green: 0.38, blue: 0.38)
        case .backFrameSkirt:
            return Color(red: 0.28, green: 0.30, blue: 0.30)
        case .underside:
            return Color(red: 0.18, green: 0.19, blue: 0.19)
        }
    }

    private func stageDeckSurfaceSeams(_ topFace: StageDeckFace, in size: CGSize) -> Path {
        Path { path in
            guard topFace.vertices.count == 4 else {
                return
            }

            let backLeft = topFace.vertices[0]
            let backRight = topFace.vertices[1]
            let frontRight = topFace.vertices[2]
            let frontLeft = topFace.vertices[3]

            for index in 1...3 {
                let amount = Double(index) / 4
                path.move(to: project(interpolate(backLeft, frontLeft, amount: amount), in: size))
                path.addLine(to: project(interpolate(backRight, frontRight, amount: amount), in: size))
            }

            path.move(to: project(interpolate(backLeft, backRight, amount: 0.5), in: size))
            path.addLine(to: project(interpolate(frontLeft, frontRight, amount: 0.5), in: size))
        }
    }

    private func interpolate(_ start: Vector3Meters, _ end: Vector3Meters, amount: Double) -> Vector3Meters {
        Vector3Meters(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount,
            z: start.z + (end.z - start.z) * amount
        )
    }

    private func trussLayer(_ object: StageObject, in size: CGSize) -> some View {
        let selected = object.id == selectedObjectId
        let lattice = object.trussLattice
        let minimumY = StageBuilderRenderOrder.trussOcclusionMinimumY(
            for: object,
            stageBase: layout.objects.first(where: { $0.type == .stageBase })
        )
        let braces = StageBuilderRenderOrder.clipMembers(lattice.braces, minimumY: minimumY)
        let endCapMembers = StageBuilderRenderOrder.clipMembers(lattice.endCaps.flatMap(\.members), minimumY: minimumY)
        let chords = StageBuilderRenderOrder.clipMembers(lattice.chords, minimumY: minimumY)
        let allMembers = StageBuilderRenderOrder.clipMembers(lattice.allMembers, minimumY: minimumY)

        return ZStack {
            trussMemberPath(braces, in: size)
                .stroke(
                    selected ? LumaStageDesign.warmAmber.opacity(0.78) : Color.white.opacity(0.44),
                    style: StrokeStyle(lineWidth: selected ? 2.8 : 2.1, lineCap: .round, lineJoin: .round)
                )

            trussMemberPath(endCapMembers, in: size)
                .stroke(
                    selected ? LumaStageDesign.warmAmber.opacity(0.88) : Color.white.opacity(0.58),
                    style: StrokeStyle(lineWidth: selected ? 3.8 : 2.8, lineCap: .round, lineJoin: .round)
                )

            trussMemberPath(chords, in: size)
                .stroke(
                    selected ? LumaStageDesign.warmAmber : Color.white.opacity(0.76),
                    style: StrokeStyle(lineWidth: selected ? 5.2 : 4.0, lineCap: .round, lineJoin: .round)
                )

            trussMemberPath(allMembers, in: size)
                .stroke(Color.black.opacity(0.24), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedObjectId = object.id
        }
    }

    private func trussMemberPath(_ members: [TrussVisualMember], in size: CGSize) -> Path {
        Path { path in
            for member in members {
                path.move(to: project(member.start, in: size))
                path.addLine(to: project(member.end, in: size))
            }
        }
    }

    private func connectorBlockLayer(_ block: TrussConnectorBlock, in size: CGSize) -> some View {
        let point = project(block.position, in: size)
        let scale = projectionScale(in: size)
        let blockSize = max(14, CGFloat(block.size) * scale)
        let faceOffset = max(3, blockSize * 0.18)

        return ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.34, green: 0.35, blue: 0.36))
                .frame(width: blockSize, height: blockSize)
                .offset(x: faceOffset, y: -faceOffset)

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.84, blue: 0.84),
                            Color(red: 0.46, green: 0.48, blue: 0.49)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
                .frame(width: blockSize, height: blockSize)

            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: max(3, blockSize * 0.16), height: max(3, blockSize * 0.16))
                .offset(x: -blockSize * 0.22, y: -blockSize * 0.22)

            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: max(3, blockSize * 0.16), height: max(3, blockSize * 0.16))
                .offset(x: blockSize * 0.22, y: blockSize * 0.22)
        }
        .rotationEffect(cameraPreset == .isometric ? .degrees(-18) : .zero)
        .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
        .position(point)
        .allowsHitTesting(false)
    }

    private func project(_ point: Vector3Meters, in size: CGSize) -> CGPoint {
        let point = orbit(point)
        let scale = projectionScale(in: size)
        let x: CGFloat
        let y: CGFloat

        switch cameraPreset {
        case .front:
            x = CGFloat(point.x) * scale
            y = -CGFloat(point.y) * scale
        case .top:
            x = CGFloat(point.x) * scale
            y = CGFloat(point.z) * scale
        case .left:
            x = CGFloat(point.z) * scale
            y = -CGFloat(point.y) * scale
        case .right:
            x = -CGFloat(point.z) * scale
            y = -CGFloat(point.y) * scale
        case .isometric:
            x = CGFloat(point.x - point.z) * scale * 0.74
            y = CGFloat(point.x + point.z) * scale * 0.30 - CGFloat(point.y) * scale * 0.82
        }

        return CGPoint(
            x: size.width / 2 + x + panOffset.width,
            y: size.height * 0.62 + y + panOffset.height
        )
    }

    private func projectionScale(in size: CGSize) -> CGFloat {
        min(size.width / 9.5, size.height / 6.5) * zoom
    }

    private func orbit(_ point: Vector3Meters) -> Vector3Meters {
        let radians = orbitDegrees * Double.pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        return Vector3Meters(
            x: point.x * cosine - point.z * sine,
            y: point.y,
            z: point.x * sine + point.z * cosine
        )
    }
}

private enum StageLibraryTab: String, CaseIterable, Identifiable {
    case stage
    case truss
    case presets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stage:
            return "Stage"
        case .truss:
            return "Truss"
        case .presets:
            return "Presets"
        }
    }
}

private enum StageCameraPreset: String, CaseIterable, Identifiable {
    case isometric
    case front
    case top
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .isometric:
            return "Isometric"
        case .front:
            return "Front"
        case .top:
            return "Top"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }

    var deckDepthScale: CGFloat {
        switch self {
        case .front:
            return 0.32
        case .isometric:
            return 0.66
        case .top, .left, .right:
            return 1
        }
    }
}

private enum TransformAxis {
    case x
    case y
    case z
}

#Preview {
    StageBuilderView()
        .environment(AppModel())
}
