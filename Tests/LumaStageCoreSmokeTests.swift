import Foundation

@main
struct LumaStageCoreSmokeTests {
    static func main() async throws {
        try validatesDemoLookDefaults()
        try defaultProjectsShipPlayableShowcase()
        spotLightRenderMathMapsIntensityAndBeamAngle()
        laserBeamMathDerivesCoreAndSheathLayers()
        try newProjectFactoryCreatesValidProject()
        try newProjectFactoryCreatesDefaultStageLayout()
        projectCreationOffersTemplatesWithBlankOption()
        try projectFactoryAppliesScenarioTemplate()
        try projectFactoryCreatesBlankStageProject()
        try stageBaseCanResizeWidthDepthAndHeight()
        try stageBaseExposesSolidGeometry()
        iPadRootProjectSelectionUsesAvailableWidth()
        stageBuilderLayoutKeepsInspectorOnScreen()
        stageBuilderInspectorCollapsesWithoutSelection()
        stageBuilderCameraPickerUsesMenuPresentation()
        stageBuilderToolbarHidesZoomStepper()
        stageBuilderToolbarHidesLayoutSummaryChips()
        stageBuilderViewportUsesProjectedGroundPlane()
        nativeGlassDesignUsesSystemRadiusHierarchy()
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
        try tallTrussPortalBuildsLegsToFullHeight()
        try trussSegmentsExposeLatticeGeometry()
        try trussPortalDeduplicatesConnectorBlocks()
        try connectorSnappingAlignsNearbyTrussEnds()
        try tabletopEditingSwapsStagePlatformPreset()
        try tabletopEditingSwapsTrussPortalPreset()
        try movingTrussDoesNotSnapBackOntoItsOwnEndpoints()
        try trussNodeSnapMarksActiveConnectorNode()
        tabletopSurfaceSelectionPrefersNearestLargestTable()
        lightingFixtureCatalogCoversCurrentVocabulary()
        fixtureCarouselPagesAndWraps()
        try lumaSyncProtocolRoundTrips()
        try groupAutoSeedFromRoleZone()
        groupMasterResolutionAndPrecedence()
        loopbackTransportDeliversMessages()
        try patchesOnlySelectedCue()
        try fineControlPatchesOnlySelectedFixtureInSelectedCue()
        try resetsOnlySelectedCue()
        try rejectsInvalidPatchValues()
        try roleColorPatchRecolorsEveryMatchingFixtureInSelectedCueOnly()
        try lightingLookDraftBuildsValidatedLook()
        lightingLookDraftRejectsInvalidValues()
        normalizedHexToleratesModelNoise()
        try goboFlowsThroughDraftAndSurvivesCodec()
        try aiEffectFlowsThroughDraftAndSurvivesCodec()
        try explanationRationaleFlowsThroughDraftAndIsBackCompat()
        try lightEffectPlanPrefersAuthoredEffectOverSuggested()
        try dmxAndTargetSurviveValidationAndCodec()
        try showcaseDemoIsValidAndDiverse()
        try aiDraftGuaranteesRenderableFrontAndBackgroundFixtures()
        try stagedAssemblyReconcilesStateCounts()
        try stagedAssemblyPreservesRigIdentityAcrossCues()
        try validateAcceptsMultipleCuesAndRejectsEmpty()
        try multiCueDraftBuildsValidatedSequence()
        try stageStateSupportsCueStackAndGo()
        try disabledFixtureAssemblesDark()
        lightEffectEngineModulatesMovementAndIntensity()
        musicBeatClockGridIsCorrect()
        musicBeatSyncLocksEffectsToBeat()
        demoTrackSynthRendersBeatMatchedAudibleWav()
        try patchPlannerAssignsSequentialDMXAndBuildsSheet()
        parsesStageVoiceCommands()
        stageLightAccessibilityLabelsAreLocalized()
        try relightDebugSnapshotMapsCueFixtures()
        try relightDebugSnapshotResolvesManualOverrides()
        cueEditSupersedesMaskingOverride()
        parsesSingleLightCommands()
        parsesLightRotationCommands()
        resolvesLightOverridesOntoCueValues()
        rigPlacementSpreadsFixturesAcrossZone()
        try fixtureManualPositionOverridesZonePlacement()
        fixtureSupportPolicyClassifiesTrussVsStand()
        try surroundingsLightPolicyGatesOpaqueVenue()
        immersiveSceneReopenPolicyBacksOffThenGivesUp()
        try humanoidFigurePlanIsAnatomicallyOrdered()
        aiComposerPlacementClampsWithinReach()
        await unavailableLightingServiceReportsUnavailable()
        try await openAIServiceDecodesAndValidates()
        await openAIServiceSurfacesRefusal()
        await openAIServiceRejectsOutOfRangeViaValidator()
        try await fallbackServiceFallsBackWhenPrimaryThrows()
        songAnalysisMakeBeatClockCoversThreePaths()
        try songAnalysisRoundTripsAndMeasuresSectionDuration()
        showPlanProducesBoundedCuesWithRanges()
        showPlanMergesShortSectionsAndPadsEmpty()
        try rigConstraintClampsRemapsAndIsIdempotent()
        try musicShowBuilderBuildsValidatedSymmetricShow()
        try musicShowLasersAreMirroredLeftAndRight()
        try laserFixturesAreForcedOntoTheTruss()
        try legacyProjectJSONDecodesToUnconstrainedRig()
        await songLibraryLoopbackBrowsesAndResolves()
        print("LumaStageCoreSmokeTests passed")
    }

    private static func validatesDemoLookDefaults() throws {
        let look = LightingLook.mvpDemo()

        expect(look.ambient.preset == .standardNight, "MVP ambient must stay standardNight")
        expect(look.cues.map(\.name) == ["Opening", "Highlight"], "MVP must expose Opening and Highlight cues")
        expect(look.selectedCueId == "cue_opening", "Opening should be the default selected cue")
        try look.validate()
    }

    private static func defaultProjectsShipPlayableShowcase() throws {
        let projects = LumaStageProject.defaultProjects()

        // The app now opens on a ready-to-play default design (the showcase show) instead of an empty
        // home, so this guards that the shipped default exists and is a valid, playable look.
        expect(!projects.isEmpty, "App should open on a ready-to-play default project, not an empty home")
        let showcase = projects.first
        expect(showcase?.id == "project_dance_showcase", "the default project is the showcase show")
        expect((showcase?.lightingLook.cues.count ?? 0) >= 2, "a playable show ships at least Opening + Highlight cues")
        try showcase?.lightingLook.validate()
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

    private static func laserBeamMathDerivesCoreAndSheathLayers() {
        // Visibility gate: shared with the beam geometry so both layers vanish together.
        expect(!LaserScatterMath.beamsVisible(0.02), "A near-dark laser must be gated off")
        expect(!LaserScatterMath.beamsVisible(0.03), "The gate stays exclusive at 0.03 (matches the legacy > 0.03)")
        expect(LaserScatterMath.beamsVisible(0.5), "A lit laser must be visible")

        // Layer geometry: the glow sheath is wider than the thin core (the haze-particle layer was removed).
        let coreRadius = 0.01
        let sheathRadius = LaserScatterMath.sheathRadius(coreRadiusMeters: coreRadius)
        expect(sheathRadius > coreRadius, "The glow sheath must be wider than the core")

        // The core is hotter (whiter) than the raw hue; the sheath stays saturated.
        let core = LaserScatterMath.coreRGBA(hex: "#FF0000", intensity: 1)
        expect(core.green > 0 && core.blue > 0, "The white-hot core must lift the non-hue channels toward white")
        expect(core.red >= core.green, "The core must still lean toward its hue (red dominant for a red laser)")
        let sheath = LaserScatterMath.sheathRGBA(hex: "#FF0000", intensity: 1)
        expect(sheath.green < 0.0001 && sheath.blue < 0.0001, "The sheath must keep the saturated hue")

        // Sheath alpha is low and scales with intensity.
        expect(sheath.alpha < 0.2, "The sheath alpha must stay low so it reads as a halo, not a solid tube")
        expect(LaserScatterMath.sheathRGBA(hex: "#FF0000", intensity: 0.5).alpha < sheath.alpha,
               "A dimmer cue must give a fainter sheath")

        // Determinism + invalid-hex fallback to white.
        expect(LaserScatterMath.coreRGBA(hex: "#3366FF", intensity: 0.7) == LaserScatterMath.coreRGBA(hex: "#3366FF", intensity: 0.7),
               "Same inputs must be deterministic")
        let bogus = LaserScatterMath.sheathRGBA(hex: "not-a-hex", intensity: 1)
        let white = LaserScatterMath.sheathRGBA(hex: "#FFFFFF", intensity: 1)
        expect(bogus == white, "An invalid hex must fall back to white")
    }

    // 規定：雷射只能掛在上舞台桁架上。驗證 (1) `enforcingTrussMountedLasers` 把落地/側台的雷射 zone 正規化
    // 為 .stageBack；(2) 被拖到低處/下舞台的雷射經 `RigPlacement` 解析後仍必定吊掛在桁架（永不落地）。
    private static func laserFixturesAreForcedOntoTheTruss() throws {
        let layout = StageLayout.defaultStudentOutdoor()

        // Simulate an AI/edit mistake: force every laser into a floor-of-house zone, then normalize.
        var look = LightingLook.showcaseDemo()
        for cueIndex in look.cues.indices {
            for fixtureIndex in look.cues[cueIndex].fixtureGroups.indices
            where look.cues[cueIndex].fixtureGroups[fixtureIndex].renderModel == .laser {
                look.cues[cueIndex].fixtureGroups[fixtureIndex].zone = .stageFront
            }
        }
        let enforced = look.enforcingTrussMountedLasers()
        var sawLaser = false
        for cue in enforced.cues {
            for fixture in cue.fixtureGroups where fixture.renderModel == .laser {
                sawLaser = true
                expect(fixture.zone == .stageBack, "A laser must be normalized onto the upstage truss zone")
            }
        }
        expect(sawLaser, "showcaseDemo must contain a laser to exercise the rule")

        // Predicate: only the laser is truss-only.
        expect(RigPlacement.mountsOnTrussOnly(.laser), "A laser is truss-only")
        expect(!RigPlacement.mountsOnTrussOnly(.movingHeadBeam), "A moving head is not truss-only")

        // A laser dragged to a low, downstage spot must resolve back onto the truss (hang, never a stand).
        let laser = try expectUnwrapped(
            enforced.cues.first?.fixtureGroups.first(where: { $0.renderModel == .laser }),
            "showcaseDemo must contain a laser"
        )
        var dragged = laser
        dragged.manualPosition = FixturePosition(x: 99, y: 0.4, z: 9) // way off the truss, near the floor
        let placement = RigPlacement.resolvedPlacement(fixture: dragged, slot: 0, count: 1, layout: layout)
        expect(RigPlacement.support(forPosition: placement.position, layout: layout) == .hangFromTruss,
               "A dragged laser must still hang from the truss, never grow a floor stand")

        // Directly pin resolvedPlacement's zone-forcing branch (manualPosition == nil): a laser with a
        // stale non-back zone (legacy/un-normalized) must STILL resolve onto the truss — independent of
        // the manual-position clamp path above.
        var staleZoneLaser = laser
        staleZoneLaser.zone = .stageFront
        staleZoneLaser.manualPosition = nil
        let stalePlacement = RigPlacement.resolvedPlacement(fixture: staleZoneLaser, slot: 0, count: 1, layout: layout)
        expect(RigPlacement.support(forPosition: stalePlacement.position, layout: layout) == .hangFromTruss,
               "A laser with no manual position must resolve onto the truss even if its stored zone is wrong")

        // A non-laser fixture with the same off-truss manual position is free to stand on the floor.
        var standingPar = laser
        standingPar.model = .ledPar
        standingPar.manualPosition = FixturePosition(x: 99, y: 0.4, z: 9)
        let parPlacement = RigPlacement.resolvedPlacement(fixture: standingPar, slot: 0, count: 1, layout: layout)
        expect(parPlacement.position.z > placement.position.z,
               "A non-laser keeps its off-truss manual position (only lasers are clamped onto the truss)")
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

    private static func projectCreationOffersTemplatesWithBlankOption() {
        let templates = ProjectCreationTemplate.allTemplates

        expect(templates.count == 2, "Project creation should offer the student-activity template plus a blank option")
        expect(templates.first?.kind == .emptyStage, "The blank stage should lead the template list (start-from-scratch first)")
        expect(templates.contains(where: { $0.kind == .campusMusic }), "Project creation should keep the campus music night scenario template")
        expect(ProjectCreationTemplate.Kind.allCases.count == 2, "campusMusic and emptyStage should be the project template kinds")
        expect(templates.first(where: { $0.kind == .emptyStage })?.visualStyle == .emptyStage, "The blank template should use the empty-stage preview style")
        expect(templates.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty }, "Every project template should have labels")
        expect(templates.allSatisfy { !$0.introduction.isEmpty }, "Every project template should include an intro paragraph")
    }

    private static func projectFactoryCreatesBlankStageProject() throws {
        let project = LumaStageProject.newProject(index: 3, template: .emptyStage)

        expect(project.name == "空白舞台 3", "The blank template should name new projects from its label")
        expect(project.eventType == "自訂", "The blank template should use a custom event type")
        try project.stageLayout.validate()
        try project.lightingLook.validate()

        let allWhite = project.lightingLook.cues.allSatisfy { cue in
            cue.fixtureGroups.allSatisfy { $0.color.value == "#FFFFFF" }
        }
        expect(allWhite, "The blank look should be neutral white with no color theme")
        expect(!project.lightingLook.cues.contains(where: { $0.fixtureGroups.contains(where: { $0.model == .laser }) }),
               "The blank look should not include a laser or accent fixtures")
    }

    private static func projectFactoryAppliesScenarioTemplate() throws {
        let project = LumaStageProject.newProject(index: 2, template: .campusMusic)

        expect(project.name == "校園音樂之夜 2", "Scenario templates should name new projects from the selected context")
        expect(project.eventType == "學生表演", "Scenario templates should apply their event type")
        expect(project.lightingLook.mood.contains("溫暖"), "Scenario templates should apply a matching lighting mood")
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

    private static func nativeGlassDesignUsesSystemRadiusHierarchy() {
        // The visionOS-native glass language layers three radii: floating panels (largest),
        // nested glass surfaces, then small repeated cards. Keep that hierarchy intact so
        // glass-on-glass reads cleanly instead of using one flat custom radius everywhere.
        expect(LumaStageDesign.panelRadius > LumaStageDesign.surfaceRadius, "Floating glass panels should use a larger system-style radius than nested surfaces")
        expect(LumaStageDesign.surfaceRadius > LumaStageDesign.cornerRadius, "Nested glass surfaces should use a softer radius than small repeated cards")
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
        // Derive the upstage truss Z from the layout so this stays correct if the default deck depth
        // changes (a deeper deck moves its back edge, which is what `connectorLayer` keys off).
        let upstageZ = layout.objects.flatMap(\.trussEndpoints).map(\.z).min() ?? -1.25
        let backConnector = Vector3Meters(x: -2, y: 0, z: upstageZ)
        expect(
            StageBuilderRenderOrder.connectorLayer(position: backConnector, stageBase: stageBase) == .behindStageBase,
            "Connector blocks behind the stage should render before the stage base"
        )
        expect(
            !StageBuilderRenderOrder.shouldRenderConnectorBlock(TrussConnectorBlock(id: "hidden", position: backConnector, size: 0.34), stageBase: stageBase),
            "Connector blocks behind and below the stage top should be hidden by the stage base"
        )

        let verticalFoot = TrussVisualMember(
            start: Vector3Meters(x: -2, y: 0, z: upstageZ),
            end: Vector3Meters(x: -2, y: 2, z: upstageZ)
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

    private static func tallTrussPortalBuildsLegsToFullHeight() throws {
        // Pins the multi-segment vertical-leg tiling for tall portals (the 5m student-stage truss).
        // A regression that stops the legs short would leave a floating top beam, so assert the legs
        // tile contiguously from the ground all the way up to the top beam.
        let objects = StageLayout.trussPortalPreset(.portal6x5)
        let truss = objects.filter { $0.type == .trussSegment }

        // 6m x 5m portal: each leg tiles 2m + 2m + 1m (3 segments), top beam = three 2m beams → 9 total.
        expect(truss.count == 9, "6m x 5m portal should be built from nine truss segments (3 per leg + 3 top)")

        // Each vertical leg tiles contiguously from the ground (y = 0, 2, 4) with no gap, capped by a
        // 1m piece so it reaches 5m exactly.
        for side in ["left", "right"] {
            let legYs = truss.filter { $0.id.contains("_\(side)_leg_") }.map(\.position.y).sorted()
            expect(legYs == [0, 2, 4], "\(side) leg should stack segments at y = 0, 2, 4 with no vertical gap")
            let cap = truss.first { $0.id.contains("_\(side)_leg_") && abs($0.position.y - 4) < 0.0001 }
            expect(cap?.assetId == .truss1m, "\(side) leg should be capped by a 1m segment so it reaches 5m exactly")
        }

        // The top beam sits at the full 5m height and the highest truss endpoint reaches 5m — the legs
        // meet the top beam with no floating gap.
        let topBeamYs = truss.filter { $0.id.contains("_top_") }.map(\.position.y)
        expect(!topBeamYs.isEmpty && topBeamYs.allSatisfy { abs($0 - 5) < 0.0001 }, "Top beam should sit at the 5m portal height")
        let maxEndpointY = objects.flatMap(\.trussEndpoints).map(\.y).max() ?? 0
        expect(abs(maxEndpointY - 5) < 0.0001, "Tall portal truss should reach exactly 5m at its top")

        // The student-stage default inherits the 5m portal.
        let defaultMaxY = StageLayout.defaultStudentOutdoor().objects.flatMap(\.trussEndpoints).map(\.y).max() ?? 0
        expect(abs(defaultMaxY - 5) < 0.0001, "defaultStudentOutdoor should rig its truss at 5m")

        var tallLayout = StageLayout.empty(name: "Tall Portal Test")
        for object in objects {
            try tallLayout.addObject(object)
        }
        try tallLayout.validate()
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
        let models = Set(catalog.map(\.visualModel))

        expect(catalog.count == 10, "Fixture guide should cover the four role fixtures plus the six real-world products")
        expect(roles == Set(FixtureRole.allCases), "Fixture guide should still cover every cue fixture role")
        let products: Set<LightingFixtureVisualModel> = [.ledStrobeBar, .movingHeadBeam, .ledPar, .audienceBlinder, .ledFresnel, .laser]
        expect(products.isSubset(of: models), "Fixture guide should include the six real-world product fixtures")
        expect(models == Set(LightingFixtureVisualModel.allCases), "Every visual model should map to exactly one catalog entry")
        expect(catalog.allSatisfy { !$0.displayName.isEmpty }, "Every fixture should have a display name")
        expect(catalog.allSatisfy { !$0.shortDescription.isEmpty }, "Every fixture should explain what the fixture does")
        expect(catalog.allSatisfy { !$0.beginnerPromptHint.isEmpty }, "Every fixture should teach users how to ask AI for the fixture")
        expect(catalog.allSatisfy { !$0.useCase.isEmpty }, "Every fixture should describe a use case (shown on the info card)")
        expect(catalog.allSatisfy { !$0.englishName.isEmpty }, "Every fixture should have an English name")
        expect(Set(catalog.map(\.visualModel)).count == catalog.count, "Each fixture should have a distinct model (the catalog id)")
        expect(catalog.allSatisfy { $0.previewTechnology == .sceneKit3D }, "Fixture previews should use real 3D SceneKit models, not flat SwiftUI drawings")
    }

    private static func fixtureCarouselPagesAndWraps() {
        let models = LightingFixtureCatalog.carouselModels
        expect(models == LightingFixtureCatalog.allFixtures.map(\.visualModel), "Carousel order should follow the catalog order")
        expect(models.count == 10, "Carousel should page through all ten catalog fixtures")

        var carousel = FixtureCarousel(startAt: .movingHeadBeam)
        expect(carousel.current == .movingHeadBeam, "Carousel should start at the tapped fixture model")
        expect(carousel.currentItem?.visualModel == .movingHeadBeam, "currentItem should resolve to the current model")

        let defaulted = FixtureCarousel(models: models, startAt: nil)
        expect(defaulted.current == models.first, "Carousel should default to the first model when no start is given")

        carousel.select(model: models.first!)
        expect(carousel.current == models.first, "Selecting a model should jump the carousel to it")

        carousel.advance(by: -1)
        expect(carousel.current == models.last, "Paging left from the first model should wrap to the last")

        carousel.advance(by: 1)
        expect(carousel.current == models.first, "Paging right from the last model should wrap to the first")

        var loop = FixtureCarousel(models: models, startAt: models.first)
        loop.advance(by: models.count)
        expect(loop.current == models.first, "Advancing a full loop should return to the start")

        var unknown = FixtureCarousel(models: models, startAt: models.first)
        unknown.select(model: .ledPar)
        let before = unknown.current
        unknown.select(model: .ledPar)
        expect(unknown.current == before, "Selecting the same model should be a stable no-op")
        expect(FixtureCarousel(models: [], startAt: nil).models == models, "An empty model list should fall back to the full catalog order")
    }

    private static func lumaSyncProtocolRoundTrips() throws {
        // Every iPad <-> Apple Vision Pro message must survive a JSON round trip unchanged — both ends
        // share this Foundation-only schema and only ever encode/decode `LumaSyncMessage`.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        func roundTrip(_ message: LumaSyncMessage) throws {
            let data = try encoder.encode(message)
            let decoded = try decoder.decode(LumaSyncMessage.self, from: data)
            expect(decoded == message, "LumaSyncMessage should survive a JSON round trip")
        }

        let conversation = LumaConversationState(
            phase: "interpreting",
            statusText: "On-device",
            liveTranscript: "make it warmer",
            messages: [
                LumaChatMessage(id: "m1", sender: .user, text: "make it warmer", timestamp: 1.0),
                LumaChatMessage(id: "m2", sender: .model, text: "Raised the front warmth.", timestamp: 2.0)
            ],
            lastError: nil
        )
        let look = LightingLook.mvpDemo()

        try roundTrip(.hello(role: .iPadPanel))
        try roundTrip(.hostState(LumaHostState(conversation: conversation, lighting: look, immersionMode: "fullStage")))
        try roundTrip(.conversation(conversation))
        try roundTrip(.lighting(look))
        try roundTrip(.control(.selectCue(id: "cue_highlight")))
        try roundTrip(.control(.setFrontLightDimmer(0.6)))
        try roundTrip(.control(.setBackgroundWashColor(hex: "#3366FF")))
        try roundTrip(.control(.setFixtureIntensity(fixtureId: "front_light", intensity: 0.8)))
        try roundTrip(.control(.setFixtureColor(fixtureId: "background_wash", hex: "#0044AA")))
        try roundTrip(.control(.setFixtureFineControl(fixtureId: "front_light", control: .default(role: .frontLight, zone: .stageFront))))
        try roundTrip(.control(.resetSelectedCue))
        try roundTrip(.control(.generate(prompt: "sunset mood")))
        try roundTrip(.control(.goToNextCue))
        try roundTrip(.control(.goToPreviousCue))
        try roundTrip(.control(.appendCue))
        try roundTrip(.control(.removeCue(id: "cue_highlight")))
        try roundTrip(.control(.setGroupMaster(groupId: "group_front", level: 0.5)))
        try roundTrip(.control(.bumpGroup(groupId: "group_movers", on: true)))

        for role in LumaPeerRole.allCases {
            try roundTrip(.hello(role: role))
        }
        expect(LumaConversationState.empty.messages.isEmpty, "Empty conversation default should carry no messages")
    }

    // MARK: - SPEC 08: group submasters

    /// A small rig exercising each `StandardFixtureGroup` predicate (role / zone / render model).
    private static func groupTestCue() -> LightingCue {
        func fixture(_ id: String, role: FixtureRole, zone: StageZone, model: LightingFixtureVisualModel?) -> FixtureGroup {
            FixtureGroup(id: id, name: id, role: role, zone: zone, enabled: true,
                         intensity: 0.8, color: FixtureColor(mode: .rgb, value: "#FFFFFF"), model: model)
        }
        return LightingCue(
            id: "cue_opening",
            name: "Opening",
            transition: .mvpDefault,
            fixtureGroups: [
                fixture("f_front", role: .frontLight, zone: .stageFront, model: .frontFresnel),
                fixture("f_back", role: .backgroundWash, zone: .stageBack, model: .backgroundBatten),
                fixture("f_mover", role: .spot, zone: .stageBack, model: .movingHeadBeam),
                fixture("f_par", role: .wash, zone: .stageLeft, model: .ledPar)
            ]
        )
    }

    /// Groups are auto-derived from each fixture's role / zone / render model — no authored schema. An
    /// empty group is omitted so the panel never shows a fader that controls nothing.
    private static func groupAutoSeedFromRoleZone() throws {
        let groups = FixtureGroupMask.autoSeed(from: groupTestCue())
        func members(_ id: String) -> [String]? { groups.first { $0.id == id }?.members }

        expect(members("group_front") == ["f_front"], "前光 = front-role / stageFront fixtures")
        expect(members("group_backgroundWash") == ["f_back"], "背景洗 = backgroundWash-role fixtures")
        expect(members("group_upstage") == ["f_back", "f_mover"], "上舞台 = every stageBack fixture, in cue order")
        expect(members("group_movers") == ["f_mover"], "動態 = moving heads / lasers / strobes by render model")
        expect(members("group_all")?.count == 4, "全部 = the whole rig")

        // A rig with no effect fixtures omits the 動態 group entirely.
        let calm = LightingCue(id: "c", name: "Opening", transition: .mvpDefault,
                               fixtureGroups: [groupTestCue().fixtureGroups[0]])
        expect(FixtureGroupMask.autoSeed(from: calm).contains { $0.id == "group_movers" } == false,
               "An empty group is omitted from the seed")
    }

    /// The SPEC 08 load invariant: `final = isOff ? 0 : (override.intensity ?? cueIntensity × groupMaster)`,
    /// per-light override beats the master, colour is master-independent, and multi-group membership takes
    /// the HTP (highest) of the ridden submasters (default 1.0).
    private static func groupMasterResolutionAndPrecedence() {
        let groups = FixtureGroupMask.autoSeed(from: groupTestCue())
        func master(_ id: String, _ masters: [String: Double]) -> Double {
            FixtureGroupMask.effectiveMaster(forFixtureId: id, groups: groups, masters: masters)
        }
        func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

        // Master scales a light with no explicit intensity override.
        let mFront = master("f_front", ["group_front": 0.5])
        expect(approx(mFront, 0.5), "front master rides at 0.5")
        let scaled = LightOverride().resolved(cueColor: "#FFFFFF", cueIntensity: 0.8, groupMaster: mFront)
        expect(approx(scaled.intensity, 0.4), "cueIntensity × master = 0.8 × 0.5 = 0.4")

        // An explicit per-light intensity override beats the master (channel beats submaster).
        var withLevel = LightOverride(); withLevel.intensity = 0.9
        expect(approx(withLevel.resolved(cueColor: "#FFFFFF", cueIntensity: 0.8, groupMaster: 0.5).intensity, 0.9),
               "explicit per-light intensity wins over the group master")

        // isOff forces 0 regardless of the master.
        var off = LightOverride(); off.isOff = true
        expect(approx(off.resolved(cueColor: "#FFFFFF", cueIntensity: 0.8, groupMaster: 0.5).intensity, 0),
               "isOff blacks the light out regardless of master")

        // A colour override applies and is unaffected by the master; intensity still scales.
        var coloured = LightOverride(); coloured.colorHex = "#FF0000"
        let c = coloured.resolved(cueColor: "#FFFFFF", cueIntensity: 0.8, groupMaster: 0.5)
        expect(c.color == "#FF0000", "colour override applies and the master does not touch colour")
        expect(approx(c.intensity, 0.4), "intensity still scales by the master under a colour-only override")

        // Multi-group membership: HTP (highest) of the ridden submasters.
        let mMover = master("f_mover", ["group_upstage": 0.3, "group_movers": 0.9])
        expect(approx(mMover, 0.9), "a fixture in several ridden groups takes the highest (HTP)")

        // A fixture whose groups are untouched defaults to 1.0 (parked submaster doesn't pull it down).
        expect(approx(master("f_par", ["group_front": 0.5]), 1.0), "an unridden fixture defaults to master 1.0")
    }

    private static func loopbackTransportDeliversMessages() {
        // The transport contract: a message sent on one end arrives, intact, on the other; sends after
        // stop are dropped. Pinned on the in-process LoopbackSyncTransport so it holds without a device.
        let host = LoopbackSyncTransport()
        let panel = LoopbackSyncTransport()

        var panelReceived: [LumaSyncMessage] = []
        panel.onReceive = { panelReceived.append($0) }

        host.connect(to: panel)
        expect(host.connectionState == .connected && panel.connectionState == .connected,
               "Paired loopback transports should both report connected")

        host.send(.control(.setFrontLightDimmer(0.5)))
        host.send(.lighting(.mvpDemo()))
        expect(panelReceived.count == 2, "Panel should receive both messages the host sent")
        expect(panelReceived.first == .control(.setFrontLightDimmer(0.5)),
               "The first message should arrive intact through the codec")

        // Bidirectional: panel -> host.
        var hostReceived: [LumaSyncMessage] = []
        host.onReceive = { hostReceived.append($0) }
        panel.send(.hello(role: .iPadPanel))
        expect(hostReceived == [.hello(role: .iPadPanel)], "Host should receive the panel's hello")

        // After stop, sends are dropped (no crash, no delivery).
        host.stop()
        expect(host.connectionState == .disconnected, "Stopping should disconnect the transport")
        host.send(.control(.resetSelectedCue))
        expect(panelReceived.count == 2, "Sends after stop should be dropped")
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

    // BUG 6: a role-named recolor (CuePatch.roleColor) recolors EVERY matching-role fixture in the
    // SELECTED cue only — never the other cue, never a regeneration — and bad hex throws.
    private static func roleColorPatchRecolorsEveryMatchingFixtureInSelectedCueOnly() throws {
        // showcaseDemo has TWO frontLight fixtures (key_l, key_r), so a plural recolor is observable.
        var state = StageState(lightingLook: .showcaseDemo())
        state.selectedCueId = "cue_opening"

        let frontCountOpening = try state.lightingLook.requireCue(id: "cue_opening").fixtureGroups.filter { $0.role == .frontLight }.count
        expect(frontCountOpening >= 2, "showcaseDemo opening should have ≥2 front lights for a meaningful plural recolor")

        try state.patchSelectedCue(.roleColor(role: .frontLight, hexColor: "#FF0000"))

        let opening = try state.lightingLook.requireCue(id: "cue_opening")
        let openingFronts = opening.fixtureGroups.filter { $0.role == .frontLight }
        expect(openingFronts.allSatisfy { $0.color.value == "#FF0000" }, "every front light in the selected cue must be recolored")
        // Non-front fixtures in the selected cue are untouched.
        expect(opening.fixtureGroups.contains { $0.role != .frontLight && $0.color.value != "#FF0000" },
               "non-matching roles in the selected cue must be untouched")

        // The OTHER cue's front lights must NOT change (single-cue invariant).
        let highlight = try state.lightingLook.requireCue(id: "cue_highlight")
        expect(highlight.fixtureGroups.contains { $0.role == .frontLight && $0.color.value != "#FF0000" },
               "the unselected cue's front lights must be untouched")

        // Bad hex throws.
        expectThrows(ValidationError.invalidHexColor("notacolor")) {
            try state.patchSelectedCue(.roleColor(role: .frontLight, hexColor: "notacolor"))
        }

        // FixtureRole.displayName is the 繁中 name the command feedback uses.
        expect(FixtureRole.frontLight.displayName == "前光", "FixtureRole.frontLight.displayName should be 前光")
        expect(FixtureRole.backgroundWash.displayName == "背景光", "FixtureRole.backgroundWash.displayName should be 背景光")
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
        expect(openingSideWash.gobo == .stripes, "Every rig fixture renders now, so a wash fixture keeps its gobo through assembly")

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

    // SPEC 01: an AI-authored `effect` on a draft fixture must survive assembly into the look's
    // `FixtureGroup`, round-trip through Codable, and decode to nil from JSON written before `effect`
    // existed (additive + back-compat).
    private static func aiEffectFlowsThroughDraftAndSurvivesCodec() throws {
        let sweep = LightEffect(kind: .panSweep, speedHz: 0.5, sizeDegrees: 26, phase: 0.2)
        let draft = LightingLookDraft(
            lookName: "Moving Beams",
            mood: "energetic, kinetic",
            openingFixtures: [
                LightingLookDraft.Fixture(id: "beam_l", name: "Beam L", role: .spot, zone: .stageLeft, enabled: true, intensity: 0.7, colorHex: "#3A6BFF", model: .movingHeadBeam, effect: sweep),
                LightingLookDraft.Fixture(id: "front", name: "Front", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.6, colorHex: "#FFD1A3")
            ],
            highlightFixtures: [
                LightingLookDraft.Fixture(id: "beam_l", name: "Beam L", role: .spot, zone: .stageLeft, enabled: true, intensity: 0.9, colorHex: "#1E4FE0", model: .movingHeadBeam, effect: sweep),
                LightingLookDraft.Fixture(id: "front", name: "Front", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.8, colorHex: "#FFE0B8")
            ],
            explanationTerm: "Movement",
            explanationPlainText: "Moving beams sweep through the air to add energy.",
            explanationActionSummary: "Added a sweeping moving-head beam for the highlight."
        )

        let look = try draft.makeValidatedLook()
        try look.validate()
        let opening = try look.requireCue(id: "cue_opening")
        let beam = opening.fixtureGroups.first { $0.id == "beam_l" }
        let front = opening.fixtureGroups.first { $0.id == "front" }
        expect(beam?.effect == sweep, "An authored effect should land on the assembled fixture")
        expect(front?.effect == nil, "A fixture without an authored effect should stay nil through assembly")

        // Codable: a fixture round-trips its effect.
        let fixture = FixtureGroup(id: "f", name: "F", role: .spot, zone: .stageLeft, enabled: true, intensity: 0.5, color: FixtureColor(mode: .rgb, value: "#FFFFFF"), effect: sweep)
        let encoded = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(FixtureGroup.self, from: encoded)
        expect(decoded.effect == sweep, "FixtureGroup effect should survive a Codable round-trip")

        // Backward compatibility: JSON written before `effect` existed must decode with effect == nil.
        let legacyEffectJSON = Data("""
        {"id":"legacy","name":"Legacy","role":"frontLight","zone":"stageFront","enabled":true,"intensity":0.5,"color":{"mode":"rgb","value":"#FFFFFF"}}
        """.utf8)
        let legacyEffect = try JSONDecoder().decode(FixtureGroup.self, from: legacyEffectJSON)
        expect(legacyEffect.effect == nil, "Legacy fixtures without an effect field should decode to nil")
    }

    // SPEC 03 (AI 燈光導師): a teaching `rationale` carried on a draft must survive assembly into the
    // look's `LightingExplanation`, and old JSON written before `rationale` existed must decode to ""
    // (additive + back-compat).
    private static func explanationRationaleFlowsThroughDraftAndIsBackCompat() throws {
        let rationale = "前光暖以塑造表演者膚色，背景偏冷拉開空間層次，靠冷暖對比建立深度。"

        // 1. A non-empty rationale on the two-cue draft must be preserved after assembly.
        let draft = LightingLookDraft(
            lookName: "Tutor Look",
            mood: "warm front, cool back",
            openingFixtures: [
                LightingLookDraft.Fixture(id: "front_light", name: "前光", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.6, colorHex: "#FFD1A3"),
                LightingLookDraft.Fixture(id: "background_wash", name: "背景泛光", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: 0.7, colorHex: "#4FA8FF")
            ],
            highlightFixtures: [
                LightingLookDraft.Fixture(id: "front_light", name: "前光", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.8, colorHex: "#FFE0B8"),
                LightingLookDraft.Fixture(id: "background_wash", name: "背景泛光", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: 0.9, colorHex: "#2F6BFF")
            ],
            explanationTerm: "對比",
            explanationPlainText: "冷暖對比讓表演者從背景中跳出。",
            explanationActionSummary: "已建立暖前光與冷背景的對比。",
            explanationRationale: rationale
        )
        let look = try draft.makeValidatedLook()
        expect(look.explanation.rationale == rationale, "A draft rationale must survive assembly into the look's explanation")

        // The multi-cue static path must carry the rationale through too.
        let multiCueLook = try LightingLookDraft.makeValidatedLook(
            lookName: "Tutor Multi",
            mood: "warm front, cool back",
            cues: [
                LightingLookDraft.Cue(id: "cue_0", name: "Opening", fixtures: [
                    LightingLookDraft.Fixture(id: "front_light", name: "前光", role: .frontLight, zone: .stageFront, enabled: true, intensity: 0.6, colorHex: "#FFD1A3"),
                    LightingLookDraft.Fixture(id: "background_wash", name: "背景泛光", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: 0.7, colorHex: "#4FA8FF")
                ])
            ],
            explanationTerm: "對比",
            explanationPlainText: "冷暖對比讓表演者從背景中跳出。",
            explanationActionSummary: "已建立暖前光與冷背景的對比。",
            explanationRationale: rationale
        )
        expect(multiCueLook.explanation.rationale == rationale, "The multi-cue path must carry the rationale into the look's explanation")

        // 2. Old JSON without a `rationale` key must decode to "".
        let legacyJSON = Data("""
        {"term":"對比","plainText":"冷暖對比讓表演者跳出。","actionSummary":"已建立對比。"}
        """.utf8)
        let legacy = try JSONDecoder().decode(LightingExplanation.self, from: legacyJSON)
        expect(legacy.rationale == "", "Old explanation JSON without a rationale key should decode to an empty string")
        expect(legacy.term == "對比", "Other explanation fields should still decode from legacy JSON")
    }

    // SPEC 01: `LightEffectPlan.effects(for:)` must return the AI-authored effect when a fixture has one,
    // and fall back to `LightEffect.suggested(...)` (the per-type deterministic default) when it does not.
    private static func lightEffectPlanPrefersAuthoredEffectOverSuggested() throws {
        let authored = LightEffect(kind: .circle, speedHz: 0.4, sizeDegrees: 22, phase: 0.0)
        // A high-energy cue (avg intensity >= threshold) so the un-authored fixtures get a non-none default.
        let cue = LightingCue(
            id: "cue_test",
            name: "Test",
            transition: .mvpDefault,
            fixtureGroups: [
                // Authored effect: should be returned verbatim regardless of energy/default.
                FixtureGroup(id: "authored", name: "Authored", role: .spot, zone: .stageLeft, enabled: true, intensity: 0.9, color: FixtureColor(mode: .rgb, value: "#FFFFFF"), model: .movingHeadBeam, effect: authored),
                // No authored effect: should fall back to the per-type suggested default.
                FixtureGroup(id: "fallback", name: "Fallback", role: .spot, zone: .stageRight, enabled: true, intensity: 0.9, color: FixtureColor(mode: .rgb, value: "#FFFFFF"), model: .movingHeadBeam)
            ]
        )

        let effects = LightEffectPlan.effects(for: cue)
        expect(effects.count == 2, "effects(for:) should return one effect per fixture")
        expect(effects[0] == authored, "An authored effect must be returned verbatim, not overwritten by the default")

        let expectedFallback = LightEffect.suggested(for: .movingHeadBeam, highEnergy: LightEffectPlan.isHighEnergy(cue), slot: 1)
        expect(effects[1] == expectedFallback, "A fixture without an authored effect must fall back to suggested(...)")
        expect(expectedFallback.kind != .none, "Sanity: the high-energy moving-head default should be animated, so the fallback differs from authored")
    }

    // The immersive scene relights ONLY the `.frontLight` and `.backgroundWash` roles, so a generated
    // look made of any other role would validate yet change nothing on screen. Generation maps each
    // cue through `RenderableCue`, which must force exactly those two roles — pin that here with the
    // same `requireFixture(role:)` call the renderer makes, so a regression fails loudly.
    private static func aiDraftGuaranteesRenderableFrontAndBackgroundFixtures() throws {
        let draft = LightingLookDraft(
            lookName: "Warm Opening",
            mood: "warm, then bold",
            opening: LightingLookDraft.RenderableCue(
                frontLightIntensity: 0.55,
                frontLightHex: "#FFCBA0",
                frontLightGobo: nil,
                backgroundWashIntensity: 0.4,
                backgroundWashHex: "#3A6BFF",
                backgroundWashGobo: .stars
            ),
            highlight: LightingLookDraft.RenderableCue(
                frontLightIntensity: 0.9,
                frontLightHex: "#FFE4C2",
                frontLightGobo: nil,
                backgroundWashIntensity: 0.95,
                backgroundWashHex: "#1E4FE0",
                backgroundWashGobo: nil
            ),
            explanationTerm: "Contrast",
            explanationPlainText: "Contrast is the brightness difference between the performer and the backdrop.",
            explanationActionSummary: "Brightened the front light and deepened the background wash for the highlight."
        )

        let look = try draft.makeValidatedLook()
        try look.validate()

        for cueId in ["cue_opening", "cue_highlight"] {
            let cue = try look.requireCue(id: cueId)
            // requireFixture throws if the role is missing — the exact call the renderer makes.
            _ = try cue.requireFixture(role: .frontLight)
            _ = try cue.requireFixture(role: .backgroundWash)
        }

        let openingFront = try look.requireCue(id: "cue_opening").requireFixture(role: .frontLight)
        expect(abs(openingFront.intensity - 0.55) < 0.0001, "Front light intensity should map into the Opening cue")
        expect(openingFront.color.value == "#FFCBA0", "Front light hex should normalize into the Opening cue")

        let openingBackground = try look.requireCue(id: "cue_opening").requireFixture(role: .backgroundWash)
        expect(openingBackground.gobo == .stars, "Background wash gobo should survive the renderable mapping")

        let highlightFront = try look.requireCue(id: "cue_highlight").requireFixture(role: .frontLight)
        expect(highlightFront.intensity > openingFront.intensity, "Highlight front light should be brighter than Opening")
    }

    // SPEC 14 (staged generation): the Foundation-only staged assembler joins a define-once rig with a
    // per-cue state MATRIX (row j → rig[j]). It must reconcile count drift exactly like `makeValidatedLook`
    // — a short row reuses its last entry, a long row truncates, and an empty row makes the whole cue dark
    // — and still produce a look that passes `validate()`.
    private static func stagedAssemblyReconcilesStateCounts() throws {
        let rig = [
            LightingLookDraft.RigFixture(id: "fixture_0", name: "Front L", role: .frontLight, zone: .stageFront, model: .frontFresnel),
            LightingLookDraft.RigFixture(id: "fixture_1", name: "Wash", role: .backgroundWash, zone: .stageBack, model: .washBar),
            LightingLookDraft.RigFixture(id: "fixture_2", name: "Beam", role: .spot, zone: .stageBack, model: .movingHeadBeam)
        ]

        let cueStates: [[LightingLookDraft.StagedState]] = [
            // Short row: 2 states for 3 fixtures → the 3rd reuses the last (the wash's #2244FF entry).
            [
                LightingLookDraft.StagedState(enabled: true, intensity: 0.6, colorHex: "#FFD1A3"),
                LightingLookDraft.StagedState(enabled: true, intensity: 0.7, colorHex: "#2244FF")
            ],
            // Long row: 5 states for 3 fixtures → the extra two are ignored.
            [
                LightingLookDraft.StagedState(enabled: true, intensity: 0.9, colorHex: "#FF3300"),
                LightingLookDraft.StagedState(enabled: true, intensity: 0.8, colorHex: "#00FF88"),
                LightingLookDraft.StagedState(enabled: true, intensity: 0.5, colorHex: "#8800FF"),
                LightingLookDraft.StagedState(enabled: false, intensity: 0.2, colorHex: "#111111"),
                LightingLookDraft.StagedState(enabled: true, intensity: 0.1, colorHex: "#222222")
            ],
            // Empty row: whole cue dark (every fixture off).
            []
        ]

        let look = try LightingLookDraft.makeValidatedStagedLook(
            lookName: "Staged Show",
            mood: "warm → bold → blackout",
            rig: rig,
            cueNames: ["Opening", "Build", "Blackout"],
            cueStates: cueStates,
            explanationTerm: "Cue",
            explanationPlainText: "A cue is one saved state of the whole rig the operator steps through.",
            explanationActionSummary: "Built a three-cue staged show.",
            explanationRationale: "Escalating cues build a short arc."
        )
        try look.validate()

        expect(look.cues.count == 3, "Every cue name should produce a cue")
        expect(look.cues.allSatisfy { $0.fixtureGroups.count == rig.count },
               "Every cue must carry one fixture per rig fixture (count reconciled)")

        // Short row: fixture_2 reuses fixture_1's last state (the #2244FF wash entry).
        let opening = try look.requireCue(id: "cue_0")
        let openingBeam = opening.fixtureGroups.first { $0.id == "fixture_2" }
        expect(openingBeam?.color.value == "#2244FF", "A short state row must reuse the last entry for the trailing fixture")
        expect(abs((openingBeam?.intensity ?? -1) - 0.7) < 0.0001, "The reused entry must carry its intensity too")

        // Long row: only the first three states are used; extras dropped.
        let build = try look.requireCue(id: "cue_1")
        let buildThird = build.fixtureGroups.first { $0.id == "fixture_2" }
        expect(buildThird?.color.value == "#8800FF", "A long state row must map the 3rd entry to the 3rd fixture and ignore extras")

        // Empty row: whole cue dark — `enabled:false` assembles intensity 0.
        let blackout = try look.requireCue(id: "cue_2")
        expect(blackout.fixtureGroups.allSatisfy { $0.intensity == 0 },
               "An empty state row must make the whole cue dark (intensity 0)")
    }

    // SPEC 14: the rig is defined ONCE and reused in every cue, so fixture ids + order must be identical
    // across cues (rig identity), cue ids must be the pinned `cue_0…`, and `selectedCueId` must resolve.
    private static func stagedAssemblyPreservesRigIdentityAcrossCues() throws {
        let rig = [
            LightingLookDraft.RigFixture(id: "fixture_0", name: "A", role: .frontLight, zone: .stageFront, model: .frontFresnel),
            LightingLookDraft.RigFixture(id: "fixture_1", name: "B", role: .wash, zone: .stageLeft, model: .washBar),
            LightingLookDraft.RigFixture(id: "fixture_2", name: "C", role: .spot, zone: .stageRight, model: .movingHeadBeam),
            LightingLookDraft.RigFixture(id: "fixture_3", name: "D", role: .backgroundWash, zone: .stageBack, model: .backgroundBatten)
        ]

        func row(_ intensity: Double) -> [LightingLookDraft.StagedState] {
            rig.map { _ in LightingLookDraft.StagedState(enabled: true, intensity: intensity, colorHex: "#FFFFFF") }
        }

        let look = try LightingLookDraft.makeValidatedStagedLook(
            lookName: "Identity Show",
            mood: "steady",
            rig: rig,
            cueNames: ["Opening", "Build", "Chorus", "Finale"],
            cueStates: [row(0.3), row(0.5), row(0.7), row(0.9)],
            explanationTerm: "Rig",
            explanationPlainText: "The rig is the fixed set of fixtures the whole show is built from.",
            explanationActionSummary: "Built a four-cue show on a stable four-fixture rig.",
            explanationRationale: "A stable rig keeps each light addressable across every cue."
        )
        try look.validate()

        let expectedIds = ["fixture_0", "fixture_1", "fixture_2", "fixture_3"]
        expect(look.cues.count == 4, "Four cue names should produce four cues")
        expect(look.cues.map(\.id) == ["cue_0", "cue_1", "cue_2", "cue_3"], "Cue ids must be the pinned cue_0… sequence")
        for cue in look.cues {
            expect(cue.fixtureGroups.map(\.id) == expectedIds,
                   "Every cue must carry the same fixture ids in the same order (rig identity)")
        }
        _ = try look.requireCue(id: look.selectedCueId)
        expect(look.selectedCueId == "cue_0", "The first cue should be selected and resolve")
    }

    // The relight debug panel (toggled from the AI composer) renders `RelightDebugSnapshot`. Pin that
    // it mirrors the cue's fixtures and correctly flags which roles the immersive scene actually draws
    // — the same `isRenderedAsSpotlight` predicate that would have made the original "valid look that
    // renders nothing" bug obvious at a glance.
    private static func relightDebugSnapshotMapsCueFixtures() throws {
        expect(FixtureRole.frontLight.isRenderedAsSpotlight, "frontLight must be rendered on stage")
        expect(FixtureRole.backgroundWash.isRenderedAsSpotlight, "backgroundWash must be rendered on stage")
        expect(!FixtureRole.wash.isRenderedAsSpotlight, "wash is not rendered on stage")
        expect(!FixtureRole.spot.isRenderedAsSpotlight, "spot is not rendered on stage")

        let look = LightingLook.mvpDemo()
        let cue = try look.requireCue(id: look.selectedCueId)
        let snapshot = RelightDebugSnapshot.make(from: cue)

        expect(snapshot.cueId == cue.id, "snapshot should carry the cue id")
        expect(snapshot.rows.count == cue.fixtureGroups.count, "snapshot should have one row per fixture")
        // Each row carries its 1-based "Light N" number in cue order — the SAME numbering the on-stage
        // floating label, the voice/deterministic commands, and the iPad panel all use, so the debug row
        // can be cross-referenced to a command.
        expect(snapshot.rows.map(\.number) == Array(1...cue.fixtureGroups.count),
               "rows should carry 1-based Light N numbers in cue order")
        // The dynamic rig relights EVERY fixture now (`RelightDebugSnapshot.make` flags them all), so
        // renderedCount equals the fixture count — including non-spotlight roles like the laser's `.spot`.
        // (The `isRenderedAsSpotlight` predicate above is now vestigial metadata, not a render gate.)
        expect(snapshot.renderedCount == cue.fixtureGroups.count,
               "every fixture in the dynamic rig is rendered, so renderedCount equals the fixture count")

        let front = try cue.requireFixture(role: .frontLight)
        let frontRow = snapshot.rows.first(where: { $0.fixtureId == front.id })
        expect(frontRow?.hex == front.color.value, "row hex should mirror the fixture color")
        expect(frontRow?.intensityPercent == Int((front.intensity * 100).rounded()), "row intensity% should mirror the fixture")
        expect(frontRow?.isRendered == true, "the frontLight row should be flagged rendered")
        // With no manual overrides passed, rows resolve to the raw cue values and read as un-overridden.
        expect(snapshot.rows.allSatisfy { !$0.isOverridden && !$0.isManuallyOff },
               "with no overrides, no row should be flagged manual")

        // A1 dynamic effects surface in the snapshot via the shared LightEffectPlan, so the in-app debug
        // readout matches what the renderer animates. mvpDemo's opening averages ≥ 0.6 → high energy.
        expect(snapshot.isHighEnergy, "mvpDemo opening averages ≥ 0.6, so it reads as a high-energy cue")
        expect(snapshot.animatedCount >= 1, "a high-energy cue runs at least one fixture effect")
        expect(frontRow?.effectKind == LightEffectKind.none, "a front fresnel stays steady even on a high-energy cue")
        let laserRow = snapshot.rows.first(where: { $0.fixtureId == "laser_fan" })
        expect(laserRow?.effectKind == LightEffectKind.none, "the laser stays still — its visible aerial beam fan isn't animated — even on a high-energy cue")
    }

    // The debug panel must resolve the manual override + group-master layers exactly like the renderer, so
    // a hands-on edit (pinch/card/voice/fader ride) shows its EFFECTIVE value in 偵錯台 — not the raw cue
    // value (the "偵錯台 doesn't change when I adjust a light by gesture" bug).
    private static func relightDebugSnapshotResolvesManualOverrides() throws {
        let look = LightingLook.mvpDemo()
        let cue = try look.requireCue(id: look.selectedCueId)

        // Light 1 recoloured + dimmed by hand; Light 2 manually blacked out; Light 3 ridden by a group at 50%.
        let overrides: [Int: LightOverride] = [
            1: LightOverride(isOff: false, colorHex: "#FF0000", intensity: 0.2),
            2: LightOverride(isOff: true, colorHex: nil, intensity: nil)
        ]
        let masters: [Int: Double] = [3: 0.5]
        let snapshot = RelightDebugSnapshot.make(from: cue, overrides: overrides, groupMasters: masters)

        let row1 = snapshot.rows[0]
        expect(row1.hex == "#FF0000", "row 1 should show the manual override colour, not the cue colour")
        expect(row1.intensityPercent == 20, "row 1 should show the manual override intensity, not the cue value")
        expect(row1.isOverridden, "row 1 should be flagged as manually overridden")
        expect(!row1.isManuallyOff, "row 1 is dimmed by hand, not blacked out")

        let row2 = snapshot.rows[1]
        expect(row2.intensityPercent == 0, "a manually blacked-out light resolves to 0%")
        expect(row2.isManuallyOff, "row 2 should be flagged as manually off")

        let cue3Intensity = cue.fixtureGroups[2].intensity
        let row3 = snapshot.rows[2]
        expect(row3.intensityPercent == Int((cue3Intensity * 0.5 * 100).rounded()),
               "a group master ride should scale the row's intensity like the renderer")
        expect(row3.isOverridden, "a light pulled off 1.0 by a group ride should be flagged")
    }

    // An authoritative cue-layer edit (iPad panel / direct per-fixture edit) supersedes the matching
    // component of a light's manual override, so the new cue value renders instead of being masked by a
    // stale override — the "平板改變的內容沒有更新到燈光上" fix. (AppModel isn't in the smoke set, so pin
    // the Foundation-only `LightOverride.superseded` logic AppModel delegates to.)
    private static func cueEditSupersedesMaskingOverride() {
        let full = LightOverride(isOff: true, colorHex: "#00FF00", intensity: 0.9)

        // An intensity edit drops the manual level + blackout but keeps an unrelated colour override.
        let afterIntensity = full.superseded(clearing: .intensity)
        expect(afterIntensity?.intensity == nil, "an intensity edit should clear the manual level")
        expect(afterIntensity?.isOff == false, "an intensity edit should un-blackout the light")
        expect(afterIntensity?.colorHex == "#00FF00", "an intensity edit should keep an unrelated colour override")

        // A colour edit drops the manual colour but keeps an unrelated intensity/blackout override.
        let afterColor = full.superseded(clearing: .color)
        expect(afterColor?.colorHex == nil, "a colour edit should clear the manual colour")
        expect(afterColor?.intensity == 0.9, "a colour edit should keep an unrelated intensity override")
        expect(afterColor?.isOff == true, "a colour edit should not touch a blackout")

        // When the edited component was the ONLY thing the override carried, it drops entirely so the light
        // follows the cue again.
        let colorOnly = LightOverride(isOff: false, colorHex: "#0000FF", intensity: nil)
        expect(colorOnly.superseded(clearing: .color) == nil, "clearing the only component should drop the override")
        let intensityOnly = LightOverride(isOff: false, colorHex: nil, intensity: 0.3)
        expect(intensityOnly.superseded(clearing: .intensity) == nil, "clearing the only component should drop the override")
    }

    // Deterministic single-light command parsing (the Action-Phrase-style precise control layer):
    // "light N ..." phrases resolve to a command and bypass AI generation; phrases without a light
    // number (e.g. the generative "change the light to yellow") return nil and fall through to the AI.
    private static func parsesSingleLightCommands() {
        expect(LightCommand.parse("Close the Light 1") == .close(1), "close + light number should map to .close")
        expect(LightCommand.parse("turn off light 2") == .close(2), "turn off should close the light")
        expect(LightCommand.parse("light 3 off") == .close(3), "trailing off should close the light")
        expect(LightCommand.parse("open the light 3") == .open(3), "open should map to .open")
        expect(LightCommand.parse("turn on light 4") == .open(4), "turn on should open the light")

        expect(LightCommand.parse("set light 1 to blue") == .setColor(1, hex: "#0000FF"), "named color should map to hex")
        expect(LightCommand.parse("make light 2 red") == .setColor(2, hex: "#FF0000"), "make + color should set color")
        expect(LightCommand.parse("set light 2 to #1FBFB8") == .setColor(2, hex: "#1FBFB8"), "explicit hex should be accepted")

        expect(LightCommand.parse("dim light 2 to 30%") == .setIntensity(2, fraction: 0.3), "dim to % should set intensity")
        expect(LightCommand.parse("set light 1 to 50%") == .setIntensity(1, fraction: 0.5), "set to % should set intensity")
        expect(LightCommand.parse("light 4 brightness 20%") == .setIntensity(4, fraction: 0.2), "brightness % should set intensity")

        expect(LightCommand.parse("blackout") == .allOff, "blackout should turn all off")
        expect(LightCommand.parse("all lights on") == .resetAll, "all on should reset overrides")

        // No light number → generative path (the full-look commands), not a single-light command.
        expect(LightCommand.parse("Change the light to yellow") == nil, "a numberless 'the light' phrase is a full-look prompt, not single-light")
        expect(LightCommand.parse("make it warm and moody") == nil, "a design prompt should not parse as a light command")
        // The rig is dynamic, so parse accepts any light number ≥ 1; AppModel validates it against the
        // actual fixture count (and reports "there's no Light 9" if the scene is smaller).
        expect(LightCommand.parse("close the light 9") == .close(9), "any light number ≥ 1 parses; range is checked at apply time")

        // BUG 6: role-name + colour recolors that role's fixtures (targeted), NOT a full-look regeneration.
        // English role token + CJK colour, CJK role + CJK colour, and a numberless English phrase all map.
        expect(LightCommand.parse("把 Front Light 改成紅色") == .setRoleColor(.frontLight, hex: "#FF0000"),
               "English role token + CJK colour should map to .setRoleColor(.frontLight, red)")
        expect(LightCommand.parse("背景光改藍色") == .setRoleColor(.backgroundWash, hex: "#0000FF"),
               "CJK background role + CJK colour should map to .setRoleColor(.backgroundWash, blue)")
        expect(LightCommand.parse("前光改成綠色") == .setRoleColor(.frontLight, hex: "#00FF00"),
               "CJK front role + CJK colour should map to .setRoleColor(.frontLight, green)")
        expect(LightCommand.parse("change the front light to red") == .setRoleColor(.frontLight, hex: "#FF0000"),
               "numberless English role + colour should map to .setRoleColor, not fall through to AI")
        // Role-only phrase (no colour) must NOT false-match — it falls through to the AI/other paths.
        expect(LightCommand.parse("把前光調暗一點") == nil,
               "a role phrase with no colour must not parse as a role recolor")
    }

    // SPEC 13: "Light N turn right/left/up/down M degrees" parses to `.rotate` (one axis at a time), the
    // aim-offset clamp holds, and rotate must NOT eat "turn off"/"turn on" (no direction word → close/open).
    private static func parsesLightRotationCommands() {
        expect(LightCommand.parse("Light 6 turn right 60 degrees") == .rotate(6, panDeltaDegrees: 60, tiltDeltaDegrees: 0),
               "turn right N° should pan +N on the named light")
        expect(LightCommand.parse("turn light 2 left 45 degrees") == .rotate(2, panDeltaDegrees: -45, tiltDeltaDegrees: 0),
               "turn left N° should pan −N")
        expect(LightCommand.parse("tilt light 3 up 20 degrees") == .rotate(3, panDeltaDegrees: 0, tiltDeltaDegrees: 20),
               "tilt up N° should tilt +N")
        expect(LightCommand.parse("rotate light 4 down 30") == .rotate(4, panDeltaDegrees: 0, tiltDeltaDegrees: -30),
               "rotate down N (no 'degrees') should tilt −N")
        expect(LightCommand.parse("pan light 1 right") == .rotate(1, panDeltaDegrees: 45, tiltDeltaDegrees: 0),
               "a rotation with no magnitude should default to 45°")

        // Regression: on/off are not direction words, so a rotation verb ("turn") must not swallow them.
        expect(LightCommand.parse("turn off light 2") == .close(2), "rotate must not eat 'turn off'")
        expect(LightCommand.parse("turn on light 4") == .open(4), "rotate must not eat 'turn on'")

        // FixtureAimOffset.adding clamps to the valid range (pan ±180, tilt ±90).
        expect(FixtureAimOffset.zero.adding(panDelta: 200, tiltDelta: 0).panDegrees == 180, "pan clamps to 180")
        expect(FixtureAimOffset.zero.adding(panDelta: 0, tiltDelta: -200).tiltDegrees == -90, "tilt clamps to −90")
        expect(FixtureAimOffset.zero.adding(panDelta: -300, tiltDelta: 0).panDegrees == -180, "pan clamps to −180")

        // Old JSON with no `aimOffset` key decodes to nil (synthesized decoder defaults optionals to nil),
        // and a set aimOffset survives a Codable round-trip (mirrors the manualPosition back-compat test).
        let legacyJSON = """
        {"id":"f1","name":"燈具 1","role":"frontLight","zone":"stageFront",
         "enabled":true,"intensity":0.6,"color":{"mode":"rgb","value":"#FFFFFF"}}
        """
        let decoded = try! JSONDecoder().decode(FixtureGroup.self, from: Data(legacyJSON.utf8))
        expect(decoded.aimOffset == nil, "A FixtureGroup decoded from JSON without an aimOffset key must yield nil")

        var placed = decoded
        placed.aimOffset = FixtureAimOffset(panDegrees: 60, tiltDegrees: -12)
        let roundTripped = try! JSONDecoder().decode(FixtureGroup.self, from: try! JSONEncoder().encode(placed))
        expect(roundTripped.aimOffset == placed.aimOffset, "aimOffset must survive a Codable round-trip")
    }

    private static func resolvesLightOverridesOntoCueValues() {
        let cueColor = "#FFD1A3"
        let cueIntensity = 0.6

        let follow = LightOverride()
        expect(!follow.isActive, "an empty override should be inactive (follows the cue)")
        let f = follow.resolved(cueColor: cueColor, cueIntensity: cueIntensity)
        expect(f.color == cueColor && abs(f.intensity - cueIntensity) < 0.0001, "an empty override should pass the cue values through")

        var off = LightOverride(); off.isOff = true
        expect(off.isActive, "an off override should be active")
        expect(off.resolved(cueColor: cueColor, cueIntensity: cueIntensity).intensity == 0, "an off light should resolve to zero intensity")

        var colored = LightOverride(); colored.colorHex = "#0000FF"
        expect(colored.resolved(cueColor: cueColor, cueIntensity: cueIntensity).color == "#0000FF", "a color override should replace the cue color")
        expect(abs(colored.resolved(cueColor: cueColor, cueIntensity: cueIntensity).intensity - cueIntensity) < 0.0001, "a color-only override should keep the cue intensity")

        var dimmed = LightOverride(); dimmed.intensity = 0.25
        expect(abs(dimmed.resolved(cueColor: cueColor, cueIntensity: cueIntensity).intensity - 0.25) < 0.0001, "an intensity override should replace the cue intensity")
    }

    // Dynamic rig placement: many fixtures in one zone spread evenly across the stage, and zones sit in
    // distinct places (FOH downstage in the audience, upstage on the truss). Pins the Foundation math the
    // dynamic renderer uses so an N-fixture scene places correctly without a simulator.
    private static func rigPlacementSpreadsFixturesAcrossZone() {
        let layout = StageLayout.defaultStudentOutdoor()

        let foh0 = RigPlacement.placement(zone: .stageFront, slot: 0, count: 4, layout: layout)
        let fohCenter = RigPlacement.placement(zone: .stageFront, slot: 0, count: 1, layout: layout)
        let foh3 = RigPlacement.placement(zone: .stageFront, slot: 3, count: 4, layout: layout)
        expect(foh0.position.x < fohCenter.position.x, "First FOH slot should sit left of a single centered fixture")
        expect(fohCenter.position.x < foh3.position.x, "Last FOH slot should sit right of center")

        let upstage = RigPlacement.placement(zone: .stageBack, slot: 0, count: 2, layout: layout)
        expect(upstage.position.z < foh0.position.z, "Upstage fixtures should sit behind the FOH line")
        expect(upstage.position.y > 0, "Upstage fixtures should hang above the floor")
        expect(upstage.aim.z < foh0.aim.z, "Upstage fixtures aim upstage; FOH fixtures aim at the performer area")
    }

    private static func fixtureManualPositionOverridesZonePlacement() throws {
        let layout = StageLayout.defaultStudentOutdoor()
        let zonePlacement = RigPlacement.placement(zone: .stageFront, slot: 1, count: 4, layout: layout)

        // (a) No manualPosition → resolvedPlacement equals the zone-derived placement (position AND aim).
        let unplaced = FixtureGroup(
            id: "f1", name: "燈具 1", role: .frontLight, zone: .stageFront,
            enabled: true, intensity: 0.6, color: FixtureColor(mode: .rgb, value: "#FFFFFF")
        )
        let resolvedUnplaced = RigPlacement.resolvedPlacement(fixture: unplaced, slot: 1, count: 4, layout: layout)
        expect(resolvedUnplaced.position == zonePlacement.position,
               "Without a manualPosition, resolved position must equal the zone-derived position")
        expect(resolvedUnplaced.aim == zonePlacement.aim,
               "Without a manualPosition, resolved aim must equal the zone-derived aim")

        // (b) With a manualPosition → position is replaced by it while aim stays zone-derived.
        var placed = unplaced
        let manual = FixturePosition(x: -1.25, y: 2.4, z: 0.9)
        placed.manualPosition = manual
        let resolvedPlaced = RigPlacement.resolvedPlacement(fixture: placed, slot: 1, count: 4, layout: layout)
        expect(resolvedPlaced.position == Vector3Meters(x: manual.x, y: manual.y, z: manual.z),
               "A manualPosition must replace the resolved position")
        expect(resolvedPlaced.aim == zonePlacement.aim,
               "A manualPosition must NOT change the zone-derived aim")

        // (c) Old JSON with no `manualPosition` key decodes to nil (synthesized decoder defaults optionals).
        let legacyJSON = """
        {"id":"f1","name":"燈具 1","role":"frontLight","zone":"stageFront",
         "enabled":true,"intensity":0.6,"color":{"mode":"rgb","value":"#FFFFFF"}}
        """
        let decoded = try JSONDecoder().decode(FixtureGroup.self, from: Data(legacyJSON.utf8))
        expect(decoded.manualPosition == nil,
               "A FixtureGroup decoded from JSON without a manualPosition key must yield nil")

        // Round-trip: a set manualPosition survives encode/decode.
        let roundTripped = try JSONDecoder().decode(FixtureGroup.self, from: JSONEncoder().encode(placed))
        expect(roundTripped.manualPosition == manual, "manualPosition must survive a Codable round-trip")
    }

    private static func fixtureSupportPolicyClassifiesTrussVsStand() {
        let layout = StageLayout.defaultStudentOutdoor()
        // Use placement to produce each zone's actual position, then ask support:
        let back  = RigPlacement.placement(zone: .stageBack,  slot: 0, count: 1, layout: layout).position
        let left  = RigPlacement.placement(zone: .stageLeft,  slot: 0, count: 2, layout: layout).position
        let front = RigPlacement.placement(zone: .stageFront, slot: 0, count: 2, layout: layout).position
        expect(RigPlacement.support(forPosition: back,  layout: layout) == .hangFromTruss, "上舞台 truss 位吊掛")
        expect(RigPlacement.support(forPosition: left,  layout: layout).isFloorStand,      "側台 boom 落地燈架")
        expect(RigPlacement.support(forPosition: front, layout: layout).isFloorStand,      "FOH 落地燈架")
        // 手動位置：truss 正下方且高 → 吊掛；台前高處（footprint 外）→ 落地。
        if let f = RigPlacement.trussFootprint(in: layout) {
            let underTruss = Vector3Meters(x: (f.minX + f.maxX)/2, y: f.topY - 0.2, z: (f.minZ + f.maxZ)/2)
            expect(RigPlacement.support(forPosition: underTruss, layout: layout) == .hangFromTruss, "truss 正下方高處吊掛")
        }
        let floatingDownstage = Vector3Meters(x: 0, y: 3.0, z: 5.0)  // 台前遠處高空
        if case .floorStand(let topY) = RigPlacement.support(forPosition: floatingDownstage, layout: layout) {
            expect(topY > 0.3 && topY <= 3.0, "落地柱頂在燈下")
        } else { fatalError("台前高空應落地燈架，不可浮空") }
    }

    private static func surroundingsLightPolicyGatesOpaqueVenue() throws {
        expect(SurroundingsLightPolicy.includesOpaqueVenue(in: .fullStage),
               "Full-stage immersion must keep the opaque venue (floor + backdrop)")
        expect(!SurroundingsLightPolicy.includesOpaqueVenue(in: .roomSpill),
               "Room-spill mode must hide the opaque venue so passthrough shows through")
        expect(StageImmersionMode.allCases.count == 2, "There should be exactly two immersion modes")
        expect(StageImmersionMode.fullStage.displayName == "Full Stage", "Full-stage display name should be stable")
        expect(StageImmersionMode.roomSpill.displayName == "Spill onto Room", "Room-spill display name should be stable")

        let encoded = try JSONEncoder().encode(StageImmersionMode.roomSpill)
        let decoded = try JSONDecoder().decode(StageImmersionMode.self, from: encoded)
        expect(decoded == .roomSpill, "StageImmersionMode should survive a Codable round-trip")
    }

    // 空間重開重試節奏（stage↔editor 交接失敗的補救）：前三次失敗以 0.3s 起倍增退避重試，
    // 第 maxAttempts 次失敗即放棄（回 nil，讓 ContentView 清掉 desired scene、退回 composer）。
    private static func immersiveSceneReopenPolicyBacksOffThenGivesUp() {
        expect(ImmersiveSceneReopenPolicy.retryDelayNanoseconds(afterFailedAttempt: 1) == 300_000_000,
               "First failed open should retry after 0.3s")
        expect(ImmersiveSceneReopenPolicy.retryDelayNanoseconds(afterFailedAttempt: 2) == 600_000_000,
               "Second failed open should back off to 0.6s")
        expect(ImmersiveSceneReopenPolicy.retryDelayNanoseconds(afterFailedAttempt: 3) == 1_200_000_000,
               "Third failed open should back off to 1.2s")
        expect(ImmersiveSceneReopenPolicy.retryDelayNanoseconds(afterFailedAttempt: ImmersiveSceneReopenPolicy.maxAttempts) == nil,
               "Exhausting maxAttempts must give up (nil) so the reconciler exits visibly")
        expect(ImmersiveSceneReopenPolicy.retryDelayNanoseconds(afterFailedAttempt: 0) == nil,
               "A nonsensical attempt number must not retry")
    }

    private static func aiComposerPlacementClampsWithinReach() {
        let home = AIComposerPlacement.defaultPosition
        expect(home.z < 0, "Composer default must sit in front of the viewer (negative z)")
        expect(AIComposerPlacement.clamped(home) == home, "Default position should already be within reach")

        // A drag flung far away / behind the user is pulled back into the reachable front volume.
        let farAway = AIComposerPlacement.clamped(SIMD3<Float>(99, 99, 99))
        expect(farAway.x <= 2.0 && farAway.y <= 2.6 && farAway.z <= -0.4, "Out-of-range drag must clamp to the far bounds")
        expect(farAway.z < 0, "Clamped composer must never end up behind the viewer")

        let tooClose = AIComposerPlacement.clamped(SIMD3<Float>(-99, -99, -99))
        expect(tooClose.x >= -2.0 && tooClose.y >= 0.6 && tooClose.z >= -3.0, "Below-range drag must clamp to the near bounds")
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

    private static func tabletopEditingSwapsStagePlatformPreset() throws {
        let base = StageLayout.defaultStudentOutdoor()
        expect(TabletopStageEditing.currentStagePlatformPreset(of: base) == .medium6x3,
               "Default layout should report the medium 6x3 stage preset")

        let large = TabletopStageEditing.applyingStagePlatformPreset(.large8x4, to: base)
        try large.validate()
        let largeBase = try expectUnwrapped(large.objects.first(where: { $0.type == .stageBase }), "Swapped layout should still have a stage base")
        expect(largeBase.size?.width == 8 && largeBase.size?.depth == 4, "Swapping to the large preset should resize the stage base to 8x4")
        expect(largeBase.position.y == (largeBase.size?.height ?? 0) / 2, "Resized stage base should sit on the ground (y = height/2)")
        expect(largeBase.id == base.objects.first(where: { $0.type == .stageBase })?.id, "Preset swap should preserve the stage base id")
        expect(TabletopStageEditing.currentStagePlatformPreset(of: large) == .large8x4, "After the swap the layout should report the large preset")

        // A preset swap preserves the base's x/z position (only its footprint changes).
        var moved = base
        let baseIndex = try expectUnwrapped(moved.objects.firstIndex(where: { $0.type == .stageBase }), "Default layout should have a stage base")
        moved.objects[baseIndex].position = Vector3Meters(x: 1.0, y: moved.objects[baseIndex].position.y, z: 0.5)
        let small = TabletopStageEditing.applyingStagePlatformPreset(.small4x2, to: moved)
        let smallBase = try expectUnwrapped(small.objects.first(where: { $0.type == .stageBase }), "Swapped layout should still have a stage base")
        expect(smallBase.position.x == 1.0 && smallBase.position.z == 0.5, "Preset swap should preserve the stage base x/z position")
    }

    private static func tabletopEditingSwapsTrussPortalPreset() throws {
        let base = StageLayout.defaultStudentOutdoor()
        expect(TabletopStageEditing.currentTrussPortalPreset(of: base) == .portal6x5,
               "Default layout should report the 6x5 portal preset")

        let swapped = TabletopStageEditing.applyingTrussPortalPreset(.portal8x4, to: base)
        try swapped.validate()
        expect(swapped.objects.contains(where: { $0.type == .stageBase }), "Swapping the portal should keep the stage base")
        expect(swapped.objects.contains(where: { $0.type == .trussSegment }), "Portal swap should leave truss segments in place")
        expect(TabletopStageEditing.currentTrussPortalPreset(of: swapped) == .portal8x4, "After the swap the layout should report the 8x4 portal preset")

        // Re-applying a preset must not leave stale/duplicate truss ids behind.
        let reSwapped = TabletopStageEditing.applyingTrussPortalPreset(.portal8x4, to: swapped)
        try reSwapped.validate()
        let trussIds = reSwapped.objects.filter { $0.type == .trussSegment }.map(\.id)
        expect(Set(trussIds).count == trussIds.count, "Re-applying a portal preset must keep truss ids unique")
    }

    private static func movingTrussDoesNotSnapBackOntoItsOwnEndpoints() throws {
        // A lone truss at an off-grid z (set directly, bypassing addObject's grid snap). Nudging it by
        // less than the connector-snap threshold must NOT cancel the move by matching the object's own
        // stale endpoints — with self-exclusion it falls through to the 0.5m grid snap (which lands at
        // a different z), instead of returning the original off-grid z.
        var layout = StageLayout.empty(name: "Move Test")
        layout.objects = [.trussSegment(id: "t1", assetId: .truss2m, position: Vector3Meters(x: 0, y: 3, z: -1.75), rotation: .zero)]

        var moved = try expectUnwrapped(layout.object(id: "t1"), "Truss should exist in the layout")
        moved.position = Vector3Meters(x: 0, y: 3, z: -1.72) // within StageLayout.connectorSnapThreshold (0.15) of its own old endpoints
        let snapped = layout.snappedObject(moved)
        expect(abs(snapped.position.z - (-1.75)) > 0.01, "A small truss move must not snap back onto the truss's own original endpoints")
    }

    private static func trussNodeSnapMarksActiveConnectorNode() throws {
        // The live tabletop drag shares the committed snap rule via `trussNodeSnap`, which also reports
        // WHICH node engaged so the editor can show a marker.
        var layout = StageLayout.empty(name: "Node Snap Test")
        try layout.addObject(.trussSegment(id: "truss_base", assetId: .truss2m, position: Vector3Meters(x: 0, y: 3, z: 0)))

        // A second truss whose left end lands just shy of the base's right end (2,3,0) → snaps onto it.
        let near = StageObject.trussSegment(id: "truss_near", assetId: .truss2m, position: Vector3Meters(x: 2.1, y: 3.03, z: 0.04))
        let snap = layout.trussNodeSnap(for: near)
        expect(snap != nil, "A truss endpoint within reach of an existing node should report a snap")
        expect(abs((snap?.node.x ?? -99) - 2.0) < 0.0001, "Reported snap node should be the existing base-truss endpoint on X")
        expect(abs((snap?.position.x ?? -99) - 2.0) < 0.0001, "Snapped position should move the near truss exactly onto the node on X")

        // Out of reach → no snap, so the drag follows the finger freely with no marker.
        let far = StageObject.trussSegment(id: "truss_far", assetId: .truss2m, position: Vector3Meters(x: 5, y: 3, z: 0))
        expect(layout.trussNodeSnap(for: far) == nil, "A truss with no node within reach should report no snap")

        // Non-truss objects have no connector endpoints, so they never node-snap.
        let base = StageObject.stageBase(id: "base", position: Vector3Meters(x: 0, y: 0, z: 0), size: StageObjectSize(width: 4, depth: 2, height: 0.8))
        expect(layout.trussNodeSnap(for: base) == nil, "Stage bases have no connector endpoints, so they never node-snap")
    }

    private static func tabletopSurfaceSelectionPrefersNearestLargestTable() {
        let viewer = Vector3Meters(x: 0, y: 1.2, z: 0)

        // Nothing big enough → keep floating (nil).
        let tiny = DetectedHorizontalSurface(center: Vector3Meters(x: 0, y: 0.7, z: -0.5), width: 0.2, depth: 0.2, isTable: true, facesUp: true)
        expect(TabletopSurfaceSelection.bestSurface(from: [tiny], viewer: viewer) == nil, "A surface below the minimum footprint should not host the diorama")

        // Only real tables qualify — a large floor and a (down-facing) ceiling must be ignored, so the model
        // keeps floating rather than landing on them. This is the ceiling-bug regression guard.
        let bigFloor = DetectedHorizontalSurface(center: Vector3Meters(x: 0, y: 0, z: -1), width: 4, depth: 4, isTable: false, facesUp: true)
        let ceiling = DetectedHorizontalSurface(center: Vector3Meters(x: 0, y: 2.6, z: -1), width: 5, depth: 5, isTable: false, facesUp: false)
        expect(TabletopSurfaceSelection.bestSurface(from: [bigFloor, ceiling], viewer: viewer) == nil, "With no table present, the floor and ceiling must be rejected (keep floating)")

        let table = DetectedHorizontalSurface(center: Vector3Meters(x: 0.5, y: 0.72, z: -0.6), width: 1.2, depth: 0.8, isTable: true, facesUp: true)
        expect(TabletopSurfaceSelection.bestSurface(from: [bigFloor, ceiling, table], viewer: viewer) == table, "A real table should be chosen over the floor and ceiling")

        // A surface mislabelled as a table but facing down (e.g. a ceiling) must still be rejected.
        let downwardTable = DetectedHorizontalSurface(center: Vector3Meters(x: 0, y: 2.5, z: -1), width: 2, depth: 2, isTable: true, facesUp: false)
        expect(TabletopSurfaceSelection.bestSurface(from: [downwardTable], viewer: viewer) == nil, "A down-facing surface must never host the diorama, even if classified a table")

        // Among tables, the larger one wins.
        let smallTable = DetectedHorizontalSurface(center: Vector3Meters(x: -0.3, y: 0.72, z: -0.5), width: 0.5, depth: 0.5, isTable: true, facesUp: true)
        let bigTable = DetectedHorizontalSurface(center: Vector3Meters(x: 1.0, y: 0.72, z: -1.2), width: 1.4, depth: 1.0, isTable: true, facesUp: true)
        expect(TabletopSurfaceSelection.bestSurface(from: [smallTable, bigTable], viewer: viewer) == bigTable, "Among tables, the larger footprint should be chosen")

        // Equal-size tables → the nearer one wins.
        let near = DetectedHorizontalSurface(center: Vector3Meters(x: 0, y: 0.72, z: -0.5), width: 1.0, depth: 1.0, isTable: true, facesUp: true)
        let far = DetectedHorizontalSurface(center: Vector3Meters(x: 0, y: 0.72, z: -3.0), width: 1.0, depth: 1.0, isTable: true, facesUp: true)
        expect(TabletopSurfaceSelection.bestSurface(from: [far, near], viewer: viewer) == near, "Among equal-size tables, the nearer one should be chosen")
    }

    private static func humanoidFigurePlanIsAnatomicallyOrdered() throws {
        let feet = Vector3Meters(x: 0.5, y: 0.8, z: 0.25)
        let plan = HumanoidFigurePlan.make(feet: feet)

        func joint(_ id: String, in plan: HumanoidFigurePlan) throws -> HumanoidFigurePlan.Joint {
            try expectUnwrapped(plan.joints.first { $0.id == id }, "figure plan should expose joint \(id)")
        }
        func blob(_ id: String, in plan: HumanoidFigurePlan) throws -> HumanoidFigurePlan.Blob {
            try expectUnwrapped(plan.blobs.first { $0.id == id }, "figure plan should expose blob \(id)")
        }

        // 1) Head top lands at exactly feet + total height; the lowest joint rests near the deck.
        let headTop = plan.headCenter.y + plan.headRadius
        expect(abs(headTop - (feet.y + 1.70)) < 0.02, "head top should sit at feet + total height (~1.70m)")
        let lowestJointY = plan.joints.map { $0.position.y }.min() ?? .infinity
        expect(abs(lowestJointY - feet.y) < 0.12, "the lowest joint (ankles) should rest near the deck")

        // 2) Vertical anatomy ordering — head, shoulders, torso, hips, knees, ankles, top to bottom.
        let shoulderR = try joint("shoulder_r", in: plan)
        let shoulderL = try joint("shoulder_l", in: plan)
        let kneeR = try joint("knee_r", in: plan)
        let kneeL = try joint("knee_l", in: plan)
        let ankleR = try joint("ankle_r", in: plan)
        let ankleL = try joint("ankle_l", in: plan)
        let torso = try blob("torso", in: plan)
        let hips = try blob("hips", in: plan)

        expect(plan.headCenter.y > shoulderR.position.y && plan.headCenter.y > shoulderL.position.y, "head should sit above the shoulders")
        expect(min(shoulderR.position.y, shoulderL.position.y) > torso.center.y, "shoulders should sit above the torso centre")
        expect(torso.center.y > hips.center.y, "torso should sit above the hips")
        expect(hips.center.y > max(kneeR.position.y, kneeL.position.y), "hips should sit above the knees")
        expect(min(kneeR.position.y, kneeL.position.y) > max(ankleR.position.y, ankleL.position.y), "knees should sit above the ankles")

        // 3) The default stance is a perfectly mirrored, symmetric pose.
        for kind in ["shoulder", "elbow", "hand", "hip", "knee", "ankle"] {
            let r = try joint("\(kind)_r", in: plan)
            let l = try joint("\(kind)_l", in: plan)
            expect(abs((r.position.x - feet.x) + (l.position.x - feet.x)) < 1e-9, "\(kind) joints should mirror across the centre line")
            expect(abs(r.position.y - l.position.y) < 1e-9 && abs(r.position.z - l.position.z) < 1e-9, "\(kind) joints should match in height and depth")
        }

        // 4) An optional weight shift drops the left hip slightly but keeps mass centred over the stand point.
        let shifted = HumanoidFigurePlan.make(feet: feet, contrapposto: 1)
        let sHipR = try joint("hip_r", in: shifted)
        let sHipL = try joint("hip_l", in: shifted)
        expect(sHipL.position.y < sHipR.position.y, "weight on the right leg should drop the left hip")
        expect(sHipR.position.y - sHipL.position.y < 0.02, "the weight shift should stay subtle")
        expect(abs((sHipR.position.x + sHipL.position.x) / 2 - feet.x) < 1e-9, "the pelvis should stay centred over the stand point")

        // 5) Every limb connects real joints and none collapses to a point.
        let anchors = plan.joints.map { $0.position }
        func isAnchor(_ point: Vector3Meters) -> Bool {
            anchors.contains { $0.distance(to: point) < 1e-9 }
        }
        for bone in plan.bones {
            expect(isAnchor(bone.a) && isAnchor(bone.b), "every limb should connect skeleton joints")
            expect(bone.a.distance(to: bone.b) > 0.05, "no limb should collapse to a point")
        }

        // 6) All four rounded masses are present and the torso reads broader than the hips.
        expect(Set(plan.blobs.map { $0.id }) == ["torso", "hips", "foot_l", "foot_r"], "figure plan should expose torso, hips and both feet")
        expect(torso.radius > hips.radius, "the torso should read broader than the hips")
    }

    private static func normalizedHexToleratesModelNoise() {
        // The on-device model sometimes appends stray punctuation to a colour (observed: "#FFD1A3,").
        // The normaliser should recover the #RRGGBB value rather than failing the whole generated look.
        expect(FixtureColor.normalizedHex("#FFD1A3,") == "#FFD1A3", "a trailing comma should be tolerated")
        expect(FixtureColor.normalizedHex("  #ffd1a3 ") == "#FFD1A3", "whitespace should be trimmed and the value upper-cased")
        expect(FixtureColor.normalizedHex("#FFD1A3") == "#FFD1A3", "a clean value should pass through unchanged")
        expect(FixtureColor.normalizedHex("warm #4FA8FF tone") == "#4FA8FF", "a value wrapped in prose should still resolve")

        // Genuinely malformed values must still fail so the look validators keep rejecting bad data.
        expect(FixtureColor.normalizedHex("#FFF") == nil, "a three-digit shorthand should be rejected")
        expect(FixtureColor.normalizedHex("#FFD1A3AB") == nil, "an eight-digit (RGBA) value should be rejected")
        expect(FixtureColor.normalizedHex("blue") == nil, "a value with no hash should be rejected")

        // End to end: a fixture colour carrying the model's comma should now normalize and parse cleanly.
        expect(FixtureColor(mode: .rgb, value: "#FFD1A3,").normalized.value == "#FFD1A3", "FixtureColor.normalized should clean model noise")
        expect(RGBComponents(hex: "#FFD1A3,") != nil, "RGB components should parse a comma-suffixed colour")
    }

    // A fixture's `target` + `dmx` (the JSON fields the model gained) must validate, round-trip through
    // Codable (they ride persistence + the iPad sync), and reject out-of-range DMX values.
    private static func dmxAndTargetSurviveValidationAndCodec() throws {
        var look = LightingLook.mvpDemo()
        let patch = DMXPatch(universe: 2, address: 13, channels: .init(dimmer: 13, red: 14, green: 15, blue: 16))
        look.cues[0].fixtureGroups[0].target = .centerStage
        look.cues[0].fixtureGroups[0].dmx = patch
        try look.validate()   // a valid target + DMX patch must pass validation

        let data = try JSONEncoder().encode(look)
        let decoded = try JSONDecoder().decode(LightingLook.self, from: data)
        expect(decoded.cues[0].fixtureGroups[0].dmx == patch, "DMX patch should survive a Codable round-trip")
        expect(decoded.cues[0].fixtureGroups[0].target == .centerStage, "Fixture target should survive a Codable round-trip")

        // FixtureTarget encodes as the snake_case string the JSON schema uses.
        let targetData = try JSONEncoder().encode(FixtureTarget.centerStage)
        expect(String(data: targetData, encoding: .utf8) == "\"center_stage\"", "FixtureTarget must encode as its snake_case raw value")

        // An out-of-range DMX address (> 512) is rejected.
        look.cues[0].fixtureGroups[0].dmx = DMXPatch(universe: 1, address: 999, channels: .init(dimmer: 1, red: 2, green: 3, blue: 4))
        expectThrows(ValidationError.invalidDMXValue("address", 999)) { try look.validate() }
    }

    // The richer offline-mock showcase look must validate, carry a diverse rig (>= 6 fixtures, several
    // distinct types), keep the same fixtures across both cues, and patch every fixture with a unique
    // DMX address + an aim target.
    private static func showcaseDemoIsValidAndDiverse() throws {
        let look = LightingLook.showcaseDemo()
        try look.validate()

        let opening = try look.requireCue(id: "cue_opening")
        let highlight = try look.requireCue(id: "cue_highlight")
        expect(opening.fixtureGroups.count >= 6, "showcase demo should have a rich rig (>= 6 fixtures)")
        expect(opening.fixtureGroups.map(\.id) == highlight.fixtureGroups.map(\.id),
               "both cues must carry the same fixtures in the same order")

        let models = Set(opening.fixtureGroups.compactMap(\.model))
        expect(models.count >= 4, "showcase demo should mix at least 4 distinct fixture types")
        expect(opening.fixtureGroups.allSatisfy { $0.dmx != nil && $0.target != nil },
               "every showcase fixture should carry a DMX patch and an aim target")

        let addresses = opening.fixtureGroups.compactMap { $0.dmx?.address }
        expect(Set(addresses).count == addresses.count, "showcase DMX addresses must not collide")
    }

    // A look is now a cue *stack*, not a fixed Opening+Highlight pair: validate accepts one or many
    // cues and rejects only an empty stack or an unresolved selection.
    private static func validateAcceptsMultipleCuesAndRejectsEmpty() throws {
        // A single-cue look validates.
        var single = LightingLook.mvpDemo()
        single.cues = [single.cues[0]]
        single.selectedCueId = single.cues[0].id
        try single.validate()

        // A many-cue look validates (duplicate the showcase's cues into a 4-cue stack).
        var many = LightingLook.showcaseDemo()
        let base = many.cues[0]
        many.cues = (0..<4).map { i in
            var c = base
            c.id = "cue_\(i)"
            c.name = "Cue \(i + 1)"
            return c
        }
        many.selectedCueId = "cue_0"
        try many.validate()
        expect(many.cues.count == 4, "a four-cue stack should validate")

        // An empty stack is rejected.
        var empty = LightingLook.mvpDemo()
        empty.cues = []
        expectThrows(ValidationError.missingRequiredCue) { try empty.validate() }

        // A selection that resolves to no cue is rejected.
        var dangling = LightingLook.mvpDemo()
        dangling.selectedCueId = "cue_nope"
        expectThrows(ValidationError.missingCue("cue_nope")) { try dangling.validate() }
    }

    // The multi-cue AI → domain assembler (the "describe the whole show → a sequence of cues" path)
    // builds an ordered, validated cue stack with the first cue selected and the rig shared across cues.
    private static func multiCueDraftBuildsValidatedSequence() throws {
        func fixtures(front: Double, back: Double) -> [LightingLookDraft.Fixture] {
            [
                LightingLookDraft.Fixture(id: "f0", name: "Front", role: .frontLight, zone: .stageFront, enabled: true, intensity: front, colorHex: "#FFD1A3"),
                LightingLookDraft.Fixture(id: "f1", name: "Back", role: .backgroundWash, zone: .stageBack, enabled: true, intensity: back, colorHex: "#3A6BFF")
            ]
        }

        let look = try LightingLookDraft.makeValidatedLook(
            lookName: "Showtime",
            mood: "builds to a finale",
            cues: [
                .init(id: "cue_0", name: "Opening", fixtures: fixtures(front: 0.4, back: 0.5)),
                .init(id: "cue_1", name: "Build", fixtures: fixtures(front: 0.6, back: 0.7)),
                .init(id: "cue_2", name: "Chorus", fixtures: fixtures(front: 0.9, back: 0.95))
            ],
            explanationTerm: "Cue Stack",
            explanationPlainText: "A cue stack is the ordered list of looks a show steps through.",
            explanationActionSummary: "Built a three-cue show."
        )

        try look.validate()
        expect(look.cues.map(\.id) == ["cue_0", "cue_1", "cue_2"], "multi-cue draft should preserve cue order and ids")
        expect(look.cues.map(\.name) == ["Opening", "Build", "Chorus"], "multi-cue draft should preserve cue names")
        expect(look.selectedCueId == "cue_0", "multi-cue draft should select the first cue")
        let chorusFront = try look.requireCue(id: "cue_2").requireFixture(role: .frontLight)
        expect(abs(chorusFront.intensity - 0.9) < 0.0001, "each cue should carry its own per-fixture state")
    }

    // The cue-stack ops: GO advances (wrapping), GO-back steps back, append duplicates the rig into a
    // new cue, remove never empties the stack, and the selection stays valid throughout.
    private static func stageStateSupportsCueStackAndGo() throws {
        var state = StageState(lightingLook: .mvpDemo())   // cue_opening, cue_highlight; selected = opening
        expect(state.cueOrder == ["cue_opening", "cue_highlight"], "stack should start as the two template cues")

        // GO advances to the next cue, and wraps from the last back to the first.
        expect(state.goToNextCue().id == "cue_highlight", "GO should advance to the next cue")
        expect(state.goToNextCue().id == "cue_opening", "GO should wrap from the last cue to the first")
        // GO back steps the other way (wrapping to the last).
        expect(state.goToPreviousCue().id == "cue_highlight", "GO back should wrap to the last cue")

        // Append duplicates the SELECTED cue (highlight) into a new, selected cue right after it.
        try state.appendCue(id: "cue_build", name: "Build")
        expect(state.selectedCueId == "cue_build", "appending a cue should select it")
        expect(state.cueOrder == ["cue_opening", "cue_highlight", "cue_build"], "new cue should insert after the source cue")
        // The duplicate keeps the rig identity (same fixtures as its source).
        let source = try state.lightingLook.requireCue(id: "cue_highlight")
        let dup = try state.lightingLook.requireCue(id: "cue_build")
        expect(dup.fixtureGroups.map(\.id) == source.fixtureGroups.map(\.id), "an appended cue should duplicate the source rig")

        // Remove the selected cue → selection falls to a neighbour, stack stays valid.
        try state.removeCue(id: "cue_build")
        expect(!state.cueOrder.contains("cue_build"), "removed cue should be gone")
        expect(state.lightingLook.cues.contains(where: { $0.id == state.selectedCueId }), "selection must still resolve after a remove")

        // Can't remove the last cue.
        try state.removeCue(id: "cue_highlight")
        expectThrows(ValidationError.cannotRemoveLastCue) { try state.removeCue(id: "cue_opening") }
        expect(state.cueOrder == ["cue_opening"], "the final cue must remain")
    }

    // Patch planning makes the (previously dead) DMXPatch field live: sequential, non-colliding
    // addresses written onto every cue, and a printable sheet summary.
    private static func patchPlannerAssignsSequentialDMXAndBuildsSheet() throws {
        let look = LightingLook.showcaseDemo()   // 9 fixtures
        let patched = DMXPatchPlanner.patched(look)

        let rig = patched.cues.first!.fixtureGroups
        let addresses = rig.compactMap { $0.dmx?.address }
        expect(addresses == [1, 5, 9, 13, 17, 21, 25, 29, 33], "fixtures should patch sequentially in 4-channel steps from address 1")
        expect(rig.allSatisfy { $0.dmx?.universe == 1 }, "nine fixtures fit in one universe")
        expect(Set(addresses).count == addresses.count, "patched DMX addresses must not collide")

        // The same patch is written onto the fixture in EVERY cue (rig identity across cues).
        for cue in patched.cues {
            expect(cue.fixtureGroups.allSatisfy { $0.dmx != nil }, "every fixture in every cue should carry a patch")
        }
        try patched.validate()

        let sheet = LightingPatchSheet.make(from: look)
        expect(sheet.fixtureCount == 9, "sheet should list every fixture")
        expect(sheet.universeCount == 1, "sheet should report one universe for nine fixtures")
        expect(sheet.channelCount == 36, "nine fixtures × 4 channels = 36 DMX channels")
        expect(sheet.rows.first?.number == 1, "rows should be 1-based, matching on-stage Light N")
        expect(sheet.rows.first?.channelSpan == "1–4", "first fixture should span channels 1–4")
        expect(sheet.rows.allSatisfy { !$0.fixtureType.isEmpty }, "every row should name a fixture type")

        // Idempotent: re-patching an already-patched look yields the same addresses.
        let twice = DMXPatchPlanner.patched(patched)
        expect(twice.cues.first!.fixtureGroups.compactMap { $0.dmx?.address } == addresses, "re-patching should be stable")
    }

    // The hands-free show-driving voice layer: cue navigation + narration in English and Chinese, while
    // design prompts (which merely contain a word like "go") still fall through to AI generation.
    private static func parsesStageVoiceCommands() {
        expect(StageVoiceCommand.parse("next cue") == .nextCue, "'next cue' should advance")
        expect(StageVoiceCommand.parse("下一個場景") == .nextCue, "Chinese 'next scene' should advance")
        expect(StageVoiceCommand.parse("go") == .nextCue, "a bare 'go' is the GO key")
        expect(StageVoiceCommand.parse("ok go now") == .nextCue, "filler around 'go' should still advance")
        expect(StageVoiceCommand.parse("previous cue") == .previousCue, "'previous cue' should step back")
        expect(StageVoiceCommand.parse("go back") == .previousCue, "'go back' should step back, not advance")
        expect(StageVoiceCommand.parse("上一個") == .previousCue, "Chinese 'previous' should step back")
        expect(StageVoiceCommand.parse("add a cue") == .addCue, "'add a cue' should append")
        expect(StageVoiceCommand.parse("新增場景") == .addCue, "Chinese 'add scene' should append")
        expect(StageVoiceCommand.parse("read it aloud") == .readExplanation, "'read it aloud' should narrate")
        expect(StageVoiceCommand.parse("念出說明") == .readExplanation, "Chinese 'read the explanation' should narrate")

        // Design prompts must NOT be hijacked into cue navigation.
        expect(StageVoiceCommand.parse("go for a warm sunset mood") == nil, "a design prompt containing 'go' must fall through")
        expect(StageVoiceCommand.parse("make it warm and moody") == nil, "a plain design prompt should not parse as a show command")
        expect(StageVoiceCommand.parse("set light 2 to blue") == nil, "a single-light command should fall through to LightCommand")

        // Longer design prompts that merely EMBED a command phrase must also fall through (the
        // substring-match bug): the parser is anchored, so the phrase has to be ~the whole utterance.
        expect(StageVoiceCommand.parse("add a cooler wash to the next scene") == nil, "embedded 'next scene' must not advance the cue")
        expect(StageVoiceCommand.parse("give me a warm glow for the previous scene transition") == nil, "embedded 'previous scene' must not step back")
        expect(StageVoiceCommand.parse("light up the last cue area") == nil, "embedded 'last cue' must not step back")
        expect(StageVoiceCommand.parse("go to next level of brightness") == nil, "embedded 'go to next' must not advance")
        expect(StageVoiceCommand.parse("add a new cue feel to the room") == nil, "embedded 'new cue' must not append")
        expect(StageVoiceCommand.parse("make the singer say it loud") == nil, "embedded 'say it' must not narrate")
        expect(StageVoiceCommand.parse("explain it like a sunset") == nil, "embedded 'explain it' must not narrate")
        // Chinese (the primary user language) design prompts that embed a command word must fall through.
        expect(StageVoiceCommand.parse("把燈光調成上一個演出的暖色") == nil, "embedded 上一個 must not step back")
        expect(StageVoiceCommand.parse("做一個像下一個季節的暖色調") == nil, "embedded 下一個 must not advance")
        expect(StageVoiceCommand.parse("複製場景的氛圍到主舞台") == nil, "embedded 複製場景 must not append")
        // Anchored true positives still parse (with a particle / filler around them).
        expect(StageVoiceCommand.parse("請下一個") == .nextCue, "a Chinese command with a particle still parses")
        expect(StageVoiceCommand.parse("read it aloud") == .readExplanation, "the exact narration command still parses")
    }

    private static func stageLightAccessibilityLabelsAreLocalized() {
        // Identity: the Nth light reads "第 N 盞燈，<繁中 type name from the catalog>".
        expect(StageLightAccessibility.identityLabel(number: 3, model: .movingHeadBeam) == "第 3 盞燈，搖頭光束燈",
               "Light identity should number the fixture and name its 繁中 type from the catalog")
        expect(StageLightAccessibility.identityLabel(number: 1, model: .laser) == "第 1 盞燈，雷射燈",
               "Light identity should resolve the laser type name from the catalog")

        // State value: colour name + intensity percent; off short-circuits to 已關閉.
        expect(StageLightAccessibility.stateValue(colorHex: "#2E6BFF", intensity: 0.6, isOff: false) == "藍色，亮度 60%",
               "A lit fixture should announce its colour and rounded intensity percent")
        expect(StageLightAccessibility.stateValue(colorHex: "#2E6BFF", intensity: 0.6, isOff: true) == "已關閉",
               "An off fixture should announce 已關閉 regardless of colour/intensity")
        expect(StageLightAccessibility.stateValue(colorHex: "#FFE9C8", intensity: 0.014, isOff: false) == "暖白，亮度 1%",
               "Intensity should round to the nearest percent and an incandescent tint reads as 暖白")

        // Colour buckets: representative hues + neutrals + the warm-white incandescent case.
        expect(StageLightAccessibility.colorName(forHex: "#E23B3B") == "紅色", "A red hex should bucket to 紅色")
        expect(StageLightAccessibility.colorName(forHex: "#33CC55") == "綠色", "A green hex should bucket to 綠色")
        expect(StageLightAccessibility.colorName(forHex: "#2E6BFF") == "藍色", "A blue hex should bucket to 藍色")
        expect(StageLightAccessibility.colorName(forHex: "#FFFFFF") == "白色", "Pure white should bucket to 白色")
        expect(StageLightAccessibility.colorName(forHex: "#000000") == "黑色", "Pure black should bucket to 黑色")
        expect(StageLightAccessibility.colorName(forHex: "#808080") == "灰色", "A mid neutral should bucket to 灰色")
        expect(StageLightAccessibility.colorName(forHex: "#FFE9C8") == "暖白", "A warm low-saturation tint should bucket to 暖白, not 白色")
        // Tolerates a missing '#' and lowercase.
        expect(StageLightAccessibility.colorName(forHex: "33cc55") == "綠色", "Colour parsing should tolerate a missing # and lowercase")
        // Malformed input falls back to 白色.
        expect(StageLightAccessibility.colorName(forHex: "not-a-color") == "白色", "Malformed hex should fall back to 白色")
        expect(StageLightAccessibility.colorName(forHex: "#12") == "白色", "A too-short hex should fall back to 白色")
    }

    private static func disabledFixtureAssemblesDark() throws {
        // A per-cue state the model emits as enabled:false but intensity > 0 must assemble to a DARK
        // fixture (intensity 0): the renderer is intensity-driven and never reads `enabled`, so without
        // this coupling a "should be off" fixture comes up lit on GO.
        let look = try LightingLookDraft.makeValidatedLook(
            lookName: "Off Test",
            mood: "test",
            cues: [
                .init(id: "cue_0", name: "A", fixtures: [
                    LightingLookDraft.Fixture(id: "f0", name: "Off Light", role: .frontLight, zone: .stageFront,
                                              enabled: false, intensity: 0.7, colorHex: "#FF0000"),
                    LightingLookDraft.Fixture(id: "f1", name: "On Light", role: .backgroundWash, zone: .stageBack,
                                              enabled: true, intensity: 0.8, colorHex: "#3A6BFF")
                ])
            ],
            explanationTerm: "Enabled",
            explanationPlainText: "A disabled fixture is dark.",
            explanationActionSummary: "Off light stays dark."
        )
        try look.validate()
        let off = try look.requireCue(id: "cue_0").requireFixture(role: .frontLight)
        expect(off.enabled == false, "a disabled fixture keeps enabled == false")
        expect(off.intensity == 0, "a disabled fixture must assemble to 0 intensity so it renders dark")
        let on = try look.requireCue(id: "cue_0").requireFixture(role: .backgroundWash)
        expect(abs(on.intensity - 0.8) < 0.0001, "an enabled fixture keeps its intensity")
    }

    private static func lightEffectEngineModulatesMovementAndIntensity() {
        // Inert: a none / zero-speed effect contributes nothing.
        expect(LightEffectEngine.output(.none, at: 3.2) == .identity, "a none effect is identity at any time")
        expect(LightEffectEngine.output(LightEffect(kind: .panSweep, speedHz: 0, sizeDegrees: 30, phase: 0), at: 1) == .identity,
               "a zero-speed effect is inert")

        // Pan sweep: centred at t=0, peaks at +size a quarter-period later, only touches pan, leaves intensity.
        let pan = LightEffect(kind: .panSweep, speedHz: 1, sizeDegrees: 30, phase: 0)
        expect(abs(LightEffectEngine.output(pan, at: 0).panOffsetDegrees) < 1e-9, "pan sweep starts centred at t=0")
        expect(abs(LightEffectEngine.output(pan, at: 0.25).panOffsetDegrees - 30) < 1e-6, "pan sweep reaches +size at quarter period")
        expect(LightEffectEngine.output(pan, at: 0.37).tiltOffsetDegrees == 0, "pan sweep never tilts")
        expect(LightEffectEngine.output(pan, at: 0.37).intensityScale == 1, "a sweep leaves intensity to the cue")
        for t in stride(from: 0.0, to: 2.0, by: 0.05) {
            expect(abs(LightEffectEngine.output(pan, at: t).panOffsetDegrees) <= 30 + 1e-9, "pan stays within size")
        }

        // Circle: pan² + tilt² ≈ size² (the beam traces a circle).
        let circle = LightEffect(kind: .circle, speedHz: 0.5, sizeDegrees: 20, phase: 0)
        let c = LightEffectEngine.output(circle, at: 0.6)
        expect(abs((c.panOffsetDegrees * c.panOffsetDegrees + c.tiltOffsetDegrees * c.tiltOffsetDegrees) - 400) < 1e-3,
               "circle keeps pan²+tilt² == size²")

        // Strobe: hard 0/1 toggle that actually visits both states.
        let strobe = LightEffect(kind: .strobe, speedHz: 5, sizeDegrees: 0, phase: 0)
        let scales = stride(from: 0.0, to: 1.0, by: 0.02).map { LightEffectEngine.output(strobe, at: $0).intensityScale }
        expect(scales.allSatisfy { $0 == 0 || $0 == 1 }, "strobe is a hard on/off")
        expect(scales.contains(0) && scales.contains(1), "strobe actually toggles both states")

        // Color chase: a smooth 0...1 pulse, phase-staggered so different fixtures differ at the same instant.
        let chaseA = LightEffect(kind: .colorChase, speedHz: 1, sizeDegrees: 0, phase: 0)
        let chaseB = LightEffect(kind: .colorChase, speedHz: 1, sizeDegrees: 0, phase: 0.5)
        let a = LightEffectEngine.output(chaseA, at: 0.1).intensityScale
        let b = LightEffectEngine.output(chaseB, at: 0.1).intensityScale
        expect((0...1).contains(a), "chase pulse stays in 0...1")
        expect(abs(a - b) > 1e-6, "a phase offset staggers fixtures so the chase runs across the rig")

        // Suggested defaults (BUG 4): the moving head re-aims (panSweep, no flicker) — the only auto-effect.
        // Wash/PAR/strobe/blinder are now AUTHORED-ONLY (.none) because an auto intensity-driving default
        // pulsed the static rig every frame and read as flicker; movement/strobe is opt-in via fixture.effect.
        expect(LightEffect.suggested(for: .movingHeadBeam, highEnergy: true, slot: 0).kind == .panSweep, "moving heads sweep")
        expect(LightEffect.suggested(for: .frontFresnel, highEnergy: true, slot: 0).kind == .none, "front fresnels stay steady")
        expect(LightEffect.suggested(for: .washBar, highEnergy: true, slot: 0).kind == .none, "wash bars are authored-only (no auto chase → no flicker)")
        expect(LightEffect.suggested(for: .ledPar, highEnergy: true, slot: 0).kind == .none, "PARs are authored-only (no auto chase → no flicker)")
        expect(LightEffect.suggested(for: .backgroundBatten, highEnergy: true, slot: 0).kind == .none, "background battens are authored-only (no auto chase → no flicker)")
        expect(LightEffect.suggested(for: .ledStrobeBar, highEnergy: true, slot: 0).kind == .none, "strobe bars are authored-only now (no auto strobe)")
        expect(LightEffect.suggested(for: .audienceBlinder, highEnergy: true, slot: 0).kind == .none, "blinders are authored-only now (no auto strobe)")
        expect(LightEffect.suggested(for: .movingHeadBeam, highEnergy: true, slot: 0).sizeDegrees
               > LightEffect.suggested(for: .movingHeadBeam, highEnergy: false, slot: 0).sizeDegrees,
               "high energy widens the moving-head swing")
    }

    // SPEC 05 (owner A): the pure beat grid. Phase stays in [0,1), hits ~0 on each beat boundary, beatHz is
    // bpm/60, startOffset shifts the grid, beatIndex increments per beat, and bpm <= 0 is guarded.
    private static func musicBeatClockGridIsCorrect() {
        let clock = MusicBeatClock(bpm: 120, startOffset: 0)   // 120 bpm → one beat every 0.5s
        expect(abs(clock.beatHz - 2) < 1e-12, "beatHz must be bpm/60 (120 → 2 Hz)")

        // Phase is ~0 exactly on each beat boundary and stays in [0,1) everywhere.
        for k in 0..<6 {
            let boundary = clock.startOffset + Double(k) / clock.beatHz   // 0, 0.5, 1.0, ...
            expect(clock.beatPhase(at: boundary) < 1e-9, "phase returns to ~0 on each beat boundary")
            expect(clock.beatIndex(at: boundary) == k, "beatIndex increments per beat")
        }
        for t in stride(from: -1.0, to: 4.0, by: 0.013) {
            let p = clock.beatPhase(at: t)
            expect(p >= 0 && p < 1, "beatPhase stays in [0,1)")
        }

        // Mid-beat is phase ~0.5.
        expect(abs(clock.beatPhase(at: 0.25) - 0.5) < 1e-9, "a quarter second into a 0.5s beat is mid-beat")

        // startOffset shifts the whole grid: with offset 0.2, the first beat boundary moves to t=0.2.
        let shifted = MusicBeatClock(bpm: 120, startOffset: 0.2)
        expect(shifted.beatPhase(at: 0.2) < 1e-9, "startOffset moves the first beat boundary")
        expect(shifted.beatIndex(at: 0.1) == -1, "beatIndex is negative before startOffset")
        expect(shifted.beatIndex(at: 0.2) == 0, "first beat starts at startOffset")
        // The shifted grid's phase at the unshifted boundary equals the offset fraction of a beat.
        expect(abs(shifted.beatPhase(at: 0.0) - 0.6) < 1e-9, "offset 0.2 of a 0.5s beat reads phase 0.6 at t=0")

        // bpm <= 0 is guarded (no divide-by-zero).
        let dead = MusicBeatClock(bpm: 0, startOffset: 0)
        expect(dead.beatPhase(at: 3.7) == 0, "bpm <= 0 returns 0 phase")
        expect(dead.beatIndex(at: 3.7) == 0, "bpm <= 0 returns beat 0")
    }

    // SPEC 05 (owner A): the beat-locked effect mapping. Strobe punches on the leading edge of each beat,
    // colorChase peaks once per beat, sweeps delegate to the A1 engine on a continuous beat clock, and
    // inert/none effects are identity.
    private static func musicBeatSyncLocksEffectsToBeat() {
        let clock = MusicBeatClock(bpm: 120, startOffset: 0)   // beat = 0.5s; strobe lit for first ~30%

        // Inert effects are identity regardless of the clock.
        expect(MusicBeatSync.output(.none, clock: clock, at: 1.3) == .identity, "none is identity under beat sync")
        let stillStrobe = LightEffect(kind: .strobe, speedHz: 0, sizeDegrees: 0, phase: 0)
        expect(MusicBeatSync.output(stillStrobe, clock: clock, at: 1.3) == .identity, "a zero-speed effect is inert")

        // Strobe: ON just after a beat boundary, OFF mid-beat.
        let strobe = LightEffect(kind: .strobe, speedHz: 8, sizeDegrees: 0, phase: 0)
        expect(MusicBeatSync.output(strobe, clock: clock, at: 0.01).intensityScale == 1, "strobe is ON just after the beat")
        expect(MusicBeatSync.output(strobe, clock: clock, at: 0.51).intensityScale == 1, "strobe re-fires on the next beat")
        expect(MusicBeatSync.output(strobe, clock: clock, at: 0.30).intensityScale == 0, "strobe is OFF mid-beat")
        // It only ever returns a hard 0 or 1 and actually visits both states across a beat.
        let strobeScales = stride(from: 0.0, to: 1.0, by: 0.01).map { MusicBeatSync.output(strobe, clock: clock, at: $0).intensityScale }
        expect(strobeScales.allSatisfy { $0 == 0 || $0 == 1 }, "beat strobe is a hard on/off")
        expect(strobeScales.contains(0) && strobeScales.contains(1), "beat strobe visits both states each beat")

        // Color chase: a smooth pulse that peaks once per beat (mid-beat) and returns to ~0 on the boundary.
        let chase = LightEffect(kind: .colorChase, speedHz: 1, sizeDegrees: 0, phase: 0)
        expect(MusicBeatSync.output(chase, clock: clock, at: 0.0).intensityScale < 1e-9, "chase is dark on the beat boundary")
        expect(abs(MusicBeatSync.output(chase, clock: clock, at: 0.25).intensityScale - 1) < 1e-9, "chase peaks once mid-beat")
        let chaseScales = stride(from: 0.0, to: 1.0, by: 0.01).map { MusicBeatSync.output(chase, clock: clock, at: $0).intensityScale }
        expect(chaseScales.allSatisfy { (0...1).contains($0) }, "chase pulse stays in 0...1")
        // Phase stagger makes two fixtures differ at the same instant (the pulse runs across the rig).
        let chaseB = LightEffect(kind: .colorChase, speedHz: 1, sizeDegrees: 0, phase: 0.5)
        expect(abs(MusicBeatSync.output(chase, clock: clock, at: 0.1).intensityScale
                   - MusicBeatSync.output(chaseB, clock: clock, at: 0.1).intensityScale) > 1e-6,
               "a phase offset staggers fixtures so the chase runs across the rig")

        // Sweep: delegates to the A1 engine on the beat clock — stays within ±sizeDegrees and is continuous
        // across beat boundaries (no jump from just-before to just-after a beat).
        let pan = LightEffect(kind: .panSweep, speedHz: 0.4, sizeDegrees: 30, phase: 0)
        for t in stride(from: 0.0, to: 2.0, by: 0.01) {
            let out = MusicBeatSync.output(pan, clock: clock, at: t)
            expect(abs(out.panOffsetDegrees) <= 30 + 1e-9, "beat-synced pan stays within sizeDegrees")
            expect(out.tiltOffsetDegrees == 0 && out.intensityScale == 1, "a beat-synced sweep leaves intensity to the cue")
        }
        // Continuity at a beat boundary: pan just before 0.5 ≈ pan just after.
        // beatTime = beatIndex + beatPhase is continuous, so the engine's sin(2π·beatTime) is too — the
        // tiny step here reflects only the curve's slope, not a discontinuity. Use a small symmetric step
        // and a tolerance comfortably above slope·step (≈ 2π·30·dt) yet far below any jump (which would be
        // O(size)).
        let dt = 1e-4
        let before = MusicBeatSync.output(pan, clock: clock, at: 0.5 - dt).panOffsetDegrees
        let after = MusicBeatSync.output(pan, clock: clock, at: 0.5 + dt).panOffsetDegrees
        expect(abs(before - after) < 0.1, "the sweep does not jump across a beat boundary")
    }

    /// The built-in demo song's synthesized backing track (`DemoTrackSynth`) must produce a well-formed,
    /// AUDIBLE, deterministic 16-bit PCM WAV whose energy follows the analysis's sections — otherwise the
    /// demo plays in silence (the exact bug this fixes). Pins: sample count = duration·sampleRate; a canonical
    /// WAV header (RIFF/WAVE/fmt /data, mono, 44.1 kHz, 16-bit, matching sizes); the buffer isn't silent; a
    /// loud chorus section is clearly louder than a quiet intro; and the render is byte-stable.
    private static func demoTrackSynthRendersBeatMatchedAudibleWav() {
        // A short two-section analysis: a quiet intro then a loud chorus. bpm-only (no beatTimes) exercises the
        // derived grid. Keep it short so the headless render stays fast.
        let sections = [
            SongSection(start: 0, end: 3, kind: .intro, pace: 0.30, loudness: 0.35, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 3, end: 6, kind: .chorus, pace: 0.90, loudness: 0.90, keyMode: .major, dominantInstruments: ["drums"])
        ]
        let analysis = SongAnalysis(title: "T", duration: 6, bpm: 128, beatTimes: [], barTimes: [], sections: sections)

        let sampleRate = DemoTrackSynth.sampleRate
        let samples = DemoTrackSynth.renderSamples(for: analysis)

        // --- Sample count matches the declared duration -----------------------------------------------------
        let expectedCount = Int((6.0 * Double(sampleRate)).rounded())
        expect(samples.count == expectedCount, "render must be duration·sampleRate samples (got \(samples.count), want \(expectedCount))")

        // --- Not silent, and always within [-1, 1] (soft-clipped) -------------------------------------------
        let peak = samples.map { abs($0) }.max() ?? 0
        expect(peak > 0.05, "the demo track must be audible, not silent (peak \(peak))")
        expect(samples.allSatisfy { $0 >= -1 && $0 <= 1 }, "samples must stay within [-1, 1] after soft-clip")

        // --- Section dynamics: the loud chorus is clearly louder than the quiet intro -----------------------
        func rms(_ startSec: Double, _ endSec: Double) -> Double {
            let a = Int(startSec * Double(sampleRate)), b = Int(endSec * Double(sampleRate))
            let slice = samples[a..<min(b, samples.count)]
            let sumSq = slice.reduce(0.0) { $0 + Double($1) * Double($1) }
            return (sumSq / Double(max(1, slice.count))).squareRoot()
        }
        let introRMS = rms(0.5, 2.5)
        let chorusRMS = rms(3.5, 5.5)
        expect(chorusRMS > introRMS * 1.4, "the chorus must swell clearly louder than the intro (intro \(introRMS), chorus \(chorusRMS))")

        // --- Deterministic: same analysis → byte-identical audio (the file cache relies on this) ------------
        let again = DemoTrackSynth.renderSamples(for: analysis)
        expect(samples == again, "the synth must be deterministic (same analysis → identical samples)")

        // --- Canonical 16-bit PCM WAV header + sizes --------------------------------------------------------
        let wav = DemoTrackSynth.wavData(fromMono: samples, sampleRate: sampleRate)
        let bytes = [UInt8](wav)
        func ascii(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
        func le16(_ at: Int) -> Int { Int(bytes[at]) | (Int(bytes[at + 1]) << 8) }
        func le32(_ at: Int) -> Int { Int(bytes[at]) | (Int(bytes[at + 1]) << 8) | (Int(bytes[at + 2]) << 16) | (Int(bytes[at + 3]) << 24) }

        let dataSize = samples.count * 2
        expect(bytes.count == 44 + dataSize, "WAV = 44-byte header + 2 bytes/sample (got \(bytes.count))")
        expect(ascii(0..<4) == "RIFF", "WAV must start with RIFF")
        expect(le32(4) == 36 + dataSize, "RIFF chunk size must be 36 + dataSize")
        expect(ascii(8..<12) == "WAVE", "WAV must declare the WAVE form")
        expect(ascii(12..<16) == "fmt ", "fmt chunk id")
        expect(le32(16) == 16, "PCM fmt chunk is 16 bytes")
        expect(le16(20) == 1, "audioFormat must be 1 (PCM)")
        expect(le16(22) == 1, "mono (1 channel)")
        expect(le32(24) == sampleRate, "sample rate must round-trip")
        expect(le32(28) == sampleRate * 2, "byteRate = sampleRate · channels · bytesPerSample")
        expect(le16(32) == 2, "blockAlign = channels · bytesPerSample")
        expect(le16(34) == 16, "16 bits per sample")
        expect(ascii(36..<40) == "data", "data chunk id")
        expect(le32(40) == dataSize, "data chunk size must equal the sample byte count")
    }

    // MARK: - SPEC 10: OpenAI cloud backend + fallback composer

    /// Builds a canonical OpenAI Responses envelope (HTTP 200) whose assistant `message` carries an
    /// `output_text` item holding `innerJSON` — the exact shape `OpenAILightingService.extractOutputText`
    /// walks (a leading `reasoning` item is included so the test also pins that non-message items are
    /// skipped). Returned as `(Data, URLResponse)` to match the injected `HTTPSend` boundary.
    private static func openAIEnvelopeData(innerJSON: String) -> Data {
        let envelope: [String: Any] = [
            "status": "completed",
            "output": [
                ["type": "reasoning", "summary": []],
                [
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        ["type": "output_text", "text": innerJSON]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: envelope, options: [])
    }

    /// A canonical Responses envelope whose message content is a `refusal` item (no `output_text`).
    private static func openAIRefusalData(reason: String) -> Data {
        let envelope: [String: Any] = [
            "status": "completed",
            "output": [
                [
                    "type": "message",
                    "content": [
                        ["type": "refusal", "refusal": reason]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: envelope, options: [])
    }

    /// An `HTTPSend` stub that always returns the given `Data` with an HTTP 200 response.
    private static func httpStub(returning data: Data) -> HTTPSend {
        return { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response)
        }
    }

    /// A wider-than-FOH, well-formed inner lighting look JSON: two cues, six fixtures (≥ 4), six-digit
    /// hex, and intensities inside 0...1 — exactly the DTO `OpenAILightingService.LookDTO` decodes.
    private static func validInnerLookJSON() -> String {
        """
        {
          "lookName": "Warm Opening to Bold Finale",
          "mood": "warm, building to bold",
          "cues": [
            { "name": "Opening" },
            { "name": "Finale" }
          ],
          "fixtures": [
            {
              "name": "Front Wash L",
              "type": "frontFresnel",
              "zone": "frontOfHouse",
              "states": [
                { "enabled": true, "intensity": 0.55, "colorHex": "#FFD1A3", "beamAngleDegrees": 40, "gobo": "none" },
                { "enabled": true, "intensity": 0.85, "colorHex": "#FFE4C2", "beamAngleDegrees": 40, "gobo": "none" }
              ]
            },
            {
              "name": "Front Wash R",
              "type": "ledFresnel",
              "zone": "frontOfHouse",
              "states": [
                { "enabled": true, "intensity": 0.5, "colorHex": "#FFD1A3", "beamAngleDegrees": 45, "gobo": "none" },
                { "enabled": true, "intensity": 0.8, "colorHex": "#FFE4C2", "beamAngleDegrees": 45, "gobo": "none" }
              ]
            },
            {
              "name": "Back Wash",
              "type": "backgroundBatten",
              "zone": "upstageTruss",
              "states": [
                { "enabled": true, "intensity": 0.4, "colorHex": "#3A6BFF", "beamAngleDegrees": 60, "gobo": "stars" },
                { "enabled": true, "intensity": 0.9, "colorHex": "#1E4FE0", "beamAngleDegrees": 60, "gobo": "none" }
              ]
            },
            {
              "name": "Moving Beam L",
              "type": "movingHeadBeam",
              "zone": "sideStageLeft",
              "states": [
                { "enabled": false, "intensity": 0.0, "colorHex": "#000000", "beamAngleDegrees": 12, "gobo": "none" },
                { "enabled": true, "intensity": 0.95, "colorHex": "#22CCFF", "beamAngleDegrees": 12, "gobo": "breakup" }
              ]
            },
            {
              "name": "Moving Beam R",
              "type": "movingHeadBeam",
              "zone": "sideStageRight",
              "states": [
                { "enabled": false, "intensity": 0.0, "colorHex": "#000000", "beamAngleDegrees": 12, "gobo": "none" },
                { "enabled": true, "intensity": 0.95, "colorHex": "#22CCFF", "beamAngleDegrees": 12, "gobo": "breakup" }
              ]
            },
            {
              "name": "Laser Fan",
              "type": "laser",
              "zone": "floor",
              "states": [
                { "enabled": false, "intensity": 0.0, "colorHex": "#000000", "beamAngleDegrees": 8, "gobo": "none" },
                { "enabled": true, "intensity": 1.0, "colorHex": "#39FF14", "beamAngleDegrees": 8, "gobo": "none" }
              ]
            }
          ],
          "explanation": {
            "term": "Contrast",
            "plainText": "Contrast is the brightness difference between the performer and the backdrop.",
            "actionSummary": "Warmed the front wash and deepened the back wash, then added beams and a laser for the finale."
          }
        }
        """
    }

    // SPEC 10 work item 8.1 — happy path: a valid Responses envelope whose inner output_text holds a
    // well-formed lighting look decodes through OpenAILightingService's DTO + the SHARED validator and
    // surfaces as `.openAI`. Uses an injected HTTPSend stub + fixed key provider — no network, no key.
    private static func openAIServiceDecodesAndValidates() async throws {
        let service = OpenAILightingService(
            httpSend: httpStub(returning: openAIEnvelopeData(innerJSON: validInnerLookJSON())),
            apiKeyProvider: { "sk-test-fixed-key" }
        )

        expect(service.availability.isAvailable, "A non-empty key provider should make the service available")

        let result = try await service.generateLook(from: "為校園音樂之夜做一個由暖轉烈的燈光秀")

        // The shared validator is authoritative — the look it produced must itself pass validate().
        try result.look.validate()
        expect(result.source == .openAI, "A look generated by the OpenAI backend must report source .openAI")
        expect(result.look.cues.map(\.id) == ["cue_0", "cue_1"], "Two model cues should assemble as cue_0/cue_1")
        expect(result.look.selectedCueId == "cue_0", "The first cue should be selected")
        expect(result.look.cues[0].fixtureGroups.count == 6, "All six model fixtures should be assembled into the rig")
        // A fixture the model marked off must assemble dark (enabled:false → intensity 0).
        let openingBeam = result.look.cues[0].fixtureGroups.first { $0.id == "fixture_3" }
        expect(openingBeam?.intensity == 0, "A model-disabled fixture must assemble to 0 intensity in the opening cue")
    }

    // SPEC 10 work item 8.2 — a `refusal` content item short-circuits to a refusal failure WITHOUT
    // attempting to decode it as a look. Asserts the exact 繁中 `.generationFailed` message.
    private static func openAIServiceSurfacesRefusal() async {
        let service = OpenAILightingService(
            httpSend: httpStub(returning: openAIRefusalData(reason: "I can't help with that.")),
            apiKeyProvider: { "sk-test-fixed-key" }
        )

        do {
            _ = try await service.generateLook(from: "做一個燈光秀")
            fatalError("A refusal content item must throw, not return a look")
        } catch let error as LightingGenerationError {
            expect(error == .generationFailed("模型拒絕生成燈光效果。請嘗試換個說法。"),
                   "A refusal must map to the verbatim 繁中 .generationFailed refusal message")
        } catch {
            fatalError("Expected LightingGenerationError.generationFailed, got \(error)")
        }
    }

    // SPEC 10 work item 8.3 — proves the schema is NOT trusted for range/hex: an inner JSON whose
    // intensity exceeds 1.0 (and which carries a malformed hex) is rejected by the SHARED validator, so
    // generateLook throws `.generationFailed` (wrapping the ValidationError's message), never returns it.
    private static func openAIServiceRejectsOutOfRangeViaValidator() async {
        // Out-of-range intensity (1.8) on an otherwise structurally valid look. The schema's numeric
        // bounds are hints only; the post-parse validate() must catch this.
        let badInnerJSON = """
        {
          "lookName": "Out Of Range",
          "mood": "test",
          "cues": [ { "name": "A" }, { "name": "B" } ],
          "fixtures": [
            {
              "name": "Front",
              "type": "frontFresnel",
              "zone": "frontOfHouse",
              "states": [
                { "enabled": true, "intensity": 1.8, "colorHex": "#FFD1A3", "beamAngleDegrees": 40, "gobo": "none" },
                { "enabled": true, "intensity": 0.9, "colorHex": "#FFE4C2", "beamAngleDegrees": 40, "gobo": "none" }
              ]
            },
            {
              "name": "Back",
              "type": "backgroundBatten",
              "zone": "upstageTruss",
              "states": [
                { "enabled": true, "intensity": 0.5, "colorHex": "#3A6BFF", "beamAngleDegrees": 60, "gobo": "none" },
                { "enabled": true, "intensity": 0.8, "colorHex": "#1E4FE0", "beamAngleDegrees": 60, "gobo": "none" }
              ]
            },
            {
              "name": "Wash L",
              "type": "washBar",
              "zone": "sideStageLeft",
              "states": [
                { "enabled": true, "intensity": 0.5, "colorHex": "#FFFFFF", "beamAngleDegrees": 50, "gobo": "none" },
                { "enabled": true, "intensity": 0.7, "colorHex": "#FFFFFF", "beamAngleDegrees": 50, "gobo": "none" }
              ]
            },
            {
              "name": "Wash R",
              "type": "washBar",
              "zone": "sideStageRight",
              "states": [
                { "enabled": true, "intensity": 0.5, "colorHex": "#FFFFFF", "beamAngleDegrees": 50, "gobo": "none" },
                { "enabled": true, "intensity": 0.7, "colorHex": "#FFFFFF", "beamAngleDegrees": 50, "gobo": "none" }
              ]
            }
          ],
          "explanation": { "term": "Intensity", "plainText": "How strong a light is.", "actionSummary": "test." }
        }
        """

        let service = OpenAILightingService(
            httpSend: httpStub(returning: openAIEnvelopeData(innerJSON: badInnerJSON)),
            apiKeyProvider: { "sk-test-fixed-key" }
        )

        do {
            _ = try await service.generateLook(from: "做一個燈光秀")
            fatalError("An out-of-range intensity must be rejected by the shared validator, not returned")
        } catch let error as LightingGenerationError {
            // The validator rejected the parsed look; the service must surface it as .generationFailed
            // (never .modelUnavailable). The wrapped message is the ValidationError's own description.
            guard case .generationFailed(let message) = error else {
                fatalError("Out-of-range intensity must throw .generationFailed, got \(error)")
            }
            expect(message == (ValidationError.invalidIntensity(1.8).errorDescription ?? "生成的燈光效果無效。"),
                   "A validator rejection should surface the ValidationError's own 繁中 message")
        } catch {
            fatalError("Expected LightingGenerationError.generationFailed, got \(error)")
        }
    }

    // SPEC 10 work item 8.4 — the OpenAI-primary / FM-secondary composer: when the primary throws, the
    // result comes from the secondary (source .foundationModels); when the primary succeeds, the
    // secondary is never invoked.
    private static func fallbackServiceFallsBackWhenPrimaryThrows() async throws {
        let secondaryLook = LightingLook.mvpDemo()

        // Primary throws .generationFailed; secondary returns a fixed FM look → result is the secondary's.
        let throwingPrimary = StubLightingService(
            availability: .available,
            result: .failure(.generationFailed("OpenAI 服務暫時無法使用，請稍後再試。"))
        )
        let fmSecondary = SpyLightingService(
            availability: .available,
            result: .success(LightingGenerationResult(look: secondaryLook, source: .foundationModels))
        )

        let fallback = FallbackLightingService(primary: throwingPrimary, secondary: fmSecondary)
        let result = try await fallback.generateLook(from: "做一個暖色開場")
        expect(result.source == .foundationModels, "When the primary throws, the fallback must return the secondary's result")
        try result.look.validate()
        expect(fmSecondary.callCount == 1, "The secondary must be invoked exactly once when the primary fails")

        // Primary succeeds → secondary must NOT be invoked.
        let openAILook = LightingLook.mvpDemo()
        let succeedingPrimary = StubLightingService(
            availability: .available,
            result: .success(LightingGenerationResult(look: openAILook, source: .openAI))
        )
        let untouchedSecondary = SpyLightingService(
            availability: .available,
            result: .success(LightingGenerationResult(look: secondaryLook, source: .foundationModels))
        )

        let happyPath = FallbackLightingService(primary: succeedingPrimary, secondary: untouchedSecondary)
        let happyResult = try await happyPath.generateLook(from: "做一個暖色開場")
        expect(happyResult.source == .openAI, "On the primary-success path the result must be the primary's")
        expect(untouchedSecondary.callCount == 0, "The secondary must NOT be invoked when the primary succeeds")
    }

    // MARK: - SPEC 05 P1: music → show + rig constraint

    private static func songAnalysisMakeBeatClockCoversThreePaths() {
        // Path 1: explicit bpm → uses it directly with the first beat as the offset.
        let withBpm = SongAnalysis(title: "A", duration: 60, bpm: 120, beatTimes: [0.5, 1.0, 1.5],
                                   barTimes: [], sections: [])
        let clock1 = withBpm.makeBeatClock()
        expect(clock1?.bpm == 120, "Explicit bpm must drive the clock directly")
        expect(clock1?.startOffset == 0.5, "First beat is the downbeat offset")

        // Path 2: nil bpm but ≥2 beats → estimate from the median inter-beat interval (0.5s → 120bpm).
        let estimated = SongAnalysis(title: "B", duration: 60, bpm: nil,
                                     beatTimes: [1.0, 1.5, 2.0, 2.5], barTimes: [], sections: [])
        let clock2 = estimated.makeBeatClock()
        let estBpm = clock2?.bpm ?? 0
        expect(abs(estBpm - 120) < 0.001, "0.5s median gap must estimate 120 bpm, got \(estBpm)")
        expect(clock2?.startOffset == 1.0, "Estimated clock still anchors on the first beat")

        // Path 3: no usable tempo (nil bpm, <2 beats) → nil.
        let none = SongAnalysis(title: "C", duration: 60, bpm: nil, beatTimes: [], barTimes: [], sections: [])
        expect(none.makeBeatClock() == nil, "No bpm and no beats must yield no clock")
        let oneBeat = SongAnalysis(title: "D", duration: 60, bpm: nil, beatTimes: [2.0], barTimes: [], sections: [])
        expect(oneBeat.makeBeatClock() == nil, "A single beat is not enough to estimate tempo")
    }

    private static func songAnalysisRoundTripsAndMeasuresSectionDuration() throws {
        let section = SongSection(start: 10, end: 28, kind: .chorus, pace: 0.8, loudness: 0.7,
                                  keyMode: .major, dominantInstruments: ["drums", "vocals"])
        expect(section.duration == 18, "Section duration is end - start")

        let analysis = SongAnalysis(
            title: "Demo", duration: 150, bpm: 128, beatTimes: [0, 0.47, 0.94],
            barTimes: [0, 1.88], sections: [section]
        )
        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(SongAnalysis.self, from: data)
        expect(decoded == analysis, "SongAnalysis must round-trip through Codable unchanged")
    }

    private static func showPlanProducesBoundedCuesWithRanges() {
        // Six distinct sections; with maxCues 4 the plan keeps the four longest as boundaries.
        let sections = [
            SongSection(start: 0, end: 12, kind: .intro, pace: 0.2, loudness: 0.2, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 12, end: 40, kind: .verse, pace: 0.4, loudness: 0.4, keyMode: .minor, dominantInstruments: ["vocals"]),
            SongSection(start: 40, end: 80, kind: .chorus, pace: 0.9, loudness: 0.9, keyMode: .major, dominantInstruments: ["drums"]),
            SongSection(start: 80, end: 100, kind: .bridge, pace: 0.5, loudness: 0.5, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 100, end: 140, kind: .drop, pace: 1.0, loudness: 0.95, keyMode: .major, dominantInstruments: ["drums"]),
            SongSection(start: 140, end: 150, kind: .outro, pace: 0.15, loudness: 0.2, keyMode: .minor, dominantInstruments: [])
        ]
        let analysis = SongAnalysis(title: "T", duration: 150, bpm: 120, beatTimes: [0], barTimes: [], sections: sections)
        let plan = ShowPlan.make(from: analysis, maxCues: 4, minCueSeconds: 8)

        expect(plan.cues.count >= 2 && plan.cues.count <= 4, "Cue count must land in [2, maxCues], got \(plan.cues.count)")
        for cue in plan.cues {
            expect((0...1).contains(cue.energy), "energy in 0...1")
            expect((0...1).contains(cue.suggestedIntensity), "suggestedIntensity in 0...1")
            // suggestedIntensity = clamp(0.35 + 0.6*energy)
            let expected = min(max(0.35 + 0.6 * cue.energy, 0), 1)
            expect(abs(cue.suggestedIntensity - expected) < 1e-9, "suggestedIntensity must follow the formula")
            expect(cue.highEnergy == (cue.energy >= LightEffectPlan.highEnergyThreshold),
                   "highEnergy must align to LightEffectPlan.highEnergyThreshold")
        }

        // A high-energy section (pace 0.9, loud 0.9) → energy 0.9 ≥ 0.6 → highEnergy.
        let chorusEnergy = CueBrief.energy(pace: 0.9, loudness: 0.9)
        expect(chorusEnergy >= 0.6, "A loud, fast chorus must read as high energy")
    }

    private static func showPlanMergesShortSectionsAndPadsEmpty() {
        // A sub-minimum section folds into the previous cue, so two adjacent sections collapse to one.
        let sections = [
            SongSection(start: 0, end: 30, kind: .verse, pace: 0.4, loudness: 0.4, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 30, end: 33, kind: .breakdown, pace: 0.5, loudness: 0.5, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 33, end: 70, kind: .chorus, pace: 0.8, loudness: 0.8, keyMode: .major, dominantInstruments: [])
        ]
        let analysis = SongAnalysis(title: "M", duration: 70, bpm: 120, beatTimes: [0], barTimes: [], sections: sections)
        let plan = ShowPlan.make(from: analysis, maxCues: 6, minCueSeconds: 8)
        // The 3s breakdown folds into the verse → 2 resulting cues (verse-merged + chorus).
        expect(plan.cues.count == 2, "A 3s section under minCueSeconds must fold into the previous cue, got \(plan.cues.count)")

        // Empty analysis → padded to exactly 2 neutral cues.
        let empty = SongAnalysis(title: "E", duration: 0, bpm: nil, beatTimes: [], barTimes: [], sections: [])
        let emptyPlan = ShowPlan.make(from: empty)
        expect(emptyPlan.cues.count == 2, "An empty analysis must pad to 2 neutral cues, got \(emptyPlan.cues.count)")
    }

    private static func rigConstraintClampsRemapsAndIsIdempotent() throws {
        // A look with 4 fixtures of mixed models across two cues (rig identity: same ids/order per cue).
        func cue(id: String, name: String) -> LightingCue {
            LightingCue(id: id, name: name, transition: .mvpDefault, fixtureGroups: [
                FixtureGroup(id: "f1", name: "1", role: .frontLight, zone: .stageFront, enabled: true,
                             intensity: 0.6, color: FixtureColor(mode: .rgb, value: "#FFFFFF"), model: .frontFresnel),
                FixtureGroup(id: "f2", name: "2", role: .spot, zone: .stageBack, enabled: true,
                             intensity: 0.6, color: FixtureColor(mode: .rgb, value: "#00FF00"), model: .laser),
                FixtureGroup(id: "f3", name: "3", role: .wash, zone: .fullStage, enabled: true,
                             intensity: 0.6, color: FixtureColor(mode: .rgb, value: "#0000FF"), model: .ledPar),
                FixtureGroup(id: "f4", name: "4", role: .spot, zone: .stageBack, enabled: true,
                             intensity: 0.6, color: FixtureColor(mode: .rgb, value: "#FF0000"), model: .movingHeadBeam)
            ])
        }
        let look = LightingLook(
            schemaVersion: "1.0", intent: .generateLook, lookName: "L", mood: "m",
            ambient: AmbientState(preset: .standardNight, level: 0.35, colorTemperature: 4200),
            selectedCueId: "cA",
            cues: [cue(id: "cA", name: "Opening"), cue(id: "cB", name: "Highlight")],
            explanation: LightingExplanation(term: "t", plainText: "p", actionSummary: "a")
        )
        try look.validate()

        // isUnconstrained → passthrough unchanged.
        let unconstrained = RigConstraint(fixtureCount: nil, allowedModels: [])
        expect(unconstrained.enforce(on: look) == look, "An unconstrained rig must return the look unchanged")

        // Over-count clamp to 2 (tail dropped in rig order), plus a model whitelist that doesn't include
        // the laser (.movingHeadBeam shares the spot role → laser remaps to it).
        let constraint = RigConstraint(fixtureCount: 2, allowedModels: [.frontFresnel, .movingHeadBeam])
        let enforced = constraint.enforce(on: look)

        for c in enforced.cues {
            expect(c.fixtureGroups.count == 2, "Count must clamp to fixtureCount=2, got \(c.fixtureGroups.count)")
            for fixture in c.fixtureGroups {
                expect([.frontFresnel, .movingHeadBeam].contains(fixture.renderModel),
                       "Every kept fixture must use a whitelisted model, got \(fixture.renderModel)")
            }
        }
        // Per-cue fixtureId consistency (rig identity preserved across cues).
        let idsA = enforced.cues[0].fixtureGroups.map(\.id)
        let idsB = enforced.cues[1].fixtureGroups.map(\.id)
        expect(idsA == idsB, "Every cue must keep the same fixtureId set/order after enforce")
        expect(idsA == ["f1", "f2"], "Tail fixtures must be dropped in rig order")
        // f2 was a laser (spot role) not in the whitelist → remapped to .movingHeadBeam (the spot-role allowed model).
        let f2 = enforced.cues[0].fixtureGroups.first { $0.id == "f2" }
        expect(f2?.renderModel == .movingHeadBeam, "A non-allowed laser must remap to the same-role allowed model")
        try enforced.validate()

        // Idempotence: enforcing again changes nothing.
        let twice = constraint.enforce(on: enforced)
        expect(twice == enforced, "enforce must be idempotent on an already-compliant look")
    }

    private static func musicShowBuilderBuildsValidatedSymmetricShow() throws {
        // Major, high-energy chorus + minor, low-energy verse → decidable warm/cool + effect/none.
        let sections = [
            SongSection(start: 0, end: 40, kind: .verse, pace: 0.2, loudness: 0.2, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 40, end: 90, kind: .chorus, pace: 0.95, loudness: 0.95, keyMode: .major, dominantInstruments: ["drums"])
        ]
        let analysis = SongAnalysis(title: "S", duration: 90, bpm: 128, beatTimes: [0], barTimes: [], sections: sections)
        let plan = ShowPlan.make(from: analysis)
        expect(plan.cues.count == 2, "Two distinct long sections → two cues")

        let unconstrained = RigConstraint(fixtureCount: nil, allowedModels: [])
        let look = try MusicShowBuilder.buildLook(plan: plan, rig: unconstrained, lookName: "音樂秀")

        // One cue per CueBrief; every cue validates (makeValidatedLook already ran validate()).
        expect(look.cues.count == plan.cues.count, "Cue count must equal plan.cues count")
        try look.validate()

        // Rig is even-sized and ≤ 8 (symmetric pairs, no lone laser).
        let rigSize = look.cues[0].fixtureGroups.count
        expect(rigSize <= 8 && rigSize % 2 == 0, "Rig must be symmetric (even) and ≤ 8, got \(rigSize)")

        // Identify the verse (low energy, minor) and chorus (high energy, major) cues by name.
        let verseCue = try expectUnwrapped(look.cues.first { $0.name == CueBrief.displayName(for: .verse) }, "verse cue present")
        let chorusCue = try expectUnwrapped(look.cues.first { $0.name == CueBrief.displayName(for: .chorus) }, "chorus cue present")

        // Major/minor color-temp is decidable on a non-front accent fixture: major redder than minor bluer.
        func accent(_ cue: LightingCue) -> RGBComponents {
            let fixture = cue.fixtureGroups.first { $0.role != .frontLight } ?? cue.fixtureGroups[0]
            return fixture.color.rgbComponents
        }
        let majorRGB = accent(chorusCue)
        let minorRGB = accent(verseCue)
        expect(majorRGB.red > majorRGB.blue, "Major (chorus) accent must skew warm (red > blue)")
        expect(minorRGB.blue > minorRGB.red, "Minor (verse) accent must skew cool (blue > red)")

        // High-energy chorus gives a mover/strobe a dynamic effect; low-energy verse runs none.
        let chorusEffects = LightEffectPlan.effects(for: chorusCue)
        expect(chorusEffects.contains { $0.isAnimated }, "A high-energy cue must drive at least one dynamic effect")
        let verseHasAuthored = verseCue.fixtureGroups.contains { ($0.effect?.isAnimated ?? false) }
        expect(!verseHasAuthored, "A low-energy cue must author no dynamic effect")

        // Post-enforce compliance: a count+model lock yields a compliant look.
        let constrained = RigConstraint(fixtureCount: 4, allowedModels: [.frontFresnel, .movingHeadBeam])
        let lockedLook = try MusicShowBuilder.buildLook(plan: plan, rig: constrained, lookName: "鎖定秀")
        for c in lockedLook.cues {
            expect(c.fixtureGroups.count <= 4, "Locked rig must respect fixtureCount")
            for fixture in c.fixtureGroups {
                expect([.frontFresnel, .movingHeadBeam].contains(fixture.renderModel),
                       "Locked rig must only use whitelisted models")
            }
        }
        try lockedLook.validate()
    }

    // BUG 5: the music show's two lasers must land MIRRORED (one far left, one far right), not both on the
    // right. Resolve placements through RigPlacement exactly as the renderer does (per-zone slot in
    // fixtureGroups order) and assert laser_l.x < centerX < laser_r.x.
    private static func musicShowLasersAreMirroredLeftAndRight() throws {
        let sections = [
            SongSection(start: 0, end: 40, kind: .verse, pace: 0.2, loudness: 0.2, keyMode: .minor, dominantInstruments: []),
            SongSection(start: 40, end: 90, kind: .chorus, pace: 0.95, loudness: 0.95, keyMode: .major, dominantInstruments: ["drums"])
        ]
        let analysis = SongAnalysis(title: "S", duration: 90, bpm: 128, beatTimes: [0], barTimes: [], sections: sections)
        let plan = ShowPlan.make(from: analysis)
        let unconstrained = RigConstraint(fixtureCount: nil, allowedModels: [])
        // Default rig (maxFixtures 8) keeps the full palindromic back zone, so both lasers stay mirrored.
        let look = try MusicShowBuilder.buildLook(plan: plan, rig: unconstrained, lookName: "音樂秀", maxFixtures: 8)

        let layout = StageLayout.defaultStudentOutdoor()
        let cue = look.cues[0]
        let centerX = layout.objects.first { $0.type == .stageBase }?.position.x ?? 0

        // Reproduce the renderer's per-zone slot assignment (ImmersiveView.syncRig).
        var zoneTotals: [StageZone: Int] = [:]
        for fixture in cue.fixtureGroups { zoneTotals[fixture.zone, default: 0] += 1 }
        var zoneSlots: [StageZone: Int] = [:]
        var laserX: [String: Double] = [:]
        for fixture in cue.fixtureGroups {
            let slot = zoneSlots[fixture.zone, default: 0]
            zoneSlots[fixture.zone] = slot + 1
            let placement = RigPlacement.resolvedPlacement(
                fixture: fixture, slot: slot, count: zoneTotals[fixture.zone] ?? 1, layout: layout)
            if fixture.id == "laser_l" || fixture.id == "laser_r" {
                laserX[fixture.id] = placement.position.x
            }
        }

        let lx = try expectUnwrapped(laserX["laser_l"], "laser_l must be present in the default rig")
        let rx = try expectUnwrapped(laserX["laser_r"], "laser_r must be present in the default rig")
        expect(lx < centerX, "laser_l must sit left of center (got \(lx) vs center \(centerX))")
        expect(rx > centerX, "laser_r must sit right of center (got \(rx) vs center \(centerX))")
        expect(lx < rx, "laser_l must be left of laser_r — the pair must be mirrored, not both on one side")
    }

    private static func legacyProjectJSONDecodesToUnconstrainedRig() throws {
        // A project encoded WITHOUT the rigConstraint key (old save) must decode to unconstrained.
        let layout = StageLayout.defaultStudentOutdoor()
        let layoutData = try JSONEncoder().encode(layout)
        let layoutJSON = try expectUnwrapped(
            JSONSerialization.jsonObject(with: layoutData) as? [String: Any],
            "stage layout must encode to a JSON object"
        )
        let lookData = try JSONEncoder().encode(LightingLook.mvpDemo())
        let lookJSON = try expectUnwrapped(
            JSONSerialization.jsonObject(with: lookData) as? [String: Any],
            "lighting look must encode to a JSON object"
        )
        let legacy: [String: Any] = [
            "id": "legacy_1",
            "name": "舊專案",
            "venueDescription": "戶外",
            "eventType": "展演",
            "lastEditedDescription": "舊存檔",
            "stageLayout": layoutJSON,
            "lightingLook": lookJSON
            // no rigConstraint key
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let project = try JSONDecoder().decode(LumaStageProject.self, from: data)
        expect(project.rigConstraint.isUnconstrained,
               "A legacy project JSON without rigConstraint must decode to an unconstrained rig")
    }

    // SPEC 12 WI-2: the Foundation-only selection seam. Pins the loopback's browse/search/resolve
    // behaviour so the platform `MusicKitSongLibrary` and the UI can be written against this contract.
    private static func songLibraryLoopbackBrowsesAndResolves() async {
        let resolved = URL(fileURLWithPath: "/tmp/luma-loopback-song.m4a")
        let items = [
            SongLibraryItem(id: "1", title: "Neon Skyline", artist: "Aurora", duration: 211, isProtected: false),
            SongLibraryItem(id: "2", title: "Midnight Drive", artist: "Aurora", duration: 184, isProtected: false),
            SongLibraryItem(id: "3", title: "Quiet Harbor", artist: "Lumen", duration: 0, isProtected: true)
        ]
        let library = LoopbackSongLibrary(items: items, resolvedURL: resolved)

        // search filters by title (case-insensitive) and by artist.
        let byTitle = await library.search("neon")
        expect(byTitle.map(\.id) == ["1"], "search must match title case-insensitively")
        let byArtist = await library.search("AURORA")
        expect(byArtist.map(\.id) == ["1", "2"], "search must match artist case-insensitively")
        let none = await library.search("nope")
        expect(none.isEmpty, "search with no match must return empty")

        // recentSongs respects the limit.
        let recent = await library.recentSongs(limit: 2)
        expect(recent.map(\.id) == ["1", "2"], "recentSongs must return the first `limit` items")

        // a non-protected item resolves to the injected URL.
        do {
            let url = try await library.resolvePlayableURL(for: items[0])
            expect(url == resolved, "resolvePlayableURL must return the injected URL for a non-protected item")
        } catch {
            fatalError("resolvePlayableURL should not throw for a non-protected item, got \(error)")
        }

        // a protected item throws .protected.
        do {
            _ = try await library.resolvePlayableURL(for: items[2])
            fatalError("resolvePlayableURL must throw for a protected item")
        } catch let error as SongSourceError {
            expect(error == .protected, "protected item must throw .protected, got \(error)")
        } catch {
            fatalError("protected item must throw SongSourceError.protected, got \(error)")
        }
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

// MARK: - Test doubles for the FallbackLightingService composer (SPEC 10 work item 8.4)

/// A fixed `LightingLookGenerating` stub that reports a chosen availability and either succeeds with a
/// fixed result or throws a fixed `LightingGenerationError`. Used as the FallbackLightingService primary.
private struct StubLightingService: LightingLookGenerating {
    let availability: LightingModelAvailability
    let result: Result<LightingGenerationResult, LightingGenerationError>

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        try result.get()
    }
}

/// Like `StubLightingService` but a reference type that records how many times `generateLook` ran, so a
/// test can assert the composer DID (or did NOT) reach the secondary backend.
private final class SpyLightingService: LightingLookGenerating {
    let availability: LightingModelAvailability
    let result: Result<LightingGenerationResult, LightingGenerationError>
    private(set) var callCount = 0

    init(availability: LightingModelAvailability,
         result: Result<LightingGenerationResult, LightingGenerationError>) {
        self.availability = availability
        self.result = result
    }

    func generateLook(from prompt: String) async throws -> LightingGenerationResult {
        callCount += 1
        return try result.get()
    }
}
