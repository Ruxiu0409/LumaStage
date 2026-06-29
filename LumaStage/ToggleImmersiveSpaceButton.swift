//
//  ToggleImmersiveSpaceButton.swift
//  LumaStage
//
//  Created by Tsai Cheng-Yeh on 2026/5/20.
//

import SwiftUI

#if os(visionOS)
struct ToggleImmersiveSpaceButton: View {
    enum DisplayStyle {
        case label
        case icon
    }

    var displayStyle: DisplayStyle = .label

    @Environment(AppModel.self) private var appModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                    case .open:
                        // Hide the stage but keep the project open — the composer returns to the main
                        // window. Clear the desired scene first so `ContentView` doesn't immediately
                        // reopen the stage when its reconciler re-runs.
                        appModel.desiredImmersiveScene = .none
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        // Don't set .closed here — ImmersiveView.onDisappear owns that transition.

                    case .closed:
                        // Ask for the stage; `ContentView`'s reconciler opens it (it owns `openImmersiveSpace`
                        // so the open is driven from the always-alive main window).
                        appModel.desiredImmersiveScene = .stage

                    case .inTransition:
                        // This case should not ever happen because button is disabled for this case.
                        break
                }
            }
        } label: {
            switch displayStyle {
            case .label:
                Label(
                    appModel.immersiveSpaceState == .open ? "關閉舞台" : "開啟舞台",
                    systemImage: appModel.immersiveSpaceState == .open ? "rectangle.slash" : "sparkles"
                )
            case .icon:
                Image(systemName: appModel.immersiveSpaceState == .open ? "rectangle.slash" : "sparkles")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(appModel.immersiveSpaceState == .open ? LumaStageDesign.warmAmber : LumaStageDesign.textSecondary)
            }
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
}
#endif
