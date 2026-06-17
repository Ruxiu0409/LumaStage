import SwiftUI

#if os(iOS)
struct IPadRootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        GeometryReader { proxy in
            Group {
                if appModel.selectedProject == nil {
                    ProjectSelectionView()
                        .frame(width: CGFloat(IPadRootLayout.projectSelectionWidth(availableWidth: proxy.size.width)))
                        .padding(CGFloat(IPadRootLayout.projectSelectionHorizontalPadding))
                } else {
                    IPadCompanionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            LinearGradient(
                colors: [
                    LumaStageDesign.nightBlack,
                    Color(red: 0.052, green: 0.055, blue: 0.064)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    IPadRootView()
        .environment(AppModel())
}
#endif
