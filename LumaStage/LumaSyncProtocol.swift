import Foundation

// MARK: - LumaStage device-to-device sync protocol
//
// The wire schema shared between the **Apple Vision Pro host** (the source of truth, where the
// immersive stage and on-device Foundation Models run) and the **iPad control panel** (a thin
// real-time remote). It is deliberately:
//
//  - **Transport-agnostic** — it says *what* is exchanged, not *how*. A Multipeer Connectivity
//    session, a Network.framework connection, or an in-process loopback can all carry these values.
//    Both ends just `JSONEncoder`/`JSONDecoder` a `LumaSyncMessage`.
//  - **Foundation-only** — no SwiftUI / RealityKit / FoundationModels imports, so it lives in the
//    shared testable core and the smoke tests can pin round-trip `Codable` behavior without a live
//    connection or a simulator (see `LumaSyncProtocolRoundTrips`).
//  - **Reuse-first** — lighting payloads reuse the already-`Codable` `LightingLook` /
//    `FixtureFineControl` domain models rather than re-describing them, and control commands map 1:1
//    to existing `AppModel` mutation metho ds, so there is a single schema, not two drifting copies.
//
// Direction is documented per case; both ends send and receive the same `LumaSyncMessage` envelope
// over one channel.

/// Identifies which side of the link a peer is, exchanged once on connect so each end knows whether
/// it should publish host state or send control commands.
enum LumaPeerRole: String, Codable, Equatable, CaseIterable {
    case visionProHost
    case iPadPanel
}

/// The single envelope exchanged over the link. Swift synthesizes `Codable`/`Equatable` for enums
/// with associated values, so the whole protocol round-trips for free.
enum LumaSyncMessage: Codable, Equatable {
    /// Handshake (either → either): announces who just connected so the host can immediately reply
    /// with a full `.hostState` snapshot.
    case hello(role: LumaPeerRole)

    /// AVP → iPad: a complete snapshot of host state. Sent on connect and as a re-sync fallback, so a
    /// freshly-joined or reconnected iPad is instantly consistent without replaying deltas.
    case hostState(LumaHostState)

    /// AVP → iPad: a conversation-only delta (high frequency during a generation — transcription,
    /// interpreting, explaining). Lets the Chat tab update live without resending the lighting look.
    case conversation(LumaConversationState)

    /// AVP → iPad: a lighting-only delta after a cue/look change. Reuses the domain `LightingLook`.
    case lighting(LightingLook)

    /// iPad → AVP: a control-panel edit to apply to the live look (and reflect on the AVP at once).
    case control(LumaControlCommand)
}

/// AVP → iPad. The full host state mirrored by the panel on connect.
struct LumaHostState: Codable, Equatable {
    var conversation: LumaConversationState
    var lighting: LightingLook
    /// `StageImmersionMode.rawValue` — lets the panel show (and later toggle) full-stage vs room-spill.
    var immersionMode: String
}

/// AVP → iPad. Everything the Chat tab renders: the live conversation with Foundation Models.
struct LumaConversationState: Codable, Equatable {
    /// `AppModel.ConversationState.rawValue` (idle / listening / transcribing / interpreting /
    /// applying / explaining / error). Kept as a string so the schema does not depend on the host's
    /// observable model — the panel maps it to its own UI.
    var phase: String
    /// Human-readable status line (e.g. the generation source or the unavailable reason).
    var statusText: String
    /// The in-progress (partial) transcript, shown as a live "listening / typing" bubble. Empty when
    /// nothing is being captured.
    var liveTranscript: String
    /// Completed conversation turns, oldest first — the chat history the panel lists.
    var messages: [LumaChatMessage]
    /// The most recent user-facing error, if any (surfaced as a system bubble).
    var lastError: String?

    static let empty = LumaConversationState(phase: "idle", statusText: "", liveTranscript: "", messages: [], lastError: nil)
}

/// One bubble in the Chat tab. `id`/`timestamp` are supplied by the sender (the schema never calls
/// `UUID()`/`Date()` itself, so it stays pure and the smoke tests stay deterministic).
struct LumaChatMessage: Codable, Equatable, Identifiable {
    enum Sender: String, Codable, Equatable {
        case user      // the operator's voice/typed prompt
        case model     // Foundation Models' reply (the understood command + explanation)
        case system    // status / errors
    }

    var id: String
    var sender: Sender
    var text: String
    /// Epoch seconds, stamped by the sender at send time.
    var timestamp: Double
}

/// iPad → AVP. Each case maps 1:1 to an `AppModel` mutation so the host receiver is a thin switch.
/// Edits only ever target the **currently selected cue** (the same invariant `StageState` enforces),
/// except `selectCue`, which changes the selection, and `generate`, which replaces the whole look.
enum LumaControlCommand: Codable, Equatable {
    /// Maps to `AppModel.selectCue(id:)`.
    case selectCue(id: String)
    /// Maps to `AppModel.setFrontLightDimmer(_:)` — 0...1.
    case setFrontLightDimmer(Double)
    /// Maps to `AppModel.setBackgroundWashColor(_:)` — `#RRGGBB`.
    case setBackgroundWashColor(hex: String)
    /// Maps to `AppModel.setFixtureIntensity(id:value:)` — 0...1.
    case setFixtureIntensity(fixtureId: String, intensity: Double)
    /// Maps to `AppModel.setFixtureColor(id:hexColor:)` — `#RRGGBB`.
    case setFixtureColor(fixtureId: String, hex: String)
    /// Maps to `AppModel.setFixtureFineControl(id:control:)`. Reuses the domain `FixtureFineControl`.
    case setFixtureFineControl(fixtureId: String, control: FixtureFineControl)
    /// Maps to `AppModel.resetSelectedCue()`.
    case resetSelectedCue
    /// Maps to `AppModel.generate(from:)` — an iPad-initiated prompt; the AVP runs Foundation Models
    /// and streams the result back as `.conversation` + `.lighting` updates.
    case generate(prompt: String)
    /// Maps to `AppModel.goToNextCue()` — the GO key: advance the cue stack (wraps at the end).
    case goToNextCue
    /// Maps to `AppModel.goToPreviousCue()` — step back through the cue stack.
    case goToPreviousCue
    /// Maps to `AppModel.appendCue()` — duplicate the current cue into the stack as a new one.
    case appendCue
    /// Maps to `AppModel.removeCue(id:)` — remove a cue from the stack (never the last one).
    case removeCue(id: String)
    /// Maps to `AppModel.setGroupMaster(id:level:)` — ride a group submaster (0...1). The `groupId` is a
    /// `StandardFixtureGroup.id` (e.g. "group_front"); scales every member light with no explicit
    /// per-light intensity override (SPEC 08 load invariant).
    case setGroupMaster(groupId: String, level: Double)
    /// Maps to `AppModel.bumpGroup(id:on:)` — momentary flash: `on` drives the group to full, `off`
    /// releases it back to following the cue.
    case bumpGroup(groupId: String, on: Bool)
}
