#if os(iOS)
import Foundation
import Observation

/// The iPad control panel's state. A thin remote: it holds the latest `LumaHostState` mirrored from
/// the Apple Vision Pro and sends `LumaControlCommand`s back over the same `LumaSyncTransport` the
/// host uses. The AVP remains the single source of truth — every edit is applied there and echoed
/// back, so the panel always reflects confirmed state.
@MainActor
@Observable
final class LumaPanelModel {
    private let transport: any LumaSyncTransport

    private(set) var connectionState: LumaSyncConnectionState = .disconnected
    /// The last full snapshot from the host; `nil` until the first one arrives.
    private(set) var host: LumaHostState?

    /// When true, the panel runs on baked-in sample data with no real link: `start()` is a no-op and
    /// `send(_:)` applies edits to the local sample so the UI stays fully interactive offline. Set by
    /// `mockPreview()`; production builds leave it `false`.
    private(set) var isMock = false

    init(transport: (any LumaSyncTransport)? = nil) {
#if canImport(MultipeerConnectivity)
        self.transport = transport ?? MultipeerSyncTransport(displayName: "LumaStage iPad")
#else
        self.transport = transport ?? LoopbackSyncTransport()
#endif
        configureTransport()
    }

    /// Begins browsing for the AVP host and announces this panel.
    func start() {
        guard !isMock else { return }   // the mock panel never opens a real link
        transport.start(as: .iPadPanel)
        transport.send(.hello(role: .iPadPanel))
    }

    func stop() {
        transport.stop()
    }

    // MARK: - Read accessors for the views

    var conversation: LumaConversationState {
        host?.conversation ?? .empty
    }

    var lighting: LightingLook? {
        host?.lighting
    }

    /// The cue currently selected on the host, if a look has arrived.
    var selectedCue: LightingCue? {
        guard let look = host?.lighting else { return nil }
        return look.cues.first(where: { $0.id == look.selectedCueId })
    }

    var isConnected: Bool {
        connectionState == .connected
    }

    var connectionStatusText: String {
        switch connectionState {
        case .disconnected: return "已中斷連線"
        case .advertising: return "等待中…"
        case .browsing: return "正在搜尋 Vision Pro…"
        case .connecting: return "連線中…"
        case .connected: return "已連線"
        }
    }

    // MARK: - Sending edits

    func send(_ command: LumaControlCommand) {
        if isMock {
            applyLocally(command)   // no host on the other end — reflect the edit in our sample state
            return
        }
        transport.send(.control(command))
    }

    // MARK: - Transport

    private func configureTransport() {
        transport.onConnectionStateChange = { [weak self] state in
            guard let self else { return }
            self.connectionState = state
            // On (re)connect, re-announce so the host immediately replies with a full snapshot.
            if state == .connected {
                self.transport.send(.hello(role: .iPadPanel))
            }
        }
        transport.onReceive = { [weak self] message in
            guard let self else { return }
            switch message {
            case .hostState(let snapshot):
                self.host = snapshot
            case .conversation(let conversation):
                self.host?.conversation = conversation
            case .lighting(let look):
                self.host?.lighting = look
            case .hello, .control:
                break   // panel-bound payloads; ignored on the panel
            }
        }
    }

    // MARK: - Offline mock mode

    /// A panel preloaded with sample lighting + chat so the iPad UI can be built and reviewed without a
    /// live Apple Vision Pro link. Reports `.connected`, seeds a full `LumaHostState`, makes `start()` a
    /// no-op, and applies control edits to the sample so sliders / swatches / the cue picker stay
    /// interactive offline. To reconnect for real, build `LumaPanelModel()` instead (see `PanelRootView`).
    static func mockPreview() -> LumaPanelModel {
        let model = LumaPanelModel(transport: LoopbackSyncTransport())
        model.isMock = true
        model.connectionState = .connected
        model.host = Self.sampleHostState()
        return model
    }

    /// Applies a control command to the in-memory sample state (mock mode only) so the panel reflects
    /// the edit at once — the same fields the host would change, minus the real on-stage relight.
    private func applyLocally(_ command: LumaControlCommand) {
        guard var state = host else { return }
        switch command {
        case .selectCue(let id):
            state.lighting.selectedCueId = id
        case .setFixtureIntensity(let fixtureId, let intensity):
            Self.mutateFixture(in: &state.lighting, fixtureId: fixtureId) { $0.intensity = intensity }
        case .setFixtureColor(let fixtureId, let hex):
            Self.mutateFixture(in: &state.lighting, fixtureId: fixtureId) { $0.color.value = hex }
        case .setFixtureFineControl(let fixtureId, let control):
            Self.mutateFixture(in: &state.lighting, fixtureId: fixtureId) { $0.fineControl = control }
        case .generate(let prompt):
            let n = state.conversation.messages.count
            state.conversation.messages.append(
                LumaChatMessage(id: "mock_u\(n)", sender: .user, text: prompt, timestamp: Double(n))
            )
            state.conversation.messages.append(
                LumaChatMessage(id: "mock_m\(n)", sender: .model,
                                text: "（示範資料）已依「\(prompt)」更新燈光效果。實際生成需連線 Vision Pro。",
                                timestamp: Double(n) + 0.1)
            )
        case .goToNextCue:
            Self.advanceMockSelection(in: &state.lighting, by: 1)
        case .goToPreviousCue:
            Self.advanceMockSelection(in: &state.lighting, by: -1)
        case .appendCue:
            if let source = state.lighting.cues.first(where: { $0.id == state.lighting.selectedCueId }) {
                var duplicate = source
                duplicate.id = "mock_cue_\(state.lighting.cues.count)"
                duplicate.name = "場景 \(state.lighting.cues.count + 1)"
                state.lighting.cues.append(duplicate)
                state.lighting.selectedCueId = duplicate.id
            }
        case .removeCue(let id):
            if state.lighting.cues.count > 1 {
                state.lighting.cues.removeAll { $0.id == id }
                if !state.lighting.cues.contains(where: { $0.id == state.lighting.selectedCueId }) {
                    state.lighting.selectedCueId = state.lighting.cues.first?.id ?? state.lighting.selectedCueId
                }
            }
        case .resetSelectedCue, .setFrontLightDimmer, .setBackgroundWashColor:
            break   // no baseline / legacy single-light paths in the mock
        }
        host = state
    }

    /// Advances the mock's selected cue by `step` (wrapping) so the panel's GO works offline.
    private static func advanceMockSelection(in look: inout LightingLook, by step: Int) {
        guard !look.cues.isEmpty else { return }
        let current = look.cues.firstIndex(where: { $0.id == look.selectedCueId }) ?? 0
        let count = look.cues.count
        let next = ((current + step) % count + count) % count
        look.selectedCueId = look.cues[next].id
    }

    private static func mutateFixture(
        in look: inout LightingLook,
        fixtureId: String,
        _ transform: (inout FixtureGroup) -> Void
    ) {
        guard let cueIndex = look.cues.firstIndex(where: { $0.id == look.selectedCueId }),
              let fixtureIndex = look.cues[cueIndex].fixtureGroups.firstIndex(where: { $0.id == fixtureId })
        else { return }
        transform(&look.cues[cueIndex].fixtureGroups[fixtureIndex])
    }

    // MARK: - Sample data

    private static func sampleHostState() -> LumaHostState {
        LumaHostState(
            conversation: sampleConversation(),
            lighting: .showcaseDemo(),   // 8 diverse fixtures, each with a DMX patch + aim target
            immersionMode: StageImmersionMode.fullStage.rawValue
        )
    }

    private static func sampleConversation() -> LumaConversationState {
        LumaConversationState(
            phase: "idle",
            statusText: "示範資料（尚未連線 Vision Pro）",
            liveTranscript: "",
            messages: [
                LumaChatMessage(id: "mock_1", sender: .user,
                                text: "幫我設計一個學生戶外舞台的開場燈光，溫暖一點", timestamp: 1),
                LumaChatMessage(id: "mock_2", sender: .model,
                                text: "已生成開場與重點兩個場景：開場以溫暖前光打亮表演者，背景用冷色泛光做對比；重點場景再提高前光亮度，強化戲劇張力。",
                                timestamp: 2),
                LumaChatMessage(id: "mock_3", sender: .user,
                                text: "重點場景背景換成深藍色", timestamp: 3),
                LumaChatMessage(id: "mock_4", sender: .model,
                                text: "已將重點場景的背景泛光改為深藍，前光維持暖色，讓冷暖對比更明顯。",
                                timestamp: 4)
            ],
            lastError: nil
        )
    }
}
#endif
