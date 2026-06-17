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
#if os(iOS)
        WindowGroup {
            IPadRootView()
                .environment(appModel)
        }
#else
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
        .immersionStyle(selection: .constant(.full), in: .full)
#endif
    }
}
