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

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
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
                return "Standby"
            case .listening:
                return "Listening"
            case .transcribing:
                return "Transcribing"
            case .interpreting:
                return "Interpreting"
            case .applying:
                return "Applying"
            case .explaining:
                return "Explaining"
            case .error:
                return "Error"
            }
        }
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var stageImmersionMode: StageImmersionMode = .fullStage
    var conversationState: ConversationState = .idle
    var projects = LumaStageProject.defaultProjects()
    var selectedProjectId: String?
    var stageState = StageState(lightingLook: .mvpDemo())
    var transcript = ""
    var typedPrompt = ""
    var aiUnderstoodCommand = "Waiting for voice or text input"
    var lastExplanation = LightingLook.mvpDemo().explanation
    var generationSource: LightingGenerationSource = .foundationModels
    private(set) var modelAvailability: LightingModelAvailability = .available
    var lastError: String?

    let speechTranscriber = SpeechTranscriber()

    @ObservationIgnored
    private let aiClient: any LightingLookGenerating

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

    var displayedTranscript: String {
        if speechTranscriber.isRecording {
            return speechTranscriber.transcript.isEmpty ? "Listening..." : speechTranscriber.transcript
        }

        return transcript.isEmpty ? "No transcript yet" : transcript
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

    /// SwiftUI immersion style for the current mode: full-immersion night stage, or passthrough
    /// mixed reality so the stage spotlights can spill onto the real room.
    var immersionStyle: any ImmersionStyle {
        switch stageImmersionMode {
        case .fullStage: return .full
        case .roomSpill: return .mixed
        }
    }

    func toggleStageImmersion() {
        stageImmersionMode = stageImmersionMode == .roomSpill ? .fullStage : .roomSpill
        aiUnderstoodCommand = stageImmersionMode == .roomSpill
            ? "Spilling the stage lights onto your real room"
            : "Back to the full immersive stage"
    }

    func openProject(id: String) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == id }) else {
            fail("Project not found.")
            return
        }

        let project = projects[projectIndex]
        selectedProjectId = project.id
        stageState = StageState(lightingLook: project.lightingLook)
        transcript = ""
        typedPrompt = ""
        aiUnderstoodCommand = "Opened \(project.name)"
        lastExplanation = project.lightingLook.explanation
        generationSource = .foundationModels
        lastError = nil
        conversationState = .idle
        refreshModelAvailability()
    }

    func createProject() {
        createProject(template: .blank)
    }

    func createProject(template: ProjectCreationTemplate.Kind) {
        let project = LumaStageProject.newProject(index: projects.count + 1, template: template)
        projects.insert(project, at: 0)
        openProject(id: project.id)
    }

    func closeProject() {
        persistCurrentProjectState()
        selectedProjectId = nil
        transcript = ""
        typedPrompt = ""
        aiUnderstoodCommand = "Waiting for project selection"
        lastError = nil
        conversationState = .idle
    }

    func toggleSpeechInput() async {
        if speechTranscriber.isRecording {
            conversationState = .transcribing
            let finalTranscript = speechTranscriber.stop()
            guard !finalTranscript.isEmpty else {
                fail("I could not catch that. Use text input or try again.")
                return
            }

            await generate(from: finalTranscript)
            return
        }

        refreshModelAvailability()
        guard modelAvailability.isAvailable else {
            fail(modelAvailability.unavailableReason ?? "Apple Intelligence is unavailable.")
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
            fail("Enter a text prompt first.")
            return
        }

        await generate(from: prompt)
    }

    func generate(from prompt: String) async {
        refreshModelAvailability()
        guard modelAvailability.isAvailable else {
            fail(modelAvailability.unavailableReason ?? "Apple Intelligence is unavailable.")
            return
        }

        conversationState = .interpreting
        transcript = prompt
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
        } catch {
            fail(error.localizedDescription)
        }
    }

    func selectCue(id: String) {
        do {
            try stageState.selectCue(id: id)
            aiUnderstoodCommand = "Switched the current cue to \(selectedCue?.localizedDisplayName ?? id)"
            lastExplanation = LightingExplanation(
                term: "Cue",
                plainText: "A cue is a lighting state. When you switch cues, LumaStage animates brightness and color changes over time.",
                actionSummary: "Selected \(selectedCue?.localizedDisplayName ?? id) for preview and editing."
            )
            conversationState = .applying
            persistCurrentProjectState()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func setFrontLightDimmer(_ value: Double) {
        do {
            try stageState.patchSelectedCue(.frontLightDimmer(value))
            aiUnderstoodCommand = "Set front light intensity to \(Int(round(value * 100)))%"
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
            aiUnderstoodCommand = "Set background wash color to \(hexColor)"
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
            aiUnderstoodCommand = "Set selected fixture intensity to \(Int(round(value * 100)))%"
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
            aiUnderstoodCommand = "Set selected fixture color to \(hexColor)"
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
            aiUnderstoodCommand = "Updated selected fixture position, angle, and beam"
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
            aiUnderstoodCommand = "Reset the current cue"
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
                fail("Select a project before saving the stage layout.")
                return
            }

            projects[projectIndex].stageLayout = layout
            projects[projectIndex].lastEditedDescription = "Stage layout updated"
            aiUnderstoodCommand = "Updated the stage builder layout for \(layout.name)"
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
        projects[projectIndex].lastEditedDescription = "Current session"
    }

    private static func understoodCommand(for prompt: String) -> String {
        let lowercasedPrompt = prompt.lowercased()

        if lowercasedPrompt.contains("front light") {
            return "Adjust front light intensity so the performer reads more clearly."
        }

        if lowercasedPrompt.contains("background wash") {
            return "Adjust the background wash to change the stage color and mood."
        }

        if lowercasedPrompt.contains("highlight") {
            return "Create Opening and Highlight cues, with a brighter and more focused highlight section."
        }

        return "Generate a stage lighting design with Opening and Highlight cues."
    }
}
