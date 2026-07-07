//
//  ContentView.swift
//  LumaStage
//
//  Created by Tsai Cheng-Yeh on 2026/5/20.
//

import SwiftUI

#if os(visionOS)
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if appModel.isInspectingFixture {
                // Hide the project window while the fixture observatory windows are open.
                clearPlaceholder
            } else if appModel.selectedProject == nil {
                ProjectSelectionView()
                    .frame(width: 760)
                    // Invariant safety net: the project list must never coexist with the AI composer's
                    // own window. That window is normally torn down in `ImmersiveView.onDisappear`, but
                    // a `dismissWindow` issued during the immersive-space close transition is sometimes
                    // dropped by the system, leaving the composer floating after we return to the list.
                    // Re-dismissing here whenever the list appears guarantees it's gone (a no-op if it
                    // already is). Also fires once harmlessly at launch.
                    .onAppear { dismissWindow(id: AppModel.aiComposerWindowID) }
            } else if appModel.immersiveSpaceState == .open || appModel.desiredImmersiveScene != .none {
                // A project is selected and an immersive space is open (or about to open) — the stage/editor
                // content lives in that space, not here, so the main window collapses to a clear
                // placeholder. (Also covers the brief transition frame so the composer doesn't flash.)
                clearPlaceholder
            } else {
                VisionAIComposerBox()
                    .frame(width: 820)
            }
        }
        // Reconcile whenever the desired scene changes AND whenever this window is (re)created — every
        // immersive-space close reopens this main window, and the recreated view's `.task` is what opens
        // the next space in the swap.
        .task(id: appModel.desiredImmersiveScene) {
            await reconcileImmersiveScene()
        }
    }

    private var clearPlaceholder: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
    }

    /// Opens whichever immersive space `desiredImmersiveScene` names — but only when none is currently open.
    /// The stage↔editor swap is two-step: the leaving space dismisses itself (its caller calls
    /// `dismissImmersiveSpace`), its `onDisappear` reopens this main window, and the recreated `ContentView`
    /// runs this to open the next space. Driving the open from the always-recreated main window (never from
    /// inside a space, which is torn down mid-transition) is what makes the hand-off reliable.
    ///
    /// visionOS intermittently rejects an open issued while the previous space's dismiss transition is
    /// still winding down, so a failed open retries on `ImmersiveSceneReopenPolicy`'s backoff. When the
    /// retries are exhausted, giving up must be *visible*: clearing `desiredImmersiveScene` returns this
    /// window to the AI composer (whose 開啟舞台 button re-requests the stage) instead of leaving the user
    /// stranded on the invisible transition placeholder with a desired scene no one will ever honor.
    @MainActor
    private func reconcileImmersiveScene() async {
        // A cancelled predecessor task (desired scene changed mid-retry) resets `.inTransition` back to
        // `.closed` on its way out — give it a beat instead of bailing, because bailing would strand
        // `desiredImmersiveScene` with no reconciler left to honor it.
        while appModel.immersiveSpaceState == .inTransition {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }

        guard appModel.immersiveSpaceState == .closed else {
            return
        }

        let spaceID: String
        switch appModel.desiredImmersiveScene {
        case .none:
            return
        case .stage:
            spaceID = appModel.immersiveSpaceID
        case .tabletopEditor:
            spaceID = appModel.tabletopEditorSpaceID
        }

        appModel.immersiveSpaceState = .inTransition
        var attempt = 1
        while true {
            switch await openImmersiveSpace(id: spaceID) {
            case .opened:
                return // the space's onAppear sets immersiveSpaceState = .open
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                guard let delay = ImmersiveSceneReopenPolicy.retryDelayNanoseconds(afterFailedAttempt: attempt) else {
                    appModel.immersiveSpaceState = .closed
                    appModel.desiredImmersiveScene = .none
                    return
                }
                attempt += 1
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    // Cancelled mid-backoff — release the transition state so the successor task's
                    // settle-wait above can take over.
                    appModel.immersiveSpaceState = .closed
                    return
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
#endif
