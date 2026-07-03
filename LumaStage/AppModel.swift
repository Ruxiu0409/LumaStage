//
//  AppModel.swift
//  LumaStage
//
//  Created by Tsai Cheng-Yeh on 2026/5/20.
//

import SwiftUI
import Observation
import QuartzCore

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    static let fixtureObservatoryWindowID = "FixtureObservatory"
    static let fixtureInfoCardWindowID = "FixtureInfoCard"
    /// The AI composer rides in its own native window — opened with the immersive space — so it
    /// gets the system move bar and smooth, compositor-driven dragging instead of a hand-rolled
    /// RealityView-attachment drag.
    static let aiComposerWindowID = "AIComposer"
    /// The selected-light control card's own native window (converted from a RealityKit attachment so it
    /// gets the system move bar). Opened/dismissed by `ImmersiveView` (the view agent wires that).
    static let lightControlWindowID = "light-control"
    /// The tabletop stage editor's dedicated **mixed (passthrough)** immersive space: a small editable
    /// stage model that ARKit rests on the user's real table. It *replaces* the 1:1 stage space while
    /// editing (only one immersive space can be open at a time); `ContentView` swaps between them via
    /// `desiredImmersiveScene`.
    let tabletopEditorSpaceID = "TabletopEditorSpace"
    /// The launch/project window (`ContentView`). It carries an explicit id so it can be *dismissed*
    /// while the immersive stage or the fixture observatory is showing — otherwise the window lingers
    /// as nothing but its empty, draggable system bar (its content collapses to a 1x1 clear view, but
    /// visionOS keeps drawing the window's move/grabber bar). Reopened when those return.
    static let mainWindowID = "Main"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    /// Which immersive space the app *wants* open. The stage space and the tabletop-editor space are
    /// mutually exclusive (visionOS allows one open immersive space), so entering/leaving editing flips
    /// this and `ContentView` reconciles it — opening the named space whenever the main window is back and
    /// no space is currently open. Driving the swap from the always-recreated main window (rather than from
    /// inside a space, which gets torn down mid-transition) is what keeps the hand-off reliable.
    enum ImmersiveScene: Equatable {
        case none
        case stage
        case tabletopEditor
    }

    enum ConversationState: String {
        case idle
        case listening
        case transcribing
        case interpreting
        case applying
        case explaining
        case error

        var displayName: String {
            switch self {
            case .idle:
                return "待命"
            case .listening:
                return "聆聽中"
            case .transcribing:
                return "轉錄中"
            case .interpreting:
                return "解讀中"
            case .applying:
                return "套用中"
            case .explaining:
                return "說明中"
            case .error:
                return "錯誤"
            }
        }
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    /// The immersive space the app wants open; `ContentView` reconciles it. Defaults to `.none` (project
    /// list). Set to `.stage` when a project opens, `.tabletopEditor` while editing the stage on the table.
    var desiredImmersiveScene: ImmersiveScene = .none
    var stageImmersionMode: StageImmersionMode = .fullStage

    /// Whether the in-app relight debug panel (toggled from the AI composer) is showing. Off by default.
    var isDebugPanelVisible = false

    /// Voice-only / accessibility mode: when on, every generation, cue change, and single-light edit is
    /// spoken aloud via `SpeechNarrator`, so the whole design loop (generate → step cues with "go" →
    /// hear the result) is usable without seeing the floating composer. Off by default.
    var isVoiceNarrationEnabled = false

    /// Manual per-light overrides (the deterministic control layer), keyed by `StageLightID.number`.
    /// Layered on top of the generative cue by the renderer; persists across AI generations until
    /// cleared ("all lights on" / "reset lights"). Empty = every light follows the cue.
    var lightOverrides: [Int: LightOverride] = [:]

    /// SPEC 08 — group submasters (the fast live-control unit). `groups` is auto-derived from the
    /// current rig's role/zone/type on every look change; `groupMasters` is the transient ride layer
    /// keyed by `StandardFixtureGroup.id` (only groups actively ridden carry an entry). The renderer
    /// folds these into the SAME cue → override resolution (NOT a second override state) and they reset
    /// alongside `lightOverrides` on a new rig.
    var groups: [FixtureGroupMask] = []
    var groupMasters: [String: Double] = [:]

    /// Fixture observatory (volumetric) state. `isInspectingFixture` hides the project window while
    /// the observatory is open; `fixtureCarousel` is the single shared paging state for the two
    /// separate observatory windows (the volumetric model and the info card), so paging in the card
    /// drives the model and vice versa.
    var isInspectingFixture = false
    var fixtureCarousel = FixtureCarousel()

    /// Tabletop stage editor state: whether an editing session is active (the dedicated passthrough editor
    /// immersive space), and which stage object is currently selected for move/rotate. Edits persist through
    /// `saveStageLayout`, so the immersive 1:1 stage reflects them.
    var isEditingTabletopStage = false
    var selectedStageObjectId: String?
    /// The rig fixture (by `id`) currently selected in the tabletop editor for move/remove. Reset to nil
    /// whenever the rig changes out from under it (project open / AI regenerate), mirroring `lightOverrides`.
    var selectedFixtureId: String? = nil
    var conversationState: ConversationState = .idle
    var projects = LumaStageProject.defaultProjects()
    var selectedProjectId: String?

    var stageState = StageState(lightingLook: .mvpDemo())
    var transcript = ""
    var typedPrompt = ""
    var aiUnderstoodCommand = "等待語音或文字輸入"
    var lastExplanation = LightingLook.mvpDemo().explanation
    var generationSource: LightingGenerationSource = .openAI
    private(set) var modelAvailability: LightingModelAvailability = .available
    var lastError: String?

    let speechTranscriber = SpeechTranscriber()

    /// Speaks feedback aloud when `isVoiceNarrationEnabled`. ObservationIgnored — it's an output sink,
    /// not observable state. (Constructing the synthesizer is cheap; it stays silent until `speak`.)
    @ObservationIgnored
    private let narrator = SpeechNarrator()

    @ObservationIgnored
    private let aiClient: any LightingLookGenerating

    // MARK: - Music sync (SPEC 05 owner C)
    //
    // The deterministic "song → multi-cue show" surface owner D's UI drives. `songAnalyzer` is the
    // injectable analysis boundary (same pattern as `aiClient`); `musicSyncEngine` owns playback + the
    // cross-thread beat clock the `LightEffectSystem` reads. The last analysis/plan are kept so the show
    // can be rebuilt (e.g. when the rig constraint changes) without re-analyzing.

    /// Injectable song-analysis boundary. Default is the on-device `MusicUnderstandingService`; tests /
    /// previews inject `PreviewSongAnalyzer` / `CachedSongAnalyzer` / a mock.
    @ObservationIgnored
    private let songAnalyzer: any SongAnalyzing

    /// Injectable 音樂資料庫瀏覽邊界（SPEC 12）。預設為平台實作 `MusicKitSongLibrary`；測試 / 預覽注入
    /// `LoopbackSongLibrary`。讓使用者從裝置資料庫挑曲，解析到可讀檔案 URL 後餵進既有的 `importSong` 管線。
    @ObservationIgnored
    private let songLibrary: any SongLibraryBrowsing

    /// Playback + render-thread beat clock for music-synced shows.
    @ObservationIgnored
    let musicSyncEngine = MusicSyncEngine()

    /// The most recent analysis + plan, retained so `setRigConstraint` can rebuild the show in place.
    @ObservationIgnored
    private var lastAnalysis: SongAnalysis?
    @ObservationIgnored
    private var lastPlan: ShowPlan?
    /// The beat clock for the loaded show, kept so the clock-only demo path (no playable audio) can still
    /// anchor `MusicSyncClockSource` and beat-lock the visuals from `playMusicShow()`.
    @ObservationIgnored
    private var lastClock: MusicBeatClock?
    /// True when the loaded show has no playable audio (the built-in demo): `playMusicShow` then anchors the
    /// beat clock directly so the visuals still lock, since the audio engine can't `play()` without a player.
    @ObservationIgnored
    private var musicShowIsClockOnly = false

    /// Whether a music-driven show is loaded (analysis present + a show built from it).
    var isMusicShowActive = false
    /// Mirrors `musicSyncEngine.isPlaying` so the UI can observe it on `AppModel`.
    var isMusicPlaying = false
    /// The analyzed tempo of the loaded song (nil when no tempo could be derived / no song loaded).
    var musicBPM: Double?
    /// Title of the loaded song (for the music status row).
    var currentSongTitle: String?
    /// The locked-rig constraint, mirroring the open project's. `setRigConstraint` writes it back to the
    /// project and re-enforces it on the current look. Defaults to unconstrained.
    var rigConstraint = RigConstraint(fixtureCount: nil, allowedModels: [])

    /// Host-side link to the iPad control panel (advertises over Multipeer, mirrors host state, and
    /// applies the panel's edits). Created lazily by `startIPadSync()` so previews/tests that build an
    /// `AppModel` never start networking.
    @ObservationIgnored
    private var syncCoordinator: LumaSyncCoordinator?

    init(
        aiClient: (any LightingLookGenerating)? = nil,
        songAnalyzer: (any SongAnalyzing)? = nil,
        songLibrary: (any SongLibraryBrowsing)? = nil
    ) {
        let resolvedClient = aiClient ?? Self.makeDefaultLightingClient()
        self.aiClient = resolvedClient
        self.songAnalyzer = songAnalyzer ?? MusicUnderstandingService()
        self.songLibrary = songLibrary ?? MusicKitSongLibrary()
        modelAvailability = resolvedClient.availability
    }

    private static func makeDefaultLightingClient() -> any LightingLookGenerating {
        let openAI = OpenAILightingService()
#if canImport(FoundationModels)
        return FallbackLightingService(primary: openAI, secondary: FoundationModelsLightingService())
#else
        return FallbackLightingService(primary: openAI, secondary: UnavailableLightingLookService())
#endif
    }

    var lightingLook: LightingLook {
        stageState.lightingLook
    }

    var stageLayout: StageLayout {
        selectedProject?.stageLayout ?? .defaultStudentOutdoor()
    }

    var selectedProject: LumaStageProject? {
        guard let selectedProjectId else {
            return nil
        }

        return projects.first(where: { $0.id == selectedProjectId })
    }

    var selectedCueId: String {
        stageState.selectedCueId
    }

    var selectedCue: LightingCue? {
        try? stageState.requireSelectedCue()
    }

    var frontLightDimmer: Double {
        selectedFixture(role: .frontLight)?.intensity ?? 0
    }

    var backgroundWashColor: String {
        selectedFixture(role: .backgroundWash)?.color.value ?? "#4FA8FF"
    }

    var selectedCueFixtures: [FixtureGroup] {
        selectedCue?.fixtureGroups ?? []
    }

    /// The cue stack in playback order — what the cue strip and GO control render.
    var cues: [LightingCue] {
        lightingLook.cues
    }

    /// 1-based position of the selected cue in the stack (for "場景 2/5" labels).
    var selectedCueNumber: Int {
        stageState.selectedCueIndex + 1
    }

    /// The current look's DMX patch sheet — the load-in paperwork (fixtures get real universe/address
    /// assigned as it's built). Computed on demand; also the source for the PDF export.
    var patchSheet: LightingPatchSheet {
        LightingPatchSheet.make(from: lightingLook)
    }

    /// What the relight debug panel renders: how the selected cue's fixtures map onto the scene
    /// (color/intensity/beam per fixture, and which roles actually light the stage). `nil` with no cue.
    /// Resolves through the SAME manual-override + group-master layers the renderer applies, so the panel
    /// reflects hands-on edits (pinch/card/voice/fader rides) — not just the raw AI cue values.
    var relightDebugSnapshot: RelightDebugSnapshot? {
        selectedCue.map { cue in
            RelightDebugSnapshot.make(from: cue, overrides: lightOverrides, groupMasters: groupMasterByLight())
        }
    }

    var generationStatus: String {
        switch modelAvailability {
        case .available:
            return generationSource.displayName
        case .unavailable(let reason):
            return reason
        }
    }

    var isModelAvailable: Bool {
        modelAvailability.isAvailable
    }

    func refreshModelAvailability() {
        modelAvailability = aiClient.availability
    }

    /// Starts the iPad control-panel link: advertises over Multipeer, mirrors host state to the panel,
    /// and applies the panel's edits back through this model. Safe to call repeatedly — only the first
    /// call creates the coordinator — so it can be driven from the main window's `.task`.
    func startIPadSync() {
        guard syncCoordinator == nil else { return }
        let coordinator = LumaSyncCoordinator(appModel: self)
        syncCoordinator = coordinator
        coordinator.start()
    }

    /// SwiftUI immersion style for the current mode: full-immersion night stage, or passthrough
    /// mixed reality so the stage spotlights can spill onto the real room.
    var immersionStyle: any ImmersionStyle {
        switch stageImmersionMode {
        case .fullStage: return .full
        case .roomSpill: return .mixed
        }
    }

    /// Opens fixture inspection at `model` and hides the project window. The two observatory windows
    /// are opened by the caller (they need the SwiftUI `openWindow` action).
    func startFixtureInspection(model: LightingFixtureVisualModel) {
        fixtureCarousel = FixtureCarousel(startAt: model)
        isInspectingFixture = true
    }

    /// Pages the shared carousel; both observatory windows re-render off `fixtureCarousel`.
    func pageFixture(by direction: Int) {
        fixtureCarousel.advance(by: direction)
    }

    /// Marks inspection finished so the project window reappears. Window dismissal is the caller's
    /// job (it needs `dismissWindow`).
    func endFixtureInspection() {
        isInspectingFixture = false
    }

    // MARK: - Tabletop stage editor

    /// Enters a tabletop editing session: requests the dedicated passthrough editor immersive space. That
    /// space replaces the 1:1 stage space (only one immersive space can be open), so the caller dismisses
    /// the stage space; `ContentView` then opens the editor space once the main window is back.
    func enterTabletopEditing() {
        selectedStageObjectId = nil
        isEditingTabletopStage = true
        desiredImmersiveScene = .tabletopEditor
    }

    /// Leaves the editing session and returns to the 1:1 stage space. The caller dismisses the editor space;
    /// `ContentView` reopens the stage space.
    func exitTabletopEditing() {
        clearTabletopEditingState()
        desiredImmersiveScene = .stage
    }

    /// Resets the editing flags without touching the desired scene — shared by `exitTabletopEditing` (which
    /// then asks for the stage) and `closeProject` (which asks for `.none`).
    private func clearTabletopEditingState() {
        isEditingTabletopStage = false
        selectedStageObjectId = nil
    }

    /// Selects (or, on a miss, deselects) the tapped stage object — routed through the shared
    /// `StageBuilderSelectionPolicy` so selection behaves the same as the former iPad builder.
    func selectStageObject(id: String?) {
        selectedStageObjectId = StageBuilderSelectionPolicy.selectedObjectIdAfterViewportTap(
            currentSelectionId: selectedStageObjectId,
            hitObjectId: id
        )
    }

    /// Moves a stage object in the ground plane (its y is preserved), grid/connector-snapped, and
    /// persists the result so the immersive stage reflects the new position.
    func moveStageObject(id: String, toX x: Double, z: Double) {
        var layout = stageLayout
        guard var object = layout.object(id: id) else {
            return
        }

        object.position = Vector3Meters(x: x, y: object.position.y, z: z)
        do {
            try layout.updateObject(layout.snappedObject(object))
            saveStageLayout(layout)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Rotates the selected stage object by 90° about the vertical axis (stage rotations must stay
    /// right-angle aligned, which `StageLayout.validate()` enforces).
    func rotateSelectedStageObject() {
        guard let id = selectedStageObjectId else {
            return
        }

        var layout = stageLayout
        guard var object = layout.object(id: id) else {
            return
        }

        let nextY = (object.rotation.y + 90).truncatingRemainder(dividingBy: 360)
        object.rotation = Vector3Degrees(x: object.rotation.x, y: nextY, z: object.rotation.z)
        do {
            try layout.updateObject(layout.snappedObject(object))
            saveStageLayout(layout)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Adds a new stage object (a truss segment) to the layout — snapped + validated — and selects it so
    /// the user can immediately drag it into place. Placement is routed through the shared
    /// `StageBuilderDropPlanner` so it matches the former builder; ids are unique per add.
    func addStageObject(assetId: StageAssetId) {
        var layout = stageLayout
        let id = "\(assetId.rawValue)_\(UUID().uuidString.prefix(6).lowercased())"
        guard let object = StageBuilderDropPlanner.object(
            assetId: assetId,
            id: id,
            existingObjects: layout.objects,
            dropPosition: nil
        ) else {
            return
        }

        do {
            try layout.addObject(object)
            saveStageLayout(layout)
            selectedStageObjectId = object.id
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Removes the currently selected stage object and clears the selection. A locked object (e.g. the
    /// default stage base if it were locked) throws, which is surfaced as an error.
    func removeSelectedStageObject() {
        guard let id = selectedStageObjectId else {
            return
        }

        var layout = stageLayout
        do {
            try layout.removeObject(id: id)
            saveStageLayout(layout)
            selectedStageObjectId = nil
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Rig fixtures on the tabletop diorama (place / move / remove a light)
    //
    // The rig lives in the look's `cue.fixtureGroups`, NOT `StageLayout` — a fixture has rig identity:
    // the same `id` appears in every cue at the same `manualPosition`. These methods mirror the
    // `moveStageObject`/`addStageObject`/`removeSelectedStageObject` shape but route through
    // `StageState.replaceLightingLook` (which validates) + `persistCurrentProjectState`. The dynamic rig
    // is 4–12 fixtures; `LightingLook.validate()` itself enforces only non-empty cues + a resolvable
    // selection (no fixture-count check), so the count guards live here.

    /// Soft cap on the dynamic rig so the tabletop editor can't grow it without bound (mirrors the
    /// generation schema's 4–12 fixture intent). `addFixtureToRig` refuses to exceed it.
    static let maxRigFixtureCount = 12

    /// Selects (or clears) the rig fixture the tabletop editor operates on. Pure selection — no look edit.
    func selectFixture(id: String?) {
        selectedFixtureId = id
    }

    /// Sets the manual stage position (model metres) of the fixture `id` in EVERY cue — rig identity, so
    /// the same fixture sits at the same spot across the whole show — then re-validates + persists.
    func moveFixture(id: String, toX x: Double, y: Double, z: Double) {
        var look = stageState.lightingLook
        // 規定：雷射不可被拖離桁架 — 把拖曳位置夾回 truss footprint 再存（與 RigPlacement 共用同一套規則，
        // 所以在 1:1 舞台與桌上模型上雷射都會彈回桁架上）。
        let isLaser = look.cues.contains { cue in
            cue.fixtureGroups.contains { $0.id == id && RigPlacement.mountsOnTrussOnly($0.renderModel) }
        }
        let position: FixturePosition
        if isLaser {
            let clamped = RigPlacement.clampedToTruss(Vector3Meters(x: x, y: y, z: z), layout: stageLayout)
            position = FixturePosition(x: clamped.x, y: clamped.y, z: clamped.z)
        } else {
            position = FixturePosition(x: x, y: y, z: z)
        }
        var found = false
        for cueIndex in look.cues.indices {
            if let fixtureIndex = look.cues[cueIndex].fixtureGroups.firstIndex(where: { $0.id == id }) {
                look.cues[cueIndex].fixtureGroups[fixtureIndex].manualPosition = position
                found = true
            }
        }
        guard found else {
            fail("找不到要移動的燈具。")
            return
        }
        do {
            try stageState.replaceLightingLook(look)
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Rotates the aim of the fixture `id` in EVERY cue by a pan/tilt delta — rig identity, so the same
    /// fixture keeps one orientation across the whole show — then re-validates + persists. Mirrors
    /// `moveFixture`: the delta accumulates onto the fixture's `aimOffset` (clamped by `adding`), and the
    /// renderer folds that offset onto the zone-derived resting aim so the head geometry + beam re-aim.
    func rotateFixture(id: String, panDelta: Double, tiltDelta: Double) {
        var look = stageState.lightingLook
        var found = false
        for cueIndex in look.cues.indices {
            if let fixtureIndex = look.cues[cueIndex].fixtureGroups.firstIndex(where: { $0.id == id }) {
                let current = look.cues[cueIndex].fixtureGroups[fixtureIndex].aimOffset ?? .zero
                look.cues[cueIndex].fixtureGroups[fixtureIndex].aimOffset =
                    current.adding(panDelta: panDelta, tiltDelta: tiltDelta)
                found = true
            }
        }
        guard found else {
            fail("找不到要旋轉的燈具。")
            return
        }
        do {
            try stageState.replaceLightingLook(look)
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Appends a new fixture (of the given visual model + zone) to EVERY cue with sensible defaults and
    /// the same `id` (rig identity), re-validates + persists, and selects it. Refuses to grow the rig past
    /// `maxRigFixtureCount`.
    func addFixtureToRig(model: LightingFixtureVisualModel, zone: StageZone) {
        var look = stageState.lightingLook
        guard let largestCueCount = look.cues.map(\.fixtureGroups.count).max(),
              largestCueCount < Self.maxRigFixtureCount else {
            fail("燈具數量已達上限（\(Self.maxRigFixtureCount) 盞），無法再新增。")
            return
        }

        let id = "fixture_\(UUID().uuidString.prefix(6).lowercased())"
        let role = model.derivedRole
        // 規定：雷射只能掛在上舞台桁架上，忽略呼叫端傳入的 zone（新增燈具面板一律傳 .stageFront）。
        let effectiveZone = RigPlacement.mountsOnTrussOnly(model) ? .stageBack : zone
        let number = largestCueCount + 1
        let newFixture = FixtureGroup(
            id: id,
            name: "燈具 \(number)",
            role: role,
            zone: effectiveZone,
            enabled: true,
            intensity: 0.6,
            color: FixtureColor(mode: .rgb, value: "#FFFFFF"),
            fineControl: .default(role: role, zone: effectiveZone),
            model: model,
            manualPosition: nil
        )

        for cueIndex in look.cues.indices {
            look.cues[cueIndex].fixtureGroups.append(newFixture)
        }

        do {
            try stageState.replaceLightingLook(look)
            persistCurrentProjectState()
            selectedFixtureId = id
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Removes the selected fixture from EVERY cue, re-validates + persists, and clears the selection.
    /// Refuses to remove if doing so would leave any cue with no fixtures (a cue must stay lit).
    func removeSelectedFixture() {
        guard let id = selectedFixtureId else {
            return
        }
        var look = stageState.lightingLook
        let wouldEmptyACue = look.cues.contains { cue in
            cue.fixtureGroups.contains(where: { $0.id == id }) && cue.fixtureGroups.count <= 1
        }
        guard !wouldEmptyACue else {
            fail("至少需要保留一盞燈具，無法刪除最後一盞。")
            return
        }

        for cueIndex in look.cues.indices {
            look.cues[cueIndex].fixtureGroups.removeAll { $0.id == id }
        }

        do {
            try stageState.replaceLightingLook(look)
            persistCurrentProjectState()
            selectedFixtureId = nil
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Swaps the stage platform footprint (small / medium / large) and persists it.
    func setStagePlatformPreset(_ preset: StagePlatformPreset) {
        saveStageLayout(TabletopStageEditing.applyingStagePlatformPreset(preset, to: stageLayout))
        reconcileStageSelection()
    }

    /// Swaps the truss portal (4x3 / 6x5 / 8x4) and persists it.
    func setTrussPortalPreset(_ preset: StagePortalPreset) {
        saveStageLayout(TabletopStageEditing.applyingTrussPortalPreset(preset, to: stageLayout))
        reconcileStageSelection()
    }

    /// Clears the stage selection when the selected object no longer exists — e.g. after a portal
    /// preset swap replaces the truss segments with new ids.
    private func reconcileStageSelection() {
        if stageLayout.object(id: selectedStageObjectId) == nil {
            selectedStageObjectId = nil
        }
    }

    func toggleDebugPanel() {
        isDebugPanelVisible.toggle()
    }

    func toggleStageImmersion() {
        stageImmersionMode = stageImmersionMode == .roomSpill ? .fullStage : .roomSpill
        aiUnderstoodCommand = stageImmersionMode == .roomSpill
            ? "正在將舞台燈光投射到你的真實房間"
            : "返回完整沉浸式舞台"
    }

    func openProject(id: String) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == id }) else {
            fail("找不到專案。")
            return
        }

        let project = projects[projectIndex]
        selectedProjectId = project.id
        // Ask for the 1:1 stage space; `ContentView` opens it once it's the front-most window.
        desiredImmersiveScene = .stage
        stageState = StageState(lightingLook: project.lightingLook)
        lightOverrides = [:]
        selectedFixtureId = nil
        resetGroups()
        // A different project is a different rig; drop any stale per-light selection so the control card
        // can't index a fixture that no longer exists. Mirrors generate's reset.
        selectedLightNumber = nil
        // Mirror the opened project's locked-rig constraint, and drop any music show from the prior project.
        rigConstraint = project.rigConstraint
        clearMusicShow()
        transcript = ""
        typedPrompt = ""
        aiUnderstoodCommand = "已開啟 \(project.name)"
        lastExplanation = project.lightingLook.explanation
        generationSource = .foundationModels
        lastError = nil
        conversationState = .idle
        refreshModelAvailability()
    }

    func createProject() {
        createProject(template: .campusMusic)
    }

    func createProject(template: ProjectCreationTemplate.Kind) {
        let project = LumaStageProject.newProject(index: projects.count + 1, template: template)
        projects.insert(project, at: 0)
        openProject(id: project.id)
    }

    func closeProject() {
        persistCurrentProjectState()
        selectedProjectId = nil
        // No project → no immersive space. Also end any tabletop editing session (its layout no longer
        // has a home once the project closes); `ContentView` then opens nothing.
        clearTabletopEditingState()
        clearMusicShow()
        desiredImmersiveScene = .none
        transcript = ""
        typedPrompt = ""
        aiUnderstoodCommand = "等待選擇專案"
        lastError = nil
        conversationState = .idle
    }

    // MARK: - Music sync show (SPEC 05 owner C)

    /// Analyzes a song file → builds a deterministic multi-cue show from it → applies the look, loads it
    /// into the playback engine, and arms cue-by-section advance. The deterministic backbone (analysis →
    /// `ShowPlan` → `MusicShowBuilder`) never needs the AI, so the show is built even if generation is
    /// unavailable. Any failure surfaces through the existing `fail(...)`.
    func importSong(url: URL, title overrideTitle: String? = nil) async {
        // A file-picker URL is usually security-scoped; bracket the access so analysis can read it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // 資料庫項目的 assetURL（`ipod-library://…`）檔名無意義，所以選曲路徑會傳真實 title 進來；
        // 檔案瀏覽器路徑沒傳，就沿用既有的「去副檔名取檔名」行為。
        let title = overrideTitle ?? url.deletingPathExtension().lastPathComponent
        do {
            let analysis = try await songAnalyzer.analyze(url: url, title: title)
            try buildAndLoadShow(from: analysis, audioURL: url)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// SPEC 12 — 從裝置音樂資料庫挑一首歌：解析其可讀取檔案 URL，再餵進既有的 `importSong` 管線
    /// （帶上資料庫的真實 title）。受 DRM 保護 / 未下載的串流曲目沒有可讀 URL，會以繁中說明優雅拒絕。
    func pickLibrarySong(_ item: SongLibraryItem) async {
        do {
            let url = try await songLibrary.resolvePlayableURL(for: item)
            await importSong(url: url, title: item.title)
        } catch SongSourceError.protected {
            fail("此曲受保護或尚未下載到本機，無法在裝置端分析；請先在「音樂」App 下載，或改用未受保護的本機檔案。")
        } catch SongSourceError.unauthorized {
            fail("沒有音樂資料庫存取權限，請在設定中開啟。")
        } catch {
            fail("無法讀取這首歌：\(error.localizedDescription)")
        }
    }

    /// 薄包裝，讓選曲 view 透過 `AppModel` 取用資料庫，而不直接持有 `MusicKitSongLibrary`（注入慣例）。
    func authorizeMusicLibrary() async -> Bool {
        await songLibrary.authorize()
    }

    /// 列出資料庫近期曲目（給選曲 view 的初始清單）。
    func browseLibrary(limit: Int = 50) async -> [SongLibraryItem] {
        await songLibrary.recentSongs(limit: limit)
    }

    /// 依關鍵字搜尋資料庫曲目（給選曲 view 的搜尋框）。
    func searchLibrary(_ query: String) async -> [SongLibraryItem] {
        await songLibrary.search(query)
    }

    /// Same pipeline as `importSong`, but using the built-in pre-analyzed demo song — the zero-fail stage
    /// path. The demo analyzer ships its analysis as bundled JSON (no live framework run), so the show is
    /// always built. Audio is a fully-original backing track synthesized on-device from that same analysis
    /// (`DemoTrackSynth`, beat-locked to the exact grid + sections) — so the demo actually plays sound AND
    /// cues auto-advance on the section boundaries, just like an imported file. If synthesis/caching fails
    /// for any reason, it falls back to the silent clock-only path (visuals still beat-lock; manual GO).
    func useBuiltInDemoSong() async {
        do {
            let analysis = try await CachedSongAnalyzer().analyze(url: URL(fileURLWithPath: ""), title: "")
            let audioURL = await Self.demoAudioURL(for: analysis)   // nil ⇒ silent clock-only fallback
            try buildAndLoadShow(from: analysis, audioURL: audioURL)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Render (once, cached) the synthesized demo backing track to a WAV in Caches and return its file URL.
    /// The synth is deterministic, so a stable filename lets us reuse the file across launches instead of
    /// re-rendering ~150s of audio every time. The CPU-bound render runs off the main actor. Returns nil on
    /// any failure so `useBuiltInDemoSong` degrades gracefully to the silent clock-only demo.
    private static func demoAudioURL(for analysis: SongAnalysis) async -> URL? {
        let fileManager = FileManager.default
        guard let caches = try? fileManager.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        // Version the name so a future synth change invalidates the cache without a stale file lingering.
        let url = caches.appendingPathComponent("luma-demo-track-v1.wav")
        if fileManager.fileExists(atPath: url.path) { return url }

        // Render AND write the ~13 MB WAV off the main actor — both the CPU-bound synthesis and the atomic
        // disk write stay off-main so tapping the demo button never hitches the UI on a cache miss.
        return await Task.detached(priority: .userInitiated) {
            let data = DemoTrackSynth.wavData(for: analysis)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }.value
    }

    /// Shared backbone for `importSong` / `useBuiltInDemoSong`: builds the show from an analysis, applies it,
    /// and arms the engine. When a decodable audio file loads, `play()` runs the player, beat-locks the
    /// visuals, and auto-advances cues on the section boundaries. When no audio loads (a nil URL, or a
    /// non-nil URL the player can't decode), the show falls back to clock-only: `playMusicShow` anchors the
    /// beat clock directly (visuals still beat-lock) but cues do not auto-advance — the show holds its first
    /// cue and the user GOes manually. Throws on look-build / validation failure (caught by the callers → `fail`).
    private func buildAndLoadShow(from analysis: SongAnalysis, audioURL: URL?) throws {
        let plan = ShowPlan.make(from: analysis)
        let look = try MusicShowBuilder.buildLook(
            plan: plan,
            rig: rigConstraint,
            lookName: analysis.title
        )

        try stageState.replaceLightingLook(look)
        // A freshly built show is a brand-new dynamic rig — reset the manual layers, mirroring generate().
        lightOverrides = [:]
        selectedFixtureId = nil
        resetGroups()
        selectedLightNumber = nil
        lastExplanation = look.explanation
        generationSource = .foundationModels
        persistCurrentProjectState()

        // Retain so `setRigConstraint` can rebuild the show in place and `playMusicShow` can anchor the
        // clock-only demo path.
        lastAnalysis = analysis
        lastPlan = plan
        let clock = analysis.makeBeatClock()
        lastClock = clock

        // Load first, then derive clock-only from whether a decodable player ACTUALLY loaded — not from the
        // URL's nil-ness. A nil URL (or an empty one) fails player creation and lands clock-only, but so does
        // a non-nil-but-unreadable URL (stale/corrupt cached demo WAV, or a file `AVURLAsset` could analyze
        // but `AVAudioPlayer` can't decode). Keying the fallback on load success means such a case still
        // beat-locks the visuals via `playMusicShow`'s clock anchor instead of freezing into a dead, silent
        // show with no player tick.
        musicSyncEngine.load(url: audioURL ?? URL(fileURLWithPath: ""), clock: clock)
        musicShowIsClockOnly = !musicSyncEngine.hasLoadedPlayer
        musicSyncEngine.setSectionStarts(plan.cues.map(\.startTime))
        musicSyncEngine.onSectionBoundary = { [weak self] index in
            self?.selectCueAtSectionIndex(index)
        }

        isMusicShowActive = true
        isMusicPlaying = musicSyncEngine.isPlaying
        musicBPM = analysis.bpm
        currentSongTitle = analysis.title
        lastError = nil
        aiUnderstoodCommand = "已依「\(analysis.title)」生成 \(look.cues.count) 個場景的整場演出。"
        conversationState = .explaining
        narrateIfEnabled(aiUnderstoodCommand)
    }

    /// Starts music-synced playback: audio (if any) + the beat clock anchor + cue auto-advance. No-op when
    /// no show is loaded. For the clock-only demo (no playable audio), anchors `MusicSyncClockSource`
    /// directly so the render-thread effect system still beat-locks even though no audio plays.
    func playMusicShow() {
        guard isMusicShowActive else { return }
        musicSyncEngine.play()
        if musicShowIsClockOnly, let clock = lastClock {
            // The audio engine has no player to start; anchor the shared beat clock ourselves so the visuals
            // lock to tempo from "now". (CACurrentMediaTime is the same time base the engine uses.)
            MusicSyncClockSource.shared.setActive(startMediaTime: CACurrentMediaTime(), clock: clock)
        }
        isMusicPlaying = musicSyncEngine.isPlaying || musicShowIsClockOnly
    }

    /// Stops playback and clears the beat clock; the look stays applied so the stage holds its last cue.
    func stopMusicShow() {
        musicSyncEngine.stop()
        // The engine clears the source on a real-audio stop, but for the clock-only demo we anchored it
        // ourselves, so clear it here too.
        if musicShowIsClockOnly {
            MusicSyncClockSource.shared.clear()
        }
        isMusicPlaying = musicSyncEngine.isPlaying
    }

    /// Maps a section boundary index → the cue at that index in the stack and selects it (bounds-guarded).
    /// Wired as `musicSyncEngine.onSectionBoundary`, so cues auto-advance as the song crosses each section.
    private func selectCueAtSectionIndex(_ index: Int) {
        let stack = cues
        guard index >= 0, index < stack.count else { return }
        selectCue(id: stack[index].id)
    }

    /// Updates the locked-rig constraint: stores it on the model, persists it to the current project, and
    /// re-enforces it on the current look immediately so the user sees the effect at once.
    func setRigConstraint(_ constraint: RigConstraint) {
        rigConstraint = constraint

        if let selectedProjectId,
           let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectId }) {
            projects[projectIndex].rigConstraint = constraint
        }

        // Re-enforce on the current look right now (idempotent, so re-applying a compliant look is a no-op).
        // Keep the laser-on-truss rule too — a model remap could otherwise place a laser off the truss.
        let enforced = constraint.enforce(on: stageState.lightingLook).enforcingTrussMountedLasers()
        do {
            try stageState.replaceLightingLook(enforced)
            lightOverrides = [:]
            selectedFixtureId = nil
            resetGroups()
            selectedLightNumber = nil
            persistCurrentProjectState()
            aiUnderstoodCommand = constraint.isUnconstrained
                ? "已解除設備鎖定，燈光不再受設備檔限制。"
                : "已套用設備檔，燈光已對齊你的現有設備。"
            lastError = nil
            conversationState = .explaining
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Tears down a music show: stops playback, clears the beat clock, drops the analysis/plan, and resets
    /// the observable music state. Called on project open/close and before a manual generation so a stale
    /// show never lingers. The applied look is left untouched (the next caller replaces it).
    func clearMusicShow() {
        musicSyncEngine.stop()
        musicSyncEngine.onSectionBoundary = nil
        // Clock-only demo anchors the source itself, so make sure it's cleared on teardown.
        if musicShowIsClockOnly {
            MusicSyncClockSource.shared.clear()
        }
        lastAnalysis = nil
        lastPlan = nil
        lastClock = nil
        musicShowIsClockOnly = false
        isMusicShowActive = false
        isMusicPlaying = false
        musicBPM = nil
        currentSongTitle = nil
    }

    func toggleSpeechInput() async {
        if speechTranscriber.isRecording {
            let finalTranscript = speechTranscriber.stop()
            // Land the dictated words in the prompt field the instant recording stops — before any
            // re-render — so the captured text is visible (and stays visible through generation)
            // instead of the field snapping back to its pre-dictation contents for a frame.
            typedPrompt = finalTranscript
            conversationState = .transcribing
            guard !finalTranscript.isEmpty else {
                fail("無法辨識你的語音。請改用文字輸入或再試一次。")
                return
            }

            await generate(from: finalTranscript)
            return
        }

        refreshModelAvailability()
        guard modelAvailability.isAvailable else {
            fail(modelAvailability.unavailableReason ?? "Apple Intelligence 無法使用。")
            return
        }

        do {
            conversationState = .listening
            transcript = ""
            lastError = nil
            try await speechTranscriber.start()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func generateFromTypedPrompt() async {
        let prompt = typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            fail("請先輸入文字提示。")
            return
        }

        await generate(from: prompt)
    }

    func generate(from prompt: String) async {
        // Hands-free show control ("go", "next cue", "新增場景", "念出說明") runs the cue stack / narration
        // with no AI call — so the whole loop is drivable by voice (the accessibility mode). A design
        // prompt that merely contains a word like "go" returns nil and falls through.
        if let voiceCommand = StageVoiceCommand.parse(prompt) {
            applyVoiceCommand(voiceCommand)
            return
        }

        // Deterministic single-light commands ("close the light 1", "set light 2 to blue") bypass AI
        // generation — instant, predictable, and they work even when Apple Intelligence is unavailable.
        // A prompt without a light number (e.g. "change the light to yellow") returns nil and falls
        // through to generative look design below.
        if let command = LightCommand.parse(prompt) {
            applyLightCommand(command)
            return
        }

        refreshModelAvailability()
        guard modelAvailability.isAvailable else {
            fail(modelAvailability.unavailableReason ?? "Apple Intelligence 無法使用。")
            return
        }

        conversationState = .interpreting
        transcript = prompt
        // Mirror the prompt into the field so a voice-driven generation shows the words it is acting
        // on (typed generation already has them there); they persist through the relight.
        typedPrompt = prompt
        lastError = nil
        aiUnderstoodCommand = Self.understoodCommand(for: prompt)

        do {
            let result = try await aiClient.generateLook(from: prompt)
            conversationState = .applying
            // The locked-rig constraint applies to AI generation too (idempotent / no-op when
            // unconstrained), so a manual design still obeys the user's declared equipment profile.
            // Then force every laser onto the upstage truss (規定：雷射只能在 Truss 上) — this also
            // catches the edge case where a constraint remap turns a floor-zoned fixture into a laser.
            let constrained = rigConstraint.enforce(on: result.look).enforcingTrussMountedLasers()
            try stageState.replaceLightingLook(constrained)
            // A manual generation replaces any music-synced show that was loaded.
            clearMusicShow()
            // A freshly generated look is a brand-new dynamic rig — drop stale per-light overrides so a
            // prior "close the light 3" doesn't silently reattach to a different physical fixture (overrides
            // are keyed by cue order, not fixture id). Mirrors openProject's reset.
            lightOverrides = [:]
            selectedFixtureId = nil
            resetGroups()
            // Likewise drop a stale selection so the control card doesn't point at a now-missing fixture.
            selectedLightNumber = nil
            generationSource = result.source
            lastExplanation = result.look.explanation
            persistCurrentProjectState()
            conversationState = .explaining
            narrateIfEnabled("\(result.look.explanation.actionSummary) 共 \(lightingLook.cues.count) 個場景。")
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Applies a deterministic single-light command to `lightOverrides` (the manual control layer the
    /// renderer lays on top of the cue). No AI call; surfaces the result through the same conversation
    /// state the composer's feedback panel reads.
    /// Number of individually addressable lights in the current scene (Light 1…N, in cue order).
    var lightCount: Int {
        selectedCue?.fixtureGroups.count ?? 0
    }

    func applyLightCommand(_ command: LightCommand) {
        // The rig is dynamic, so a single-light command must name a light that exists in this scene.
        if let number = command.targetLightNumber, number < 1 || number > lightCount {
            fail("沒有第 \(number) 盞燈 — 這個場景共有 \(lightCount) 盞燈。")
            return
        }

        // A role-named recolor edits the selected cue's matching fixtures directly (no AI regeneration).
        // Routed here rather than through the override layer so it persists into the saved look.
        if case .setRoleColor(let role, let hex) = command {
            let matchCount = selectedCue?.fixtureGroups.filter { $0.role == role }.count ?? 0
            guard matchCount > 0 else {
                fail("這個場景沒有\(role.displayName)燈具。")
                return
            }
            do {
                try stageState.patchSelectedCue(.roleColor(role: role, hexColor: hex))
                persistCurrentProjectState()
            } catch {
                fail(error.localizedDescription)
                return
            }
            let summary = Self.describe(command)
            lastError = nil
            aiUnderstoodCommand = summary
            lastExplanation = lightingLook.explanation
            conversationState = .explaining
            narrateIfEnabled(summary)
            return
        }

        // A rotation edits the fixture's persistent aim offset in the LOOK (rig identity, across all
        // cues) — like `.setRoleColor` above, it goes through `replaceLightingLook` + persist rather than
        // the override layer, so it survives cue switches and project reopen. Fixture id = the number-th
        // fixture in cue order (`applyLightCommand`'s range guard already validated `number`).
        if case .rotate(let number, let pan, let tilt) = command {
            guard let id = selectedCue?.fixtureGroups[number - 1].id else {
                fail("找不到第 \(number) 盞燈。")
                return
            }
            rotateFixture(id: id, panDelta: pan, tiltDelta: tilt)
            guard lastError == nil else { return }   // rotateFixture reported a failure
            let summary = Self.describe(command)
            aiUnderstoodCommand = summary
            lastExplanation = LightingExplanation(
                term: "燈具朝向",
                plainText: "旋轉指令會改變單一燈具的朝向（水平左右或垂直俯仰），並在每個場景中保持一致，不會重新生成整個燈光。",
                actionSummary: summary
            )
            conversationState = .explaining
            narrateIfEnabled(summary)
            return
        }

        switch command {
        case .close(let number):
            lightOverrides[number, default: LightOverride()].isOff = true
        case .open(let number):
            if var override = lightOverrides[number] {
                override.isOff = false
                lightOverrides[number] = override.isActive ? override : nil
            }
        case .setColor(let number, let hex):
            lightOverrides[number, default: LightOverride()].colorHex = hex
        case .setIntensity(let number, let fraction):
            lightOverrides[number, default: LightOverride()].intensity = fraction
        case .allOff:
            for index in 0..<lightCount {
                lightOverrides[index + 1, default: LightOverride()].isOff = true
            }
        case .resetAll:
            lightOverrides.removeAll()
        case .setRoleColor:
            return   // handled above (targeted cue patch, returns early); unreachable here.
        case .rotate:
            return   // handled above (persistent aim-offset edit, returns early); unreachable here.
        }

        let summary = Self.describe(command)
        lastError = nil
        aiUnderstoodCommand = summary
        lastExplanation = LightingExplanation(
            term: "手動燈光控制",
            plainText: "單燈指令會在 AI 設計的燈光之上，直接調整單一燈具，而不會重新生成整個場景。",
            actionSummary: summary
        )
        conversationState = .explaining
        narrateIfEnabled(summary)
    }

    // MARK: - Cue stack (multi-cue sequence + GO) + voice-only control

    /// Dispatches a hands-free show command parsed from voice/typed input (`StageVoiceCommand`).
    func applyVoiceCommand(_ command: StageVoiceCommand) {
        switch command {
        case .nextCue: goToNextCue()
        case .previousCue: goToPreviousCue()
        case .addCue: appendCue()
        case .readExplanation: readCurrentExplanationAloud()
        }
    }

    /// GO: advance the cue stack to the next cue (wraps at the end). The immersive stage cross-fades to
    /// it over that cue's transition (the renderer relights whenever the selected cue changes).
    func goToNextCue() {
        announce(stageState.goToNextCue(), verb: "前往")
    }

    /// GO back: step the cue stack to the previous cue (wraps at the start).
    func goToPreviousCue() {
        announce(stageState.goToPreviousCue(), verb: "返回")
    }

    private func announce(_ cue: LightingCue, verb: String) {
        aiUnderstoodCommand = "已\(verb) \(cue.localizedDisplayName)（場景 \(selectedCueNumber)/\(cues.count)）"
        lastExplanation = LightingExplanation(
            term: "GO 走場",
            plainText: "走場是依序播放一連串場景。按 GO 會以下一個場景設定的過場時間，從目前燈光平順過渡過去 —— 這就是專業燈控台跑一整場演出的方式。",
            actionSummary: aiUnderstoodCommand
        )
        // Cue ops are synchronous (the renderer cross-fades on its own); settle straight to .explaining so
        // the composer shows the result instead of hanging forever on the pulsing "套用燈光中" spinner.
        conversationState = .explaining
        lastError = nil
        persistCurrentProjectState()
        narrateIfEnabled(aiUnderstoodCommand)
    }

    /// Appends a new cue to the stack by duplicating the current one (so the rig carries over), then
    /// selects it — the building block for turning one look into a multi-cue show by hand.
    func appendCue() {
        let number = cues.count + 1
        let id = "cue_\(UUID().uuidString.prefix(8).lowercased())"
        do {
            try stageState.appendCue(id: id, name: "場景 \(number)")
            aiUnderstoodCommand = "已新增場景 \(number)（複製目前場景，可再調整）"
            lastExplanation = LightingExplanation(
                term: "場景串",
                plainText: "場景串是一場演出的燈光腳本。新增的場景會複製目前的燈光作為起點，你可以再逐燈微調，串成完整的走台表。",
                actionSummary: aiUnderstoodCommand
            )
            conversationState = .explaining
            lastError = nil
            persistCurrentProjectState()
            narrateIfEnabled(aiUnderstoodCommand)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Removes a cue from the stack (never the last remaining one).
    func removeCue(id: String) {
        do {
            try stageState.removeCue(id: id)
            aiUnderstoodCommand = "已刪除場景（目前共 \(cues.count) 個）"
            lastExplanation = LightingExplanation(
                term: "場景串",
                plainText: "刪除場景會把它從走台表中移除，其餘場景的順序保持不變。至少需保留一個場景。",
                actionSummary: aiUnderstoodCommand
            )
            conversationState = .explaining
            lastError = nil
            persistCurrentProjectState()
            narrateIfEnabled(aiUnderstoodCommand)
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Voice narration (accessibility)

    func toggleVoiceNarration() {
        isVoiceNarrationEnabled.toggle()
        if isVoiceNarrationEnabled {
            narrator.speak("語音朗讀已開啟。\(aiUnderstoodCommand)")
        } else {
            narrator.stop()
        }
    }

    /// Reads the current understood command + explanation aloud — an explicit request (the "念出說明"
    /// voice command / a button), so it speaks regardless of the narration toggle.
    func readCurrentExplanationAloud() {
        narrator.speak("\(aiUnderstoodCommand)。\(lastExplanation.term)：\(lastExplanation.plainText)")
        // Clear any prior error so reading the explanation doesn't leave the composer stuck on the red
        // error panel (the feedback panel shows lastError first, regardless of conversationState).
        lastError = nil
        conversationState = .explaining
    }

    private func narrateIfEnabled(_ text: String) {
        guard isVoiceNarrationEnabled else { return }
        narrator.speak(text)
    }

    // MARK: - In-headset manual per-light control (the "console" surface, on top of the AI cue)
    //
    // Hands-on control of a single light from inside the immersive scene: look at it, pinch to select,
    // then open/close, dim, or recolour it. Drives the same deterministic `LightOverride` layer the voice
    // commands use (so "select Light 3 → 50%" and "把第 3 盞調到 50%" land identically) — i.e. the
    // programmer that sits ON TOP of the AI cue: "AI gives the speed, the designer keeps control."

    /// The light (1-based, cue order) currently selected for hands-on control in the immersive scene, or
    /// nil. Drives the in-scene selection highlight and the floating per-light control card.
    var selectedLightNumber: Int?

    /// The live manual override on the selected light (nil = following the cue), so the control card can
    /// reflect its current state.
    var selectedLightOverride: LightOverride? {
        guard let number = selectedLightNumber else { return nil }
        return lightOverrides[number]
    }

    /// The selected light's effective on/off + intensity, resolving its override onto the cue value — what
    /// the control card shows as the current level.
    var selectedLightResolved: (isOff: Bool, intensity: Double)? {
        guard let number = selectedLightNumber,
              let fixtures = selectedCue?.fixtureGroups,
              number >= 1, number <= fixtures.count else { return nil }
        let fixture = fixtures[number - 1]
        let override = lightOverrides[number] ?? LightOverride()
        let resolved = override.resolved(cueColor: fixture.color.value, cueIntensity: fixture.intensity)
        return (override.isOff, resolved.intensity)
    }

    /// Selects a light for manual control (or clears the selection with nil). Out-of-range numbers are
    /// ignored so a stray hit can't select a non-existent light.
    func selectLight(number: Int?) {
        guard let number else {
            selectedLightNumber = nil
            return
        }
        guard number >= 1, number <= lightCount else { return }
        selectedLightNumber = number
    }

    /// Sets a light's manual intensity override (0...1). Quiet: it mutates only the override layer the
    /// renderer observes — no conversation-state churn — so repeated level taps don't thrash the feedback
    /// panel. The renderer relights over the cue's transition.
    func setManualIntensity(light number: Int, _ value: Double) {
        guard number >= 1, number <= lightCount else { return }
        var override = lightOverrides[number] ?? LightOverride()
        override.isOff = false
        override.intensity = min(max(value, 0), 1)
        lightOverrides[number] = override
    }

    /// Toggles a light fully off / back on (the manual blackout for one fixture).
    func toggleManualOff(light number: Int) {
        guard number >= 1, number <= lightCount else { return }
        var override = lightOverrides[number] ?? LightOverride()
        override.isOff.toggle()
        lightOverrides[number] = override.isActive ? override : nil
    }

    /// Sets a light's manual colour override (#RRGGBB).
    func setManualColor(light number: Int, hex: String) {
        guard number >= 1, number <= lightCount else { return }
        var override = lightOverrides[number] ?? LightOverride()
        override.colorHex = hex
        lightOverrides[number] = override
    }

    /// Clears a light's manual override so it follows the AI cue again.
    func clearManualOverride(light number: Int) {
        lightOverrides[number] = nil
    }

    // MARK: - Group submasters (SPEC 08): the fast live-control unit
    //
    // A handful of auto-derived groups (前光/背景洗/上舞台/動態/全部) the iPad rides as submaster faders.
    // Folded into the SAME cue → override resolution the renderer already runs (`FixtureGroupMask` +
    // `LightOverride.resolved(cueColor:cueIntensity:groupMaster:)`): the group master scales every member
    // light that has NO explicit per-light intensity override (those still win — channel beats submaster);
    // multi-group membership takes the HTP. This is a transient ride layer, not a second override state.

    /// Re-derives the standard groups from the current rig and drops any ride levels — called on every
    /// look change (new project / generation), mirroring the `lightOverrides` reset so a new rig gets
    /// fresh groups and no stale masters.
    private func resetGroups() {
        groups = (selectedCue ?? cues.first).map(FixtureGroupMask.autoSeed(from:)) ?? []
        groupMasters = [:]
    }

    /// Rides a group submaster (0...1). Quiet — mutates only the transient ride layer the renderer
    /// observes, with no conversation-state churn, since the iPad rides these continuously.
    func setGroupMaster(id: String, level: Double) {
        groupMasters[id] = min(max(level, 0), 1)
    }

    /// Momentary bump/flash: `on` drives the group to full; `off` releases it back to following the cue.
    func bumpGroup(id: String, on: Bool) {
        if on { groupMasters[id] = 1.0 } else { groupMasters[id] = nil }
    }

    /// Releases a group submaster so its members follow the cue again.
    func clearGroupMaster(id: String) {
        groupMasters[id] = nil
    }

    /// The effective group master for the Nth light (1-based, cue order) — the HTP of the ridden groups
    /// it belongs to, default 1.0.
    func effectiveGroupMaster(forLight number: Int) -> Double {
        guard let fixtures = selectedCue?.fixtureGroups, number >= 1, number <= fixtures.count else { return 1.0 }
        return FixtureGroupMask.effectiveMaster(forFixtureId: fixtures[number - 1].id, groups: groups, masters: groupMasters)
    }

    /// Per-light effective masters for the renderer — only lights pulled off 1.0 are listed, so the
    /// renderer defaults the rest. Reading `groupMasters` here is also what lets `ImmersiveView`'s
    /// `body`-level call establish the Observation dependency the `update:` closure needs (the footgun).
    func groupMasterByLight() -> [Int: Double] {
        guard !groupMasters.isEmpty, let fixtures = selectedCue?.fixtureGroups else { return [:] }
        var result: [Int: Double] = [:]
        for (index, fixture) in fixtures.enumerated() {
            let master = FixtureGroupMask.effectiveMaster(forFixtureId: fixture.id, groups: groups, masters: groupMasters)
            if master != 1.0 { result[index + 1] = master }
        }
        return result
    }

    private static func describe(_ command: LightCommand) -> String {
        switch command {
        case .close(let number): return "已關閉 \(StageLightLabel.displayName(number: number))"
        case .open(let number): return "已重新開啟 \(StageLightLabel.displayName(number: number))"
        case .setColor(let number, let hex): return "已將 \(StageLightLabel.displayName(number: number)) 設為 \(hex)"
        case .setIntensity(let number, let fraction): return "已將 \(StageLightLabel.displayName(number: number)) 設為 \(Int((fraction * 100).rounded()))%"
        case .setRoleColor(let role, let hex): return "已將目前場景的\(role.displayName)改為 \(hex)"
        case .rotate(let number, let pan, let tilt):
            let label = StageLightLabel.displayName(number: number)
            if pan != 0 {
                return "已將 \(label) \(pan > 0 ? "向右轉" : "向左轉") \(Int(abs(pan)))°"
            }
            if tilt != 0 {
                return "已將 \(label) \(tilt > 0 ? "向上仰" : "向下俯") \(Int(abs(tilt)))°"
            }
            return "已調整 \(label) 的朝向"
        case .allOff: return "已關閉所有燈光"
        case .resetAll: return "已將所有燈光重置為目前的燈光"
        }
    }

    func selectCue(id: String) {
        do {
            try stageState.selectCue(id: id)
            aiUnderstoodCommand = "已切換目前場景至 \(selectedCue?.localizedDisplayName ?? id)"
            lastExplanation = LightingExplanation(
                term: "場景",
                plainText: "場景是一種燈光狀態。切換場景時，LumaStage 會隨時間動畫呈現亮度與顏色的變化。",
                actionSummary: "已選擇 \(selectedCue?.localizedDisplayName ?? id) 進行預覽與編輯。"
            )
            conversationState = .explaining
            persistCurrentProjectState()
            narrateIfEnabled(aiUnderstoodCommand)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func setFrontLightDimmer(_ value: Double) {
        do {
            try stageState.patchSelectedCue(.frontLightDimmer(value))
            aiUnderstoodCommand = "已將前光亮度設為 \(Int(round(value * 100)))%"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func setBackgroundWashColor(_ hexColor: String) {
        do {
            try stageState.patchSelectedCue(.backgroundWashColor(hexColor))
            aiUnderstoodCommand = "已將背景泛光顏色設為 \(hexColor)"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func setFixtureIntensity(id fixtureId: String, value: Double) {
        do {
            try stageState.patchSelectedCue(.fixtureIntensity(fixtureId: fixtureId, intensity: value))
            // Authoritative console edit: drop any stale manual intensity override on this light so the
            // new cue level actually renders (else `LightOverride.resolved` masks it and the light doesn't move).
            supersedeManualOverride(fixtureId: fixtureId, clearing: .intensity)
            aiUnderstoodCommand = "已將所選燈具亮度設為 \(Int(round(value * 100)))%"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func setFixtureColor(id fixtureId: String, hexColor: String) {
        do {
            try stageState.patchSelectedCue(.fixtureColor(fixtureId: fixtureId, hexColor: hexColor))
            // Authoritative console edit: drop any stale manual colour override on this light so the new
            // cue colour actually renders instead of being masked by the override.
            supersedeManualOverride(fixtureId: fixtureId, clearing: .color)
            aiUnderstoodCommand = "已將所選燈具顏色設為 \(hexColor)"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Supersedes one component of a fixture's manual override after an authoritative cue-layer edit to the
    /// same light (iPad panel or a direct per-fixture edit). Without this, a light still carrying an override
    /// from an in-headset pinch/voice/card tweak would have that override mask the console edit at resolve
    /// time and the on-stage spotlight would never change — the "iPad edits don't reach the lights" bug.
    private func supersedeManualOverride(fixtureId: String, clearing component: OverrideComponent) {
        guard let index = selectedCue?.fixtureGroups.firstIndex(where: { $0.id == fixtureId }) else { return }
        let number = index + 1
        guard let existing = lightOverrides[number] else { return }
        lightOverrides[number] = existing.superseded(clearing: component)
    }

    func setFixtureFineControl(id fixtureId: String, control: FixtureFineControl) {
        do {
            try stageState.patchSelectedCue(.fixtureFineControl(fixtureId: fixtureId, control: control))
            aiUnderstoodCommand = "已更新所選燈具的位置、角度與光束"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func resetSelectedCue() {
        do {
            try stageState.resetSelectedCue()
            aiUnderstoodCommand = "已重置目前場景"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func saveStageLayout(_ layout: StageLayout) {
        do {
            try layout.validate()
            guard let selectedProjectId,
                  let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectId }) else {
                fail("請先選擇專案，再儲存舞台佈局。")
                return
            }

            projects[projectIndex].stageLayout = layout
            projects[projectIndex].lastEditedDescription = "舞台佈局已更新"
            aiUnderstoodCommand = "已更新 \(layout.name) 的舞台建構佈局"
            lastError = nil
            conversationState = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    func resetStageLayoutToDefault() {
        saveStageLayout(.defaultStudentOutdoor())
    }

    func selectedFixture(role: FixtureRole) -> FixtureGroup? {
        selectedCue?.fixtureGroups.first(where: { $0.role == role })
    }

    func selectedFixture(id fixtureId: String?) -> FixtureGroup? {
        guard let fixtureId else {
            return nil
        }

        return selectedCue?.fixtureGroups.first(where: { $0.id == fixtureId })
    }

    private func fail(_ message: String) {
        lastError = message
        conversationState = .error
    }

    private func persistCurrentProjectState() {
        guard let selectedProjectId,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectId }) else {
            return
        }

        projects[projectIndex].lightingLook = stageState.lightingLook
        projects[projectIndex].lastEditedDescription = "目前工作階段"
    }

    private static func understoodCommand(for prompt: String) -> String {
        let lowercasedPrompt = prompt.lowercased()

        if lowercasedPrompt.contains("front light") {
            return "調整前光亮度，讓表演者更清楚可見。"
        }

        if lowercasedPrompt.contains("background wash") {
            return "調整背景泛光，改變舞台的顏色與氛圍。"
        }

        if lowercasedPrompt.contains("highlight") {
            return "建立開場與重點場景，並讓重點段落更明亮、更聚焦。"
        }

        return "生成包含開場與重點場景的舞台燈光設計。"
    }
}
