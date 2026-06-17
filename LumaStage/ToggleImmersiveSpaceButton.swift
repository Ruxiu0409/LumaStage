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
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch appModel.immersiveSpaceState {
                    case .open:
                        appModel.immersiveSpaceState = .inTransition
                        await dismissImmersiveSpace()
                        // Don't set immersiveSpaceState to .closed because there
                        // are multiple paths to ImmersiveView.onDisappear().
                        // Only set .closed in ImmersiveView.onDisappear().

                    case .closed:
                        appModel.immersiveSpaceState = .inTransition
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                // Don't set immersiveSpaceState to .open because there
                                // may be multiple paths to ImmersiveView.onAppear().
                                // Only set .open in ImmersiveView.onAppear().
                                break

                            case .userCancelled, .error:
                                // On error, we need to mark the immersive space
                                // as closed because it failed to open.
                                fallthrough
                            @unknown default:
                                // On unknown response, assume space did not open.
                                appModel.immersiveSpaceState = .closed
                        }

                    case .inTransition:
                        // This case should not ever happen because button is disabled for this case.
                        break
                }
            }
        } label: {
            switch displayStyle {
            case .label:
                Label(
                    appModel.immersiveSpaceState == .open ? "Close Stage" : "Open Stage",
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
