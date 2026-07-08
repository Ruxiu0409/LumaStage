import Foundation
import Observation

/// Host-side glue for the iPad control panel link (visionOS target only). It owns a
/// `LumaSyncTransport`, **publishes** the host's state to the panel whenever `AppModel` changes, and
/// **applies** inbound `LumaControlCommand`s by calling the matching `AppModel` method — so the panel
/// is a thin remote and `AppModel` stays the single source of truth.
///
/// It observes `AppModel` via `withObservationTracking` rather than hooking each mutation method, so
/// adding the link required no changes to the existing lighting/AI flow — only constructing and
/// `start()`ing this coordinator. The conversation history is derived from the same observable state
/// the AI composer already drives (`conversationState` / `transcript` / `aiUnderstoodCommand` /
/// `lastExplanation`), so every generation, cue edit, or single-light command surfaces as a chat turn.
@MainActor
final class LumaSyncCoordinator {
    private let transport: any LumaSyncTransport
    private unowned let appModel: AppModel

    private(set) var connectionState: LumaSyncConnectionState = .disconnected

    /// Append-only chat history mirrored to the panel; a new turn is appended each time the host's
    /// understood-command changes to a new, non-placeholder value.
    private var chatHistory: [LumaChatMessage] = []
    private var lastUnderstood: String?
    /// The last transcript already turned into a user bubble. Manual cue edits change
    /// `aiUnderstoodCommand` without touching `transcript` (which isn't cleared after a generation),
    /// so without this guard each slider/color/cue edit would replay the previous prompt as a phantom
    /// user bubble. Only a genuinely new prompt emits a new user turn.
    private var lastPromptEmitted: String?
    private var messageCounter = 0

    private static let understoodPlaceholder = "等待語音或文字輸入"
    private static let maxHistory = 50

    init(appModel: AppModel, transport: (any LumaSyncTransport)? = nil) {
        self.appModel = appModel
        self.transport = transport ?? Self.makeDefaultTransport()
        configureTransport()
    }

    private static func makeDefaultTransport() -> any LumaSyncTransport {
#if canImport(MultipeerConnectivity)
        return MultipeerSyncTransport(displayName: "LumaStage Vision Pro")
#else
        return LoopbackSyncTransport()
#endif
    }

    /// Begins advertising for an iPad panel and starts mirroring host state. Idempotent-safe to call
    /// from a view's `.task`/`.onAppear`.
    func start() {
        transport.start(as: .visionProHost)
        beginObserving()
        publishHostState()
    }

    func stop() {
        transport.stop()
    }

    // MARK: - Transport callbacks

    private func configureTransport() {
        transport.onConnectionStateChange = { [weak self] state in
            guard let self else { return }
            self.connectionState = state
            // Re-sync a freshly joined (or reconnected) panel with a full snapshot.
            if state == .connected {
                self.publishHostState()
            }
        }
        transport.onReceive = { [weak self] message in
            self?.handle(message)
        }
    }

    private func handle(_ message: LumaSyncMessage) {
        switch message {
        case .hello:
            publishHostState()
        case .control(let command):
            apply(command)
        case .hostState, .conversation, .lighting:
            break   // host-bound payloads; ignored on the host
        }
    }

    /// Maps each inbound control command to the matching `AppModel` mutation. `AppModel` re-validates
    /// and the change reflects on the AVP immediately; the resulting state change is observed below and
    /// published straight back to the panel, so its UI confirms from the source of truth.
    private func apply(_ command: LumaControlCommand) {
        switch command {
        case .selectCue(let id):
            appModel.selectCue(id: id)
        case .setFrontLightDimmer(let value):
            appModel.setFrontLightDimmer(value)
        case .setBackgroundWashColor(let hex):
            appModel.setBackgroundWashColor(hex)
        case .setFixtureIntensity(let fixtureId, let intensity):
            appModel.setFixtureIntensity(id: fixtureId, value: intensity)
        case .setFixtureColor(let fixtureId, let hex):
            appModel.setFixtureColor(id: fixtureId, hexColor: hex)
        case .setFixtureFineControl(let fixtureId, let control):
            appModel.setFixtureFineControl(id: fixtureId, control: control)
        case .resetSelectedCue:
            appModel.resetSelectedCue()
        case .generate(let prompt):
            Task { await appModel.generate(from: prompt) }
        case .goToNextCue:
            appModel.goToNextCue()
        case .goToPreviousCue:
            appModel.goToPreviousCue()
        case .appendCue:
            appModel.appendCue()
        case .removeCue(let id):
            appModel.removeCue(id: id)
        case .setGroupMaster(let groupId, let level):
            appModel.setGroupMaster(id: groupId, level: level)
        case .bumpGroup(let groupId, let on):
            appModel.bumpGroup(id: groupId, on: on)
        case .playCueList:
            appModel.playCueList()
        case .stopCueList:
            appModel.stopCueList()
        case .setWorkflowPhase(let raw):
            // v1: honor 編程↔播放 only. Entering 架設 needs a host-side view action (dismiss the stage space,
            // open the tabletop space) the coordinator can't trigger — so ignore an iPad→架設 request.
            if let phase = WorkflowPhase(rawValue: raw), phase != .rigging {
                appModel.setWorkflowPhase(phase)
            }
        }
    }

    // MARK: - Observation → publish

    /// Arms a one-shot `withObservationTracking`; on any tracked change it republishes the full host
    /// state and re-arms. Re-publishing the whole snapshot (rather than diffing) keeps the panel
    /// trivially consistent — the payload is small and sent over a local link.
    private func beginObserving() {
        withObservationTracking {
            _ = appModel.lightingLook
            _ = appModel.conversationState
            _ = appModel.transcript
            _ = appModel.aiUnderstoodCommand
            _ = appModel.lastExplanation
            _ = appModel.lastError
            _ = appModel.stageImmersionMode
            _ = appModel.selectedCueId
            _ = appModel.groupMasters
            _ = appModel.isPlayingCueList
            _ = appModel.workflowPhase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.publishHostState()
                self.beginObserving()
            }
        }
    }

    private func publishHostState() {
        transport.send(.hostState(currentHostState()))
    }

    private func currentHostState() -> LumaHostState {
        LumaHostState(
            conversation: currentConversation(),
            lighting: appModel.lightingLook,
            immersionMode: appModel.stageImmersionMode.rawValue,
            isPlayingCueList: appModel.isPlayingCueList,
            workflowPhase: appModel.workflowPhase.rawValue
        )
    }

    private func currentConversation() -> LumaConversationState {
        reconcileHistory()
        let liveTranscript = appModel.conversationState == .idle ? "" : appModel.transcript
        return LumaConversationState(
            phase: appModel.conversationState.rawValue,
            statusText: appModel.generationStatus,
            liveTranscript: liveTranscript,
            messages: chatHistory,
            lastError: appModel.lastError
        )
    }

    /// Appends a completed turn each time the understood-command changes to a new, non-placeholder
    /// value — every generation, cue edit, or single-light command produces exactly one.
    private func reconcileHistory() {
        let understood = appModel.aiUnderstoodCommand
        guard understood != Self.understoodPlaceholder, understood != lastUnderstood else { return }
        lastUnderstood = understood

        let prompt = appModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty, prompt != lastPromptEmitted {
            chatHistory.append(makeMessage(sender: .user, text: prompt))
            lastPromptEmitted = prompt
        }

        var reply = understood
        let summary = appModel.lastExplanation.actionSummary
        if !summary.isEmpty, summary != understood {
            reply += "\n" + summary
        }
        chatHistory.append(makeMessage(sender: .model, text: reply))

        if chatHistory.count > Self.maxHistory {
            chatHistory.removeFirst(chatHistory.count - Self.maxHistory)
        }
    }

    private func makeMessage(sender: LumaChatMessage.Sender, text: String) -> LumaChatMessage {
        messageCounter += 1
        return LumaChatMessage(id: "host-\(messageCounter)", sender: sender, text: text, timestamp: Date().timeIntervalSince1970)
    }
}
