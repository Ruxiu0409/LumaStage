//
//  AppModel.swift
//  LumaStage
//
//  Created by Tsai Cheng-Yeh on 2026/5/20.
//

import SwiftUI
import Observation

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
    var conversationState: ConversationState = .idle
    var projects = LumaStageProject.defaultProjects()
    var selectedProjectId: String?

    var stageState = StageState(lightingLook: .mvpDemo())
    var transcript = ""
    var typedPrompt = ""
    var aiUnderstoodCommand = "等待語音或文字輸入"
    var lastExplanation = LightingLook.mvpDemo().explanation
    var generationSource: LightingGenerationSource = .foundationModels
    private(set) var modelAvailability: LightingModelAvailability = .available
    var lastError: String?

    let speechTranscriber = SpeechTranscriber()

    /// Speaks feedback aloud when `isVoiceNarrationEnabled`. ObservationIgnored — it's an output sink,
    /// not observable state. (Constructing the synthesizer is cheap; it stays silent until `speak`.)
    @ObservationIgnored
    private let narrator = SpeechNarrator()

    @ObservationIgnored
    private let aiClient: any LightingLookGenerating

    /// Host-side link to the iPad control panel (advertises over Multipeer, mirrors host state, and
    /// applies the panel's edits). Created lazily by `startIPadSync()` so previews/tests that build an
    /// `AppModel` never start networking.
    @ObservationIgnored
    private var syncCoordinator: LumaSyncCoordinator?

    init(aiClient: (any LightingLookGenerating)? = nil) {
        let resolvedClient = aiClient ?? Self.makeDefaultLightingClient()
        self.aiClient = resolvedClient
        modelAvailability = resolvedClient.availability
    }

    private static func makeDefaultLightingClient() -> any LightingLookGenerating {
#if canImport(FoundationModels)
        return FoundationModelsLightingService()
#else
        return UnavailableLightingLookService()
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
    var relightDebugSnapshot: RelightDebugSnapshot? {
        selectedCue.map(RelightDebugSnapshot.make(from:))
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
        desiredImmersiveScene = .none
        transcript = ""
        typedPrompt = ""
        aiUnderstoodCommand = "等待選擇專案"
        lastError = nil
        conversationState = .idle
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
            try stageState.replaceLightingLook(result.look)
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
        conversationState = .applying
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
            conversationState = .applying
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
            conversationState = .applying
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
        conversationState = .explaining
    }

    private func narrateIfEnabled(_ text: String) {
        guard isVoiceNarrationEnabled else { return }
        narrator.speak(text)
    }

    private static func describe(_ command: LightCommand) -> String {
        switch command {
        case .close(let number): return "已關閉 \(StageLightLabel.displayName(number: number))"
        case .open(let number): return "已重新開啟 \(StageLightLabel.displayName(number: number))"
        case .setColor(let number, let hex): return "已將 \(StageLightLabel.displayName(number: number)) 設為 \(hex)"
        case .setIntensity(let number, let fraction): return "已將 \(StageLightLabel.displayName(number: number)) 設為 \(Int((fraction * 100).rounded()))%"
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
            conversationState = .applying
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
            aiUnderstoodCommand = "已將所選燈具顏色設為 \(hexColor)"
            lastExplanation = stageState.lightingLook.explanation
            conversationState = .explaining
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
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
