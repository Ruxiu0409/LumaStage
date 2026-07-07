//
//  LumaStageApp.swift
//  LumaStage
//
//  Created by Tsai Cheng-Yeh on 2026/5/20.
//

import SwiftUI

@main
struct LumaStageApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        // Eager read so the Scene re-evaluates — and re-applies the immersion style — when the
        // in-space toggle flips stageImmersionMode. A computed `var` body would not otherwise
        // observe a property only read inside the lazy binding closure below.
        let _ = appModel.stageImmersionMode

        WindowGroup(id: AppModel.mainWindowID) {
            ContentView()
                .environment(appModel)
                // Advertise for the iPad control panel as soon as the app is up. Idempotent, so it
                // survives the main window being dismissed/recreated for the immersive stage.
                .task { appModel.startIPadSync() }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 860, height: 260)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            // `ImmersiveView` owns the open/close lifecycle (state + opening the composer window)
            // in its own onAppear/onDisappear, since `openWindow` needs a View environment.
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: immersionStyleSelection, in: .full, .mixed)

        // The AI composer is a real native window (not a RealityView attachment) so it gets the
        // system move bar and smooth, compositor-driven dragging. `.plain` lets the panel's own
        // glass be the surface; `.utilityPanel` placement seats it within reach in front of the
        // user each time it opens. `.environment(appModel)` is required — `openWindow` doesn't
        // inherit the opener's environment. Opened/dismissed with the immersive space by
        // `ImmersiveView` (own-app windows aren't auto-hidden in full immersion).
        //
        // It MUST be a `Window`, not a `WindowGroup` (same fix as 燈光控制 below): the composer is a
        // single reusable panel, but a `WindowGroup` spawns a NEW window on every `openWindow(id:)`,
        // so a dropped dismiss during a space transition could leave two composers on screen at once
        // (issue #11). A `Window` is a singleton scene — `openWindow` just brings the one instance
        // forward instead of duplicating it.
        Window("AI 對話框", id: AppModel.aiComposerWindowID) {
            VisionAIComposerBox()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }

        // The per-light manual control card is a real native window (not a RealityView attachment),
        // mirroring the AI composer above: it gets the system move bar (the built-in panel-move
        // affordance the user asked for) AND owns its own position across content updates, so changing
        // a light's colour/brightness no longer re-seats the card to a generated spot (the attachment-
        // re-resolve "jump" bug). `.environment(appModel)` is required — `openWindow` does NOT inherit
        // the opener's environment. Opened/dismissed reactively by `ImmersiveView` as the selected
        // light changes (and dismissed when the stage space closes).
        //
        // It MUST be a `Window`, not a `WindowGroup`: this is a single, unique, reusable card that reflects
        // the one shared `appModel.selectedLightNumber`. A `WindowGroup` spawns a NEW window on every
        // `openWindow(id:)` call, so selecting light after light piled up a stack of duplicate cards that
        // all rendered the same (latest) light. A `Window` is a singleton scene — `openWindow` on an
        // already-open `Window` just brings it forward, and switching lights re-renders the same card.
        Window("燈光控制", id: AppModel.lightControlWindowID) {
            SelectedLightControlView()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }

        // Spatial fixture observatory, opened from the Fixture Guide as two independent, separately
        // movable objects sharing `appModel.fixtureCarousel`: a volumetric window holding the 3D
        // model, and a plain window holding the info card (with its own paging + back controls).
        WindowGroup(id: AppModel.fixtureObservatoryWindowID) {
            FixtureObservatoryView()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.7, height: 0.7, depth: 0.7, in: .meters)

        WindowGroup(id: AppModel.fixtureInfoCardWindowID) {
            FixtureInfoCardWindow()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .defaultSize(width: 480, height: 460)
        // Open the info card to the RIGHT of the volumetric model window, so each fixture is
        // presented with its 3D model on the left and its info card on the right. The model window
        // opens the card from its own onAppear (see `FixtureObservatoryView`), so the model window is
        // already registered in `context.windows` when this placement runs; if it isn't found, fall
        // back to a utility panel in front of the user.
        .defaultWindowPlacement { _, context in
            if let observatory = context.windows.first(where: { $0.id == AppModel.fixtureObservatoryWindowID }) {
                #if DEBUG
                print("Fixture info card placement: found observatory -> trailing")
                #endif
                return WindowPlacement(.trailing(observatory))
            }
            #if DEBUG
            print("Fixture info card placement: fallback -> utilityPanel")
            #endif
            return WindowPlacement(.utilityPanel)
        }

        // Tabletop stage editor: a small editable stage model that ARKit rests on the user's real table.
        // Its own MIXED (passthrough) immersive space — so the room is visible and content can anchor to
        // a detected table — opened from the AI composer's "Edit Stage" button in place of the 1:1 stage
        // space. Edits persist to the project, so the immersive stage reflects them on return.
        ImmersiveSpace(id: appModel.tabletopEditorSpaceID) {
            TabletopStageEditorView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    /// A mutable binding (not `.constant`) so the system can write immersion changes back into the
    /// model; the getter derives the style from `stageImmersionMode` so the in-space toggle drives
    /// the full↔mixed transition live.
    private var immersionStyleSelection: Binding<any ImmersionStyle> {
        Binding(
            get: { appModel.immersionStyle },
            set: { appModel.stageImmersionMode = ($0 is MixedImmersionStyle) ? .roomSpill : .fullStage }
        )
    }
}
