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

    @State private var requestedStageProjectId: String?

    var body: some View {
        Group {
            if appModel.selectedProject == nil {
                ProjectSelectionView()
                    .frame(width: 760)
            } else if appModel.immersiveSpaceState == .open {
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            } else {
                VisionAIComposerBox()
                    .frame(width: 820)
            }
        }
        .task(id: appModel.selectedProjectId) {
            await openDefaultStageIfNeeded()
        }
    }

    @MainActor
    private func openDefaultStageIfNeeded() async {
        guard let selectedProjectId = appModel.selectedProjectId,
              requestedStageProjectId != selectedProjectId,
              appModel.immersiveSpaceState == .closed else {
            return
        }

        requestedStageProjectId = selectedProjectId
        appModel.immersiveSpaceState = .inTransition

        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            break
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
#endif
