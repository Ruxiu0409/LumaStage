import SwiftUI

struct IPadCompanionView: View {
    @Environment(AppModel.self) private var appModel
    @State private var workspaceMode: IPadWorkspaceMode = .stageBuilder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if workspaceMode == .stageBuilder {
                StageBuilderView()
                    .frame(maxWidth: .infinity, minHeight: 640)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    lightingPreviewColumn

                    lightingControlsColumn
                }
            }
        }
        .padding(24)
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
        .foregroundStyle(LumaStageDesign.textPrimary)
    }

    private var lightingPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
                StageStatusStripForIPad()

                StageLookPreview(cue: appModel.selectedCue)
                    .clipShape(RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius)
                            .stroke(LumaStageDesign.hairline, lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 640)
    }

    private var lightingControlsColumn: some View {
        ScrollView {
            VStack(spacing: 16) {
                IPadMicroControlPanel(usesInternalScroll: false)
                FloatingAIConversationBox()
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .frame(width: 430)
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(appModel.selectedProject?.name ?? "LumaStage iPad")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(LumaStageDesign.textPrimary)

                Text(appModel.selectedProject?.venueDescription ?? "iPad stage and lighting control interface")
                    .font(.subheadline)
                    .foregroundStyle(LumaStageDesign.textSecondary)
            }

            Spacer()

            Picker("Workspace", selection: $workspaceMode) {
                ForEach(IPadWorkspaceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 290)

            Button {
                appModel.closeProject()
            } label: {
                Label("Projects", systemImage: "folder")
            }
            .lumaGlassButton()
            .controlSize(.regular)

            LumaStatusChip(
                title: workspaceMode == .stageBuilder ? "Stage Layout" : "Current Cue Only",
                tint: workspaceMode == .stageBuilder ? LumaStageDesign.coolBlue : LumaStageDesign.warmAmber
            )
        }
        .lumaPanel(padding: 18, tint: LumaStageDesign.nightBlack.opacity(0.18))
    }
}

private enum IPadWorkspaceMode: String, CaseIterable, Identifiable {
    case stageBuilder
    case lighting

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stageBuilder:
            return "Stage"
        case .lighting:
            return "Lighting"
        }
    }

    var systemImage: String {
        switch self {
        case .stageBuilder:
            return "shippingbox"
        case .lighting:
            return "lightbulb"
        }
    }
}

private struct StageStatusStripForIPad: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 10) {
            LumaStatusChip(title: "Standard Night", tint: LumaStageDesign.softGreen)
            LumaStatusChip(title: appModel.selectedCue?.localizedDisplayName ?? "No Cue Selected", tint: LumaStageDesign.warmAmber)
            LumaStatusChip(title: appModel.backgroundWashColor, tint: backgroundWashTint)

            Spacer()

            LumaMetricRow(
                title: "Front Light",
                value: "\(Int(round(appModel.frontLightDimmer * 100)))%",
                tint: LumaStageDesign.warmAmber
            )
            .frame(width: 150)
        }
        .lumaPanel(padding: 12, tint: LumaStageDesign.nightBlack.opacity(0.18))
    }

    private var backgroundWashTint: Color {
        let rgb = RGBComponents(hex: appModel.backgroundWashColor) ?? .white
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview {
    IPadCompanionView()
        .environment(AppModel())
}
