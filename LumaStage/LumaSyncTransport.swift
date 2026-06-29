import Foundation

// MARK: - Transport abstraction for the iPad <-> Apple Vision Pro link
//
// `LumaSyncProtocol` says *what* is exchanged; this says *how it is delivered*, behind an interface.
// The host coordinator and the iPad panel depend on the `LumaSyncTransport` protocol, never on
// Multipeer Connectivity directly — exactly how `AppModel` depends on `LightingLookGenerating`. That
// lets the real `MultipeerSyncTransport` (a separate, non-Foundation file) be swapped for the
// in-process `LoopbackSyncTransport` in previews and the smoke tests, so the full message flow runs
// without a second device or a live session.
//
// This file is Foundation-only (no MultipeerConnectivity import), so it stays in the testable core.

/// The link's lifecycle, surfaced in both UIs (e.g. a "Searching… / Connected" pill).
enum LumaSyncConnectionState: String, Codable, Equatable, Sendable {
    case disconnected
    case advertising   // host: waiting for a panel to join
    case browsing      // panel: looking for a host
    case connecting
    case connected
}

/// JSON wire codec shared by every transport, so all links frame `LumaSyncMessage` identically.
enum LumaSyncCodec {
    static func encode(_ message: LumaSyncMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) throws -> LumaSyncMessage {
        try JSONDecoder().decode(LumaSyncMessage.self, from: data)
    }
}

/// A bidirectional link carrying `LumaSyncMessage`s between the two devices. Implementations deliver
/// `onReceive` / `onConnectionStateChange` on the **main thread** so SwiftUI/`@Observable` consumers
/// can mutate state directly.
protocol LumaSyncTransport: AnyObject {
    var connectionState: LumaSyncConnectionState { get }

    /// Invoked (on the main thread) for every decoded inbound message.
    var onReceive: ((LumaSyncMessage) -> Void)? { get set }
    /// Invoked (on the main thread) whenever `connectionState` changes.
    var onConnectionStateChange: ((LumaSyncConnectionState) -> Void)? { get set }

    /// Begin the link in the given role — the host advertises, the panel browses. Idempotent.
    func start(as role: LumaPeerRole)
    /// Tear the link down and return to `.disconnected`.
    func stop()
    /// Fire-and-forget send. Silently dropped when not `.connected` — the host re-syncs with a full
    /// `.hostState` snapshot on (re)connect, so a dropped delta is never fatal.
    func send(_ message: LumaSyncMessage)
}

/// In-process transport for previews and tests: pair two instances with `connect(to:)` and each
/// other's `send` is delivered to the peer's `onReceive` synchronously. Every send round-trips
/// through `LumaSyncCodec`, so the loopback exercises the same encode/decode path the real transports
/// use (a payload that fails to round-trip fails here too, in a headless test rather than on device).
final class LoopbackSyncTransport: LumaSyncTransport {
    private(set) var connectionState: LumaSyncConnectionState = .disconnected
    var onReceive: ((LumaSyncMessage) -> Void)?
    var onConnectionStateChange: ((LumaSyncConnectionState) -> Void)?

    private weak var peer: LoopbackSyncTransport?

    /// Wires two loopback transports together and marks both connected.
    func connect(to other: LoopbackSyncTransport) {
        peer = other
        other.peer = self
        setState(.connected)
        other.setState(.connected)
    }

    func start(as role: LumaPeerRole) {
        // Loopback has no discovery; a paired peer is connected via `connect(to:)`.
        if peer != nil { setState(.connected) }
    }

    func stop() {
        peer?.peer = nil
        peer = nil
        setState(.disconnected)
    }

    func send(_ message: LumaSyncMessage) {
        guard let peer, connectionState == .connected else { return }
        guard let data = try? LumaSyncCodec.encode(message),
              let decoded = try? LumaSyncCodec.decode(data) else { return }
        peer.onReceive?(decoded)
    }

    private func setState(_ state: LumaSyncConnectionState) {
        guard state != connectionState else { return }
        connectionState = state
        onConnectionStateChange?(state)
    }
}
