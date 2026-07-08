import Foundation

// MARK: - Workflow phases (SPEC 20 — 架設 / 編程 / 播放)
//
// The three-stage workflow that mirrors how a real lighting crew works: first rig the lights (架設),
// then program each cue (編程), then run the show (播放). This is the decidable, Foundation-only core:
// `WorkflowPhase` is pure data (it deliberately does NOT reference `AppModel.ImmersiveScene`, so it stays
// headless-testable) and `WorkflowPhasePolicy` says which operations each phase allows. `AppModel` maps
// `usesTabletopEditorSpace` onto its `ImmersiveScene` (架設 → tabletop editor space, 編程/播放 → 1:1 stage)
// and enforces the gates at its mutation methods; the SwiftUI views are thin consumers.

/// One of the three workflow stages. `rawValue` (English) is the wire/persistence value; the display
/// name is Traditional Chinese for the UI.
enum WorkflowPhase: String, Codable, CaseIterable, Equatable {
    case rigging       // 架設
    case programming   // 調控
    case playback      // 播放

    var localizedDisplayName: String {
        switch self {
        case .rigging: return "架設"
        case .programming: return "調控"
        case .playback: return "播放"
        }
    }

    /// SF Symbol name for the three-segment phase picker.
    var systemImageName: String {
        switch self {
        case .rigging: return "square.stack.3d.up"
        case .programming: return "slider.horizontal.3"
        case .playback: return "play.rectangle.on.rectangle"
        }
    }
}

/// Which operations each phase allows. Pure predicates so the smoke tests can pin the gating and the
/// views/AppModel guards read the same single source of truth.
enum WorkflowPhasePolicy {
    /// Rig fixtures can only be moved/added/removed while rigging.
    static func allowsFixtureMove(in phase: WorkflowPhase) -> Bool { phase == .rigging }
    /// The `StageLayout` (deck / truss) can only be reshaped while rigging.
    static func allowsStageLayoutEdit(in phase: WorkflowPhase) -> Bool { phase == .rigging }
    /// The tabletop diorama placement UI is only surfaced while rigging.
    static func allowsTabletopPlacement(in phase: WorkflowPhase) -> Bool { phase == .rigging }
    /// Per-cue colour/angle/intensity editing (the programming page) is only allowed while programming.
    static func allowsCueEditing(in phase: WorkflowPhase) -> Bool { phase == .programming }
    /// Jumping between cues is allowed while programming (to edit) and playback (to scrub).
    static func allowsCueJump(in phase: WorkflowPhase) -> Bool { phase == .programming || phase == .playback }
    /// The playback progress timeline only shows on the playback page.
    static func showsPlaybackTimeline(in phase: WorkflowPhase) -> Bool { phase == .playback }
    /// Whether this phase lives in the dedicated tabletop-editor immersive space (vs. the 1:1 stage space).
    /// `AppModel` uses this to decide which `ImmersiveScene` a phase maps to.
    static func usesTabletopEditorSpace(in phase: WorkflowPhase) -> Bool { phase == .rigging }
}
