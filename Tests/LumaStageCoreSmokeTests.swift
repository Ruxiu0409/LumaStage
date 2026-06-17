import Foundation

@main
struct LumaStageCoreSmokeTests {
    static func main() async throws {
        try validatesDemoLookDefaults()
        defaultProjectListStartsEmpty()
        spotLightRenderMathMapsIntensityAndBeamAngle()
        try newProjectFactoryCreatesValidProject()
        try newProjectFactoryCreatesDefaultStageLayout()
        projectCreationTemplatesOfferBlankAndScenarioChoices()
        try projectFactoryAppliesScenarioTemplate()
        try stageBaseCanResizeWidthDepthAndHeight()
        try stageBaseExposesSolidGeometry()
        iPadRootProjectSelectionUsesAvailableWidth()
        stageBuilderLayoutKeepsInspectorOnScreen()
        stageBuilderInspectorCollapsesWithoutSelection()
        stageBuilderCameraPickerUsesMenuPresentation()
        stageBuilderToolbarHidesZoomStepper()
        stageBuilderToolbarHidesLayoutSummaryChips()
        stageBuilderViewportUsesProjectedGroundPlane()
        ipadPanelsAdoptNativeIOS26Styling()
        stageBuilderRendersBackTrussBehindStageBase()
        visionStageUsesIPadStageLayoutGeometry()
        stageBuilderSelectionPolicyClearsWhenViewportTapMissesObject()
        stageBuilderTrussLayersUseViewportHitTesting()
        stageBuilderZoomClampsPinchScale()
        stageLibraryHidesStandaloneStageDecks()
        stageLibraryDisplayNamesAvoidDimensionMultiplicationLabels()
        try stageBuilderDropPlannerPlacesDraggedAssets()
        try stagePlatformPresetsProvideDifferentStageSizes()
        try trussPortalPresetUsesOneAndTwoMeterSegments()
        try trussSegmentsExposeLatticeGeometry()
        try trussPortalDeduplicatesConnectorBlocks()
        try connectorSnappingAlignsNearbyTrussEnds()
        lightingFixtureCatalogCoversCurrentVocabulary()
        try patchesOnlySelectedCue()
        try fineControlPatchesOnlySelectedFixtureInSelectedCue()
        try resetsOnlySelectedCue()
        try rejectsInvalidPatchValues()
        try lightingLookDraftBuildsValidatedLook()
        lightingLookDraftRejectsInvalidValues()
        try goboFlowsThroughDraftAndSurvivesCodec()
        await unavailableLightingServiceReportsUnavailable()
        print("LumaStageCoreSmokeTests passed")
    }

    private static func validatesDemoLookDefaults() throws {
        let look = LightingLook.mvpDemo()

        expect(look.ambient.preset == .standardNight, "MVP ambient must stay standardNight")
        expect(look.cues.map(\.name) == ["Opening", "Highlight"], "MVP must expose Opening and Highlight cues")
        expect(look.selectedCueId == "cue_opening", "Opening should be the default selected cue")
        try look.validate()
    }

    private static func defaultProjectListStartsEmpty() {
        let projects = LumaStageProject.defaultProjects()

        expect(projects.isEmpty, "Project home should start empty by default")
    }

    private static func spotLightRenderMathMapsIntensityAndBeamAngle() {
        // Lumens: clamps to 0...1, hits the role endpoints, and rises monotonically.
        expect(SpotLightRenderMath.lumens(forIntensity: 0, role: .frontLight) == 0,
               "Zero intensity must map to zero lumens")
        expect(SpotLightRenderMath.lumens(forIntensity: 1, role: .frontLight) == SpotLightRenderMath.maxLumens(role: .frontLight),
               "Full intensity must map to the role's peak lumens")
        expect(SpotLightRenderMath.lumens(forIntensity: -0.5, role: .frontLight) == 0,
               "Negative intensity must clamp to zero lumens")
        expect(SpotLightRenderMath.lumens(forIntensity: 1.7, role: .frontLight) == SpotLightRenderMath.maxLumens(role: .frontLight),
               "Above-one intensity must clamp to peak lumens")
        expect(SpotLightRenderMath.lumens(forIntensity: 0.5, role: .frontLight) > SpotLightRenderMath.lumens(forIntensity: 0.25, role: .frontLight),
               "Lumens must increase with intensity")
        expect(SpotLightRenderMath.lumens(forIntensity: 1, role: .spot) > SpotLightRenderMath.lumens(forIntensity: 1, role: .backgroundWash),
               "Peak lumens must stay role-sensitive (a spot out-throws a background wash)")

        // Cone angles: bounded 10°...60° outer, inner tighter than outer, monotonic, clamped.
        let narrow = SpotLightRenderMath.coneAngles(beamAngleDegrees: 5)
        let wide = SpotLightRenderMath.coneAngles(beamAngleDegrees: 120)
        expect(abs(narrow.inner - narrow.outer * 0.7) < 0.0001, "Inner cone must be 70% of the outer cone for a soft penumbra edge")
        expect(abs(narrow.outer - 10) < 0.0001, "Minimum beam spread must map to a 10° outer cone")
        expect(abs(wide.outer - 60) < 0.0001, "Maximum beam spread must map to a 60° outer cone")
        expect(narrow.inner < narrow.outer, "Inner cone must sit inside the outer cone")
        expect(wide.inner < wide.outer, "Inner cone must sit inside the outer cone (wide)")
        expect(wide.outer > narrow.outer, "Wider beam spread must widen the cone")
        expect(SpotLightRenderMath.coneAngles(beamAngleDegrees: 1).outer == narrow.outer,
               "Below-range beam spread must clamp to the minimum cone")
        expect(SpotLightRenderMath.coneAngles(beamAngleDegrees: 200).outer == wide.outer,
               "Above-range beam spread must clamp to the maximum cone")

        // Shadow light size: bounded 0.04...0.40 m, widening with the beam, clamped at the ends.
        expect(abs(SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 5) - 0.04) < 0.0001,
               "Minimum beam spread must map to the smallest (hardest) shadow light size")
        expect(abs(SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 120) - 0.40) < 0.0001,
               "Maximum beam spread must map to the largest (softest) shadow light size")
        expect(SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 80) > SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 30),
               "Wider beam spread must soften the shadow (larger light size)")
        expect(SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 0) == SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 5),
               "Below-range beam spread must clamp to the smallest shadow light size")
        expect(SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 300) == SpotLightRenderMath.shadowLightSize(beamAngleDegrees: 120),
               "Above-range beam spread must clamp to the largest shadow light size")
    }

    private static func newProjectFactoryCreatesValidProject() throws {
        let project = LumaStageProject.newProject(index: 1)

        expect(!project.id.isEmpty, "New project should have an id")
        expect(!project.name.isEmpty, "New project should have a display name")
        expect(!project.venueDescription.isEmpty, "New project should have venue context")
        try project.lightingLook.validate()
    }

    private static func newProjectFactoryCreatesDefaultStageLayout() throws {
        let project = LumaStageProject.newProject(index: 1)
        let layout = project.stageLayout

        expect(layout.name == "Student Outdoor Stage", "New projects should start with an English student outdoor stage layout")
        expect(layout.units == .meters, "Stage builder should use meters")
        expect(abs(layout.gridSize - 0.5) < 0.0001, "Stage builder grid should default to 0.5m")
        expect(layout.objects.contains(where: { $0.assetId == .stageBase }), "Default layout should include an adjustable stage base")
        expect(!layout.objects.contains(where: { $0.type == .stageDeck }), "Stage decks should be hidden inside the stage base, not exposed as standalone objects")
        expect(layout.objects.contains(where: { $0.assetId == .truss2m }), "Default layout should include 2m truss segments")
        try layout.validate()
    }

    private static func projectCreationTemplatesOfferBlankAndScenarioChoices() {
        let templates = ProjectCreationTemplate.allTemplates

        expect(templates.first?.kind == .blank, "Project creation should start with a blank option")
        expect(templates.contains(where: { $0.kind == .campusMusic }), "Project creation should offer a campus music scenario")
        expect(templates.contains(where: { $0.kind == .clubShowcase }), "Project creation should offer a club showcase scenario")
        expect(templates.contains(where: { $0.kind == .graduationParty }), "Project creation should offer a graduation party scenario")
        expect(templates.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty }, "Every project template should have English labels")
        expect(templates.allSatisfy { !$0.introduction.isEmpty }, "Every project template should include an intro paragraph")
        expect(Set(templates.map(\.visualStyle)).count == templates.count, "Every project template should have a distinct preview image style")
    }

    private static func projectFactoryAppliesScenarioTemplate() throws {
        let project = LumaStageProject.newProject(index: 2, template: .campusMusic)

        expect(project.name == "Campus Music Night 2", "Scenario templates should name new projects from the selected context")
        expect(project.eventType == "Student Performance", "Scenario templates should apply their event type")
        expect(project.lightingLook.mood.contains("Warm"), "Scenario templates should apply a matching lighting mood")
        try project.stageLayout.validate()
        try project.lightingLook.validate()
    }

    private static func stageBaseCanResizeWidthDepthAndHeight() throws {
        var layout = StageLayout.empty(name: "Stage Base Test")
        var base = StageObject.stageBase(
            id: "base",
            position: .zero,
            size: StageObjectSize(width: 4, depth: 2, height: 0.8)
        )
        try layout.addObject(base)

        base.size = StageObjectSize(width: 6, depth: 3, height: 1.2)
        base.position.y = 0.6
        try layout.updateObject(base)

        let summary = layout.stageSummary()

        expect(layout.object(id: "base")?.type == .stageBase, "Stage base should be selectable as its own object")
        expect(abs(summary.stageSize.width - 6) < 0.0001, "Stage base width should drive stage summary")
        expect(abs(summary.stageSize.depth - 3) < 0.0001, "Stage base depth should drive stage summary")
        expect(abs(summary.stageSize.height - 1.2) < 0.0001, "Stage base height should drive stage summary")
        try layout.validate()
    }

    private static func stageBaseExposesSolidGeometry() throws {
        let base = StageObject.stageBase(
            id: "base_solid",
            position: .zero,
            size: StageObjectSize(width: 6, depth: 3, height: 1)
        )

        let solid = try expectUnwrapped(base.stageBaseSolid, "Stage base should expose a generated solid model")

        expect(solid.vertices.count == 8, "Stage base solid should be built from 8 box vertices")
        expect(solid.faces.count == 6, "Stage base solid should expose six faces, not a flat image")
        expect(solid.faces.contains(where: { $0.kind == .top }), "Stage base solid should include a top surface")
        expect(solid.faces.contains(where: { $0.kind == .front }), "Stage base solid should include a visible front face")
        expect(solid.faces.contains(where: { $0.kind == .right }), "Stage base solid should include a visible side face")
    }

    private static func iPadRootProjectSelectionUsesAvailableWidth() {
        expect(
            abs(IPadRootLayout.projectSelectionWidth(availableWidth: 1024) - 976) < 0.0001,
            "iPad project selection should use the available landscape width instead of staying locked to a narrow 760pt frame"
        )
    }

    private static func stageBuilderLayoutKeepsInspectorOnScreen() {
        let compact = StageBuilderPanelLayout.make(availableWidth: 599)
        let regular = StageBuilderPanelLayout.make(availableWidth: 1024)

        expect(compact.usesStackedPanels, "Stage builder should stack side panels on narrow simulator screenshots")
        expect(compact.usesScrollableLibraryPanel, "Compact library panel should be scrollable when content overflows")
        expect(compact.bottomPanelWidth * 2 + compact.spacing <= 599, "Compact side panels should fit within the available width")
        expect(!regular.usesStackedPanels, "Landscape iPad width should use the three-column editor")
        expect(regular.usesScrollableLibraryPanel, "Regular iPad library panel should be scrollable when content overflows")
        let regularRequiredWidth = regular.libraryWidth + regular.inspectorWidth + regular.minimumViewportWidth + regular.spacing * 2
        expect(regularRequiredWidth <= 1024, "Regular editor columns should keep the inspector on screen")
    }

    private static func stageBuilderInspectorCollapsesWithoutSelection() {
        expect(!StageBuilderInspectorPolicy.isVisible(selectedObjectId: nil), "Inspector should collapse when no object is selected")
        expect(StageBuilderInspectorPolicy.isVisible(selectedObjectId: "stage_base_default"), "Inspector should be visible when an object is selected")
    }

    private static func stageBuilderCameraPickerUsesMenuPresentation() {
        expect(StageBuilderToolbarLayout.cameraPickerPresentation == .menu, "Camera picker should use a menu instead of showing all view presets in the toolbar")
    }

    private static func stageBuilderToolbarHidesZoomStepper() {
        expect(!StageBuilderToolbarLayout.showsZoomStepper, "Toolbar zoom should rely on pinch gestures instead of a visible Stepper")
    }

    private static func stageBuilderToolbarHidesLayoutSummaryChips() {
        expect(!StageBuilderToolbarLayout.showsLayoutSummaryChips, "Toolbar should not show the stage layout name or object count chips")
    }

    private static func stageBuilderViewportUsesProjectedGroundPlane() {
        let lines = StageBuilderViewportGround.referenceLines()

        expect(StageBuilderViewportGround.usesProjectedWorldPlane, "Viewport background should be projected from the 3D ground plane, not drawn as a screen-aligned 2D grid")
        expect(!lines.isEmpty, "Projected ground plane should expose reference lines")
        expect(lines.allSatisfy { $0.start.y == 0 && $0.end.y == 0 }, "Projected ground lines should live on the stage floor at y=0")
        expect(lines.contains(where: { $0.start.x != $0.end.x }), "Ground plane should include world X direction guides")
        expect(lines.contains(where: { $0.start.z != $0.end.z }), "Ground plane should include world Z direction guides")
        expect(lines.contains(where: \.isMajor), "Ground plane should include stronger major reference lines")
    }

    private static func ipadPanelsAdoptNativeIOS26Styling() {
        expect(LumaStageDesign.adoptsIOS26NativePanelStyle, "iPad panels should use the native iOS 26 visual language instead of heavy custom gray panels")
        expect(LumaStageDesign.surfaceRadius > LumaStageDesign.cornerRadius, "Top-level glass panels should use a softer system-style radius than small repeated cards")
    }

    private static func stageBuilderRendersBackTrussBehindStageBase() {
        let layout = StageLayout.defaultStudentOutdoor()
        let renderedObjects = StageBuilderRenderOrder.objectsForIsometricViewport(layout.objects)
        let stageIndex = renderedObjects.firstIndex(where: { $0.type == .stageBase })
        let backTrussIndex = renderedObjects.firstIndex(where: { $0.type == .trussSegment && $0.position.z < -1 })

        expect(stageIndex != nil, "Default stage should include a stage base")
        expect(backTrussIndex != nil, "Default portal should include truss behind the stage")
        expect(backTrussIndex! < stageIndex!, "Back truss should render before the stage base so the stage hides the truss feet")

        let stageBase = layout.objects.first(where: { $0.type == .stageBase })
        let backConnector = Vector3Meters(x: -2, y: 0, z: -1.25)
        expect(
            StageBuilderRenderOrder.connectorLayer(position: backConnector, stageBase: stageBase) == .behindStageBase,
            "Connector blocks behind the stage should render before the stage base"
        )
        expect(
            !StageBuilderRenderOrder.shouldRenderConnectorBlock(TrussConnectorBlock(id: "hidden", position: backConnector, size: 0.34), stageBase: stageBase),
            "Connector blocks behind and below the stage top should be hidden by the stage base"
        )

        let verticalFoot = TrussVisualMember(
            start: Vector3Meters(x: -2, y: 0, z: -1.25),
            end: Vector3Meters(x: -2, y: 2, z: -1.25)
        )
        let clipped = StageBuilderRenderOrder.clipMembers([verticalFoot], minimumY: 0.8)
        expect(clipped.count == 1, "Back truss legs should remain visible above the stage top")
        expect(abs(clipped[0].start.y - 0.8) < 0.0001, "Back truss legs should be clipped at the stage top instead of showing the feet")
    }

    private static func visionStageUsesIPadStageLayoutGeometry() {
        let layout = StageLayout.defaultStudentOutdoor()
        let plan = ImmersiveStageGeometryPlan.make(from: layout)
        let expectedTrussMembers = layout.objects
            .filter { $0.type == .trussSegment }
            .flatMap { $0.trussLattice.allMembers }

        expect(ImmersiveStageGeometryPlan.usesSharedStageLayout, "Vision Pro stage should use the same shared stage layout model as iPad")
        expect(plan.stageBases == layout.objects.filter { $0.type == .stageBase }, "Vision Pro stage should reuse iPad stage base objects")
        expect(plan.trussMembers == expectedTrussMembers, "Vision Pro truss should reuse the iPad truss lattice geometry")
        expect(plan.connectorBlocks == layout.trussConnectorBlocks, "Vision Pro connector blocks should match iPad truss intersections")
        expect(plan.layoutSignature.contains(layout.stageLayoutId), "Vision Pro layout signature should track the shared stage layout")
    }

    private static func stageBuilderSelectionPolicyClearsWhenViewportTapMissesObject() {
        expect(
            StageBuilderSelectionPolicy.selectedObjectIdAfterViewportTap(currentSelectionId: "deck_1", hitObjectId: nil) == nil,
            "Tapping empty viewport space should clear the selected object"
        )
        expect(
            StageBuilderSelectionPolicy.selectedObjectIdAfterViewportTap(currentSelectionId: "deck_1", hitObjectId: "truss_1") == "truss_1",
            "Tapping an object should keep the editor in object selection mode"
        )
    }

    private static func stageBuilderTrussLayersUseViewportHitTesting() {
        expect(
            !StageBuilderObjectLayerHitTesting.allowsDirectLayerTap(for: .trussSegment),
            "Truss visual layers should not intercept the full viewport; viewport geometry hit-testing must choose the tapped truss"
        )
    }

    private static func stageBuilderZoomClampsPinchScale() {
        expect(StageBuilderZoom.clamped(0.2) == StageBuilderZoom.minimum, "Pinch zoom should not shrink below minimum")
        expect(StageBuilderZoom.clamped(2.5) == StageBuilderZoom.maximum, "Pinch zoom should not grow above maximum")
        expect(abs(StageBuilderZoom.scaled(base: 1.0, magnification: 1.25) - 1.25) < 0.0001, "Pinch zoom should scale from the base zoom")
        expect(StageBuilderZoom.scaled(base: 1.4, magnification: 2.0) == StageBuilderZoom.maximum, "Pinch zoom should clamp after scaling")
    }

    private static func stageLibraryHidesStandaloneStageDecks() {
        expect(StageBuilderStageLibraryAssets.stageTab == [.stageBase], "Stage library should only expose the stage base; individual deck boards are hidden inside it")
    }

    private static func stageLibraryDisplayNamesAvoidDimensionMultiplicationLabels() {
        let stageAssetNames = [
            StageAssetId.stageBase.displayName,
            StagePlatformPreset.small4x2.displayName,
            StagePlatformPreset.medium6x3.displayName,
            StagePlatformPreset.large8x4.displayName
        ]

        expect(stageAssetNames.allSatisfy { !$0.contains(" x ") }, "Stage library card titles should not show width-by-depth multiplication labels")
    }

    private static func stageBuilderDropPlannerPlacesDraggedAssets() throws {
        let base = try expectUnwrapped(
            StageBuilderDropPlanner.object(
                assetId: .stageBase,
                id: "base_drop",
                existingObjects: [],
                dropPosition: Vector3Meters(x: -1, y: 0, z: 1)
            ),
            "Stage base drops should create a stage object"
        )
        let truss = try expectUnwrapped(
            StageBuilderDropPlanner.object(
                assetId: .truss2m,
                id: "truss_drop",
                existingObjects: [],
                dropPosition: Vector3Meters(x: 0.5, y: 0, z: -1)
            ),
            "Truss drops should create a stage object"
        )

        expect(
            StageBuilderDropPlanner.object(assetId: .stageDeck2x2, id: "deck_drop", existingObjects: [], dropPosition: .zero) == nil,
            "Standalone stage deck drops should be blocked because deck boards are represented inside the stage base"
        )
        expect(abs(base.position.y - 0.4) < 0.0001, "Dragged stage bases should sit on the ground by half their height")
        expect(truss.position.y == 3, "Dragged truss segments should keep the default rigging height")
    }

    private static func stagePlatformPresetsProvideDifferentStageSizes() throws {
        let small = StageLayout.stagePlatformPreset(.small4x2)
        let medium = StageLayout.stagePlatformPreset(.medium6x3)
        let large = StageLayout.stagePlatformPreset(.large8x4)

        expect(small.count == 1 && small.first?.type == .stageBase, "4m x 2m stage should be represented by one stage base")
        expect(medium.count == 1 && medium.first?.type == .stageBase, "6m x 3m stage should be represented by one stage base")
        expect(large.count == 1 && large.first?.type == .stageBase, "8m x 4m stage should be represented by one stage base")

        var layout = StageLayout.empty(name: "Stage Preset Test")
        for object in large {
            try layout.addObject(object)
        }
        let summary = layout.stageSummary()

        expect(abs(summary.stageSize.width - 8) < 0.0001, "Large stage preset should summarize as 8m wide")
        expect(abs(summary.stageSize.depth - 4) < 0.0001, "Large stage preset should summarize as 4m deep")
        try layout.validate()
    }

    private static func trussPortalPresetUsesOneAndTwoMeterSegments() throws {
        let objects = StageLayout.trussPortalPreset(.portal4x3)
        let trussObjects = objects.filter { $0.type == .trussSegment }

        expect(trussObjects.count == 6, "4m x 3m portal should be built from six truss segments")
        expect(trussObjects.filter { $0.assetId == .truss2m }.count == 4, "4m x 3m portal should use four 2m truss segments")
        expect(trussObjects.filter { $0.assetId == .truss1m }.count == 2, "4m x 3m portal should use two 1m truss segments")
        expect(trussObjects.allSatisfy { $0.rotation.isRightAngleAligned }, "Portal truss rotations should be 90-degree aligned")

        var layout = StageLayout.empty(name: "Portal Test")
        for object in objects {
            try layout.addObject(object)
        }
        try layout.validate()
    }

    private static func trussSegmentsExposeLatticeGeometry() throws {
        let truss = StageObject.trussSegment(
            id: "truss_visual_test",
            assetId: .truss2m,
            position: Vector3Meters(x: 0, y: 3, z: 0)
        )

        let lattice = truss.trussLattice

        expect(lattice.chords.count == 4, "Rendered truss should have four longitudinal chords")
        expect(lattice.braces.count >= 8, "Rendered truss should include diagonal lattice braces")
        expect(lattice.endCaps.count == 2, "Rendered truss should include end cap frames")
        expect(lattice.allMembers.count > 1, "Rendered truss must not collapse to a single line")
    }

    private static func trussPortalDeduplicatesConnectorBlocks() throws {
        var layout = StageLayout.empty(name: "Connector Block Test")
        for object in StageLayout.trussPortalPreset(.portal4x3) {
            try layout.addObject(object)
        }

        let connectorBlocks = layout.trussConnectorBlocks
        let rawEndpointCount = layout.objects.flatMap(\.trussEndpoints).count

        expect(connectorBlocks.count < rawEndpointCount, "Shared truss intersections should be merged into one connector block")
        expect(connectorBlocks.contains { abs($0.position.x + 2) < 0.0001 && abs($0.position.y - 3) < 0.0001 }, "Portal should expose a connector block at the top-left corner")
        expect(connectorBlocks.allSatisfy { abs($0.size - 0.34) < 0.0001 }, "Connector blocks should use a square block size")
    }

    private static func connectorSnappingAlignsNearbyTrussEnds() throws {
        var layout = StageLayout.empty(name: "Snap Test")
        let base = StageObject.trussSegment(
            id: "truss_base",
            assetId: .truss2m,
            displayName: "2m Truss",
            position: Vector3Meters(x: 0, y: 3, z: 0),
            rotation: Vector3Degrees(x: 0, y: 0, z: 0)
        )
        try layout.addObject(base)

        let candidate = StageObject.trussSegment(
            id: "truss_candidate",
            assetId: .truss2m,
            displayName: "2m Truss",
            position: Vector3Meters(x: 2.11, y: 3.04, z: 0.03),
            rotation: Vector3Degrees(x: 0, y: 0, z: 0)
        )

        let snapped = layout.snappedObject(candidate)

        expect(abs(snapped.position.x - 2.0) < 0.0001, "Candidate should snap exactly to the base truss end on X")
        expect(abs(snapped.position.y - 3.0) < 0.0001, "Candidate should snap exactly to the base truss end on Y")
        expect(abs(snapped.position.z - 0.0) < 0.0001, "Candidate should snap exactly to the base truss end on Z")
    }

    private static func lightingFixtureCatalogCoversCurrentVocabulary() {
        let catalog = LightingFixtureCatalog.allFixtures
        let roles = Set(catalog.map(\.role))

        expect(catalog.count == 4, "Fixture intro should cover the four current MVP fixture roles")
        expect(roles == Set(FixtureRole.allCases), "Fixture intro should match the current fixture vocabulary exactly")
        expect(catalog.allSatisfy { !$0.displayName.isEmpty }, "Every fixture intro should have a display name")
        expect(catalog.allSatisfy { !$0.shortDescription.isEmpty }, "Every fixture intro should explain what the fixture does")
        expect(catalog.allSatisfy { !$0.beginnerPromptHint.isEmpty }, "Every fixture intro should teach users how to ask AI for the fixture")
        expect(Set(catalog.map(\.visualModel)).count == catalog.count, "Each fixture intro should have a distinct model")
        expect(catalog.allSatisfy { $0.previewTechnology == .sceneKit3D }, "Fixture intro previews should use real 3D SceneKit models, not flat SwiftUI drawings")
    }

    private static func patchesOnlySelectedCue() throws {
        var state = StageState(lightingLook: .mvpDemo())

        try state.patchSelectedCue(.frontLightDimmer(0.42))
        try state.patchSelectedCue(.backgroundWashColor("#33AAFF"))

        let opening = try state.requireSelectedCue()
        let openingFront = try opening.requireFixture(role: .frontLight)
        let openingBackground = try opening.requireFixture(role: .backgroundWash)
        let highlight = try state.lightingLook.requireCue(id: "cue_highlight")
        let highlightFront = try highlight.requireFixture(role: .frontLight)

        expect(abs(openingFront.intensity - 0.42) < 0.0001, "selected cue front light dimmer should be patched")
        expect(openingBackground.color.value == "#33AAFF", "selected cue background wash color should be patched")
        expect(abs(highlightFront.intensity - 0.75) < 0.0001, "unselected cue must not be patched")
    }

    private static func fineControlPatchesOnlySelectedFixtureInSelectedCue() throws {
        var state = StageState(lightingLook: .mvpDemo())
        let control = FixtureFineControl(
            position: FixturePosition(x: -0.35, y: 2.45, z: -1.1),
            panDegrees: 28,
            tiltDegrees: -34,
            rollDegrees: 6,
            beamAngleDegrees: 42
        )

        try state.patchSelectedCue(.fixtureIntensity(fixtureId: "front_wash", intensity: 0.33))
        try state.patchSelectedCue(.fixtureColor(fixtureId: "front_wash", hexColor: "#33AAFF"))
        try state.patchSelectedCue(.fixtureFineControl(fixtureId: "front_wash", control: control))

        let opening = try state.lightingLook.requireCue(id: "cue_opening")
        let openingFront = try opening.requireFixture(role: .frontLight)
        let highlight = try state.lightingLook.requireCue(id: "cue_highlight")
        let highlightFront = try highlight.requireFixture(role: .frontLight)

        expect(abs(openingFront.intensity - 0.33) < 0.0001, "Fine Control intensity should patch the selected fixture")
        expect(openingFront.color.value == "#33AAFF", "Fine Control color should patch the selected fixture")
        expect(openingFront.fineControl == control, "Fine Control transform should patch the selected fixture")
        expect(abs(highlightFront.intensity - 0.75) < 0.0001, "Fine Control must not patch the same fixture in another cue")
        expect(highlightFront.fineControl != control, "Fine Control transform must remain scoped to the selected cue")
    }

    private static func resetsOnlySelectedCue() throws {
        var state = StageState(lightingLook: .mvpDemo())

        try state.patchSelectedCue(.frontLightDimmer(0.2))
        state.selectedCueId = "cue_highlight"
        try state.patchSelectedCue(.frontLightDimmer(0.95))
        try state.resetSelectedCue()

        let opening = try state.lightingLook.requireCue(id: "cue_opening")
        let openingFront = try opening.requireFixture(role: .frontLight)
        let highlight = try state.lightingLook.requireCue(id: "cue_highlight")
        let highlightFront = try highlight.requireFixture(role: .frontLight)

        expect(abs(openingFront.intensity - 0.2) < 0.0001, "reset must not touch the unselected Opening cue")
        expect(abs(highlightFront.intensity - 0.75) < 0.0001, "reset should restore selected Highlight cue baseline")
    }

    private static func rejectsInvalidPatchValues() throws {
        var state = StageState(lightingLook: .mvpDemo())

        expectThrows(ValidationError.invalidIntensity(1.4)) {
            try state.patchSelectedCue(.frontLightDimmer(1.4))
        }

        expectThrows(ValidationError.invalidHexColor("blue")) {
            try state.patchSelectedCue(.backgroundWashColor("blue"))
        }
    }

    // The on-device FoundationModels service cannot run headlessly, but the AI → domain
    // boundary it relies on (assembling + validating a LightingLook from model-produced
    // primitives) is Foundation-only and fully testable here.
    private static func lightingLookDraftBuildsValidatedLook() throws {
        let look = try sampleDraft().makeValidatedLook()

        try look.validate()
        expect(look.schemaVersion == "1.0", "draft should build a v1.0 look")
        expect(look.ambient.preset == .standardNight, "draft should pin the standardNight ambient baseline")
        expect(look.selectedCueId == "cue_opening", "draft should select the Opening cue")
        expect(look.cues.map(\.id) == ["cue_opening", "cue_highlight"], "draft should assign the two required MVP cue ids")
        expect(look.cues.map(\.name) == ["Opening", "Highlight"], "draft should name the two MVP cues")

        let opening = try look.requireCue(id: "cue_opening")
        let front = try opening.requireFixture(role: .frontLight)
        expect(abs(front.intensity - 0.6) < 0.0001, "draft front light intensity should map into the look")
        expect(front.color.value == "#FFD1A3", "draft fixture hex should be normalized into the look")
    }

    private static func lightingLookDraftRejectsInvalidValues() {
        expectThrows(ValidationError.invalidHexColor("not-a-color")) {
            _ = try sampleDraft(backgroundHex: "not-a-color").makeValidatedLook()
        }

        expectThrows(ValidationError.invalidIntensity(1.8)) {
            _ = try sampleDraft(frontIntensity: 1.8).makeValidatedLook()
        }
    }

    private static func goboFlowsThroughDraftAndSurvivesCodec() throws {
        // A gobo set on a draft fixture must land on the assembled look's fixture.
        let draft = LightingLookDraft(
            lookName: "Gobo Look",
            mood: "patterned, atmospheric",
            openingFixtures: [
                LightingLookDraft.Fixture(id: "front_wash", name: "Front Wash", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.6, colorHex: "#FFD1A3", gobo: .breakup),
                LightingLookDraft.Fixture(id: "background_wash", name: "Background Wash", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: 0.75, colorHex: "#4FA8FF", gobo: .stars),
                LightingLookDraft.Fixture(id: "side_wash", name: "Side Wash", role: .wash, zone: .stageLeft, enabled: true, intensity: 0.5, colorHex: "#88AAFF", gobo: .stripes)
            ],
            highlightFixtures: [
                LightingLookDraft.Fixture(id: "front_wash", name: "Front Wash", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.75, colorHex: "#FFE0B8"),
                LightingLookDraft.Fixture(id: "background_wash", name: "Background Wash", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: 0.9, colorHex: "#2F6BFF")
            ],
            explanationTerm: "Gobo",
            explanationPlainText: "A gobo projects a shaped pattern through a fixture's beam.",
            explanationActionSummary: "Added a foliage breakup and a starfield projection."
        )

        let look = try draft.makeValidatedLook()
        try look.validate()
        let opening = try look.requireCue(id: "cue_opening")
        let openingFront = try opening.requireFixture(role: .frontLight)
        let openingBackground = try opening.requireFixture(role: .backgroundWash)
        let openingSideWash = try opening.requireFixture(role: .wash)
        let highlightFront = try look.requireCue(id: "cue_highlight").requireFixture(role: .frontLight)
        expect(openingFront.gobo == .breakup, "Draft gobo should land on the front light fixture")
        expect(openingBackground.gobo == .stars, "Draft gobo should land on the background wash fixture")
        expect(highlightFront.gobo == nil, "A fixture without a gobo should stay nil through the draft")
        expect(openingSideWash.gobo == nil, "A gobo on a non-rendering role (wash) should be cleared during assembly")

        // Gobo display names are reusable logic with no current consumer; pin them so they stay stable.
        expect(GoboPattern.breakup.displayName == "Foliage Breakup", "breakup display name should be stable")
        expect(GoboPattern.stripes.displayName == "Slats", "stripes display name should be stable")
        expect(GoboPattern.stars.displayName == "Starfield", "stars display name should be stable")
        expect(GoboPattern.grid.displayName == "Window", "grid display name should be stable")

        // Codable: a fixture round-trips its gobo.
        let fixture = FixtureGroup(id: "f", name: "F", role: .spot, zone: .stageLeft, enabled: true, intensity: 0.5, color: FixtureColor(mode: .rgb, value: "#FFFFFF"), gobo: .grid)
        let encoded = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(FixtureGroup.self, from: encoded)
        expect(decoded.gobo == .grid, "FixtureGroup gobo should survive a Codable round-trip")

        // Backward compatibility: JSON written before gobo existed must decode with gobo == nil.
        let legacyJSON = Data("""
        {"id":"legacy","name":"Legacy","role":"frontLight","zone":"stageFront","enabled":true,"intensity":0.5,"color":{"mode":"rgb","value":"#FFFFFF"}}
        """.utf8)
        let legacy = try JSONDecoder().decode(FixtureGroup.self, from: legacyJSON)
        expect(legacy.gobo == nil, "Legacy fixtures without a gobo field should decode to nil")
        expect(legacy.fineControl == nil, "Legacy fixtures without a fineControl field should still decode")
    }

    private static func unavailableLightingServiceReportsUnavailable() async {
        let service = UnavailableLightingLookService(reason: "Test environment")

        expect(!service.availability.isAvailable, "unavailable service should report unavailable")
        expect(service.availability.unavailableReason == "Test environment", "unavailable service should surface its reason")

        do {
            _ = try await service.generateLook(from: "Create a warm opening look")
            fatalError("Unavailable service should refuse to generate")
        } catch let error as LightingGenerationError {
            expect(error == .modelUnavailable("Test environment"), "unavailable service should throw modelUnavailable")
        } catch {
            fatalError("Expected LightingGenerationError, got \(error)")
        }
    }

    private static func sampleDraft(
        frontIntensity: Double = 0.6,
        backgroundHex: String = "#4FA8FF"
    ) -> LightingLookDraft {
        func fixtures(front: Double) -> [LightingLookDraft.Fixture] {
            [
                LightingLookDraft.Fixture(id: "front_wash", name: "Front Wash", role: .frontLight, zone: .stageFront, enabled: true, intensity: front, colorHex: "#FFD1A3"),
                LightingLookDraft.Fixture(id: "background_wash", name: "Background Wash", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: 0.75, colorHex: backgroundHex)
            ]
        }

        return LightingLookDraft(
            lookName: "Test Look",
            mood: "warm, test",
            openingFixtures: fixtures(front: frontIntensity),
            highlightFixtures: fixtures(front: min(frontIntensity + 0.15, 1.0)),
            explanationTerm: "Intensity",
            explanationPlainText: "How strong the light output is.",
            explanationActionSummary: "Generated Opening and Highlight cues."
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }

    private static func expectThrows<E: Error & Equatable>(_ expected: E, _ operation: () throws -> Void) {
        do {
            try operation()
            fatalError("Expected \(expected), but no error was thrown")
        } catch let error as E {
            expect(error == expected, "Expected \(expected), got \(error)")
        } catch {
            fatalError("Expected \(expected), got \(error)")
        }
    }

    private static func expectUnwrapped<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            fatalError(message)
        }

        return value
    }

}
