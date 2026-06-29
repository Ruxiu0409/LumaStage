import Foundation

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity

/// Real-time iPad <-> Apple Vision Pro link over **Multipeer Connectivity** (local Wi-Fi / peer-to-peer,
/// no server, no account) — the concrete `LumaSyncTransport` used in the shipping app. The host
/// advertises; the panel browses and auto-invites; both ends exchange JSON-encoded `LumaSyncMessage`s
/// over a reliable `MCSession`.
///
/// Lives outside the Foundation-only test core because it imports MultipeerConnectivity; the smoke
/// tests cover the transport *contract* via `LoopbackSyncTransport` instead (same as how the on-device
/// Foundation Models service is excluded and the AI→domain boundary is tested via `LightingLookDraft`).
///
/// **Concurrency:** the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this type
/// is implicitly main-actor isolated. MC, however, invokes the delegate methods on its own private
/// queues, so each delegate method is marked `nonisolated` and hops to the main actor before touching
/// the `@MainActor` state (`connectionState`) or the consumer callbacks. The `MCSession` is held
/// `nonisolated(unsafe)` because it is itself thread-safe and the delegate methods need it off-main.
///
/// Both targets must declare the service in Info.plist: `NSLocalNetworkUsageDescription` and
/// `NSBonjourServices` = `_lumastage-sync._tcp` / `_lumastage-sync._udp` (see
/// `docs/ipad-control-panel-setup.md`).
final class MultipeerSyncTransport: NSObject, LumaSyncTransport {
    /// MC service type: 1–15 chars, lowercase letters/digits/hyphens. Must match on both devices.
    static let serviceType = "lumastage-sync"

    private(set) var connectionState: LumaSyncConnectionState = .disconnected
    var onReceive: ((LumaSyncMessage) -> Void)?
    var onConnectionStateChange: ((LumaSyncConnectionState) -> Void)?

    private let myPeerID: MCPeerID
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var role: LumaPeerRole?

    /// `MCSession` is documented thread-safe, and the MC delegate callbacks (which run off-main) need
    /// it, so it is `nonisolated(unsafe)` rather than main-isolated.
    nonisolated(unsafe) private let session: MCSession

    /// `displayName` shows up as the peer's name; a short random suffix keeps two peers from colliding.
    init(displayName: String = "LumaStage") {
        let base = String(displayName.prefix(50))
        let suffix = String(UUID().uuidString.prefix(4))
        myPeerID = MCPeerID(displayName: "\(base)-\(suffix)")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func start(as role: LumaPeerRole) {
        stop()
        self.role = role
        switch role {
        case .visionProHost:
            let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
            setConnectionState(.advertising)
        case .iPadPanel:
            let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
            setConnectionState(.browsing)
        }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
        role = nil
        setConnectionState(.disconnected)
    }

    func send(_ message: LumaSyncMessage) {
        let peers = session.connectedPeers
        guard !peers.isEmpty, let data = try? LumaSyncCodec.encode(message) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    // MARK: - Main-actor state (only mutated on the main actor)

    private func setConnectionState(_ newValue: LumaSyncConnectionState) {
        guard newValue != connectionState else { return }
        connectionState = newValue
        onConnectionStateChange?(newValue)
    }

    /// Re-derives the discovery state after a peer drops, so a reconnect can happen automatically.
    private func resyncDiscoveryState() {
        guard session.connectedPeers.isEmpty else {
            setConnectionState(.connected)
            return
        }
        switch role {
        case .visionProHost: setConnectionState(.advertising)
        case .iPadPanel: setConnectionState(.browsing)
        case .none: setConnectionState(.disconnected)
        }
    }

    private func deliver(_ message: LumaSyncMessage) {
        onReceive?(message)
    }

    /// Bridges an off-main MC callback to the main actor while preserving delivery order.
    nonisolated private func onMain(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
    }
}

// MARK: - MCSessionDelegate (invoked off-main)

extension MultipeerSyncTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        onMain { [weak self] in
            switch state {
            case .connected: self?.setConnectionState(.connected)
            case .connecting: self?.setConnectionState(.connecting)
            case .notConnected: self?.resyncDiscoveryState()
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? LumaSyncCodec.decode(data) else { return }
        onMain { [weak self] in self?.deliver(message) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser (host)

extension MultipeerSyncTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Single-panel control desk: accept any invitation onto our one (thread-safe) session.
        invitationHandler(true, session)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onMain { [weak self] in self?.setConnectionState(.disconnected) }
    }
}

// MARK: - Browser (panel)

extension MultipeerSyncTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onMain { [weak self] in self?.setConnectionState(.disconnected) }
    }
}
#endif
