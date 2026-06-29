#if os(iOS)
import SwiftUI

/// Entry point for the **LumaStage Control** iPad companion target — a thin, real-time control desk
/// for the Apple Vision Pro host. Two tabs: a live Chat mirror of the on-device Foundation Models
/// conversation, and a Lighting panel whose edits apply on the AVP at once.
///
/// This is the iPad target's `@main`; it is `#if os(iOS)`-guarded so it never collides with the
/// visionOS app's `LumaStageApp`. Add this file (and the rest of `iPadPanel/`) plus the shared
/// Foundation/transport files to the iPad target only — see `docs/ipad-control-panel-setup.md`.
@main
struct LumaPanelApp: App {
    var body: some Scene {
        WindowGroup {
            PanelRootView()
        }
    }
}
#endif
