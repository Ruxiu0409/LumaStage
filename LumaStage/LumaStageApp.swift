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

        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 860, height: 260)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: immersionStyleSelection, in: .full, .mixed)
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
