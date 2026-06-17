import SwiftUI

#if os(visionOS)
struct VisionAIComposerBox: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private let composerCornerRadius: CGFloat = 28

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 14) {
            promptComposer(text: $appModel.typedPrompt)
            contextRow
        }
        .padding(16)
        .background(
            LumaStageDesign.nightBlack.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 30)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 30, y: 18)
        .foregroundStyle(LumaStageDesign.textPrimary)
    }

    private func promptComposer(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            TextField("Ask anything", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(LumaStageDesign.textPrimary)
                .lineLimit(2...4)
                .submitLabel(.send)
                .onSubmit(sendPrompt)

            HStack(spacing: 14) {
                iconButton(systemImage: "folder", tint: LumaStageDesign.textSecondary) {
                    returnToProjects()
                }
                .help("Back to Projects")

                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text(stateLabel)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(stateTint)

                if let projectName = appModel.selectedProject?.name {
                    LumaStatusChip(title: projectName, tint: LumaStageDesign.coolBlue)
                }
                LumaStatusChip(title: appModel.selectedCue?.localizedDisplayName ?? "Opening", tint: LumaStageDesign.warmAmber)
                LumaStatusChip(title: "Standard Night", tint: LumaStageDesign.softGreen)

                Spacer()

                ToggleImmersiveSpaceButton(displayStyle: .icon)
                    .buttonStyle(.plain)
                    .help("Open or close the immersive stage")

                micButton
                sendButton
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(
            LumaStageDesign.graphiteElevated.opacity(0.92),
            in: RoundedRectangle(cornerRadius: composerCornerRadius)
        )
    }

    private var contextRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.callout.weight(.semibold))

            Text(contextText)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            if let lastError = appModel.lastError {
                Text(lastError)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text(appModel.generationStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(LumaStageDesign.textSecondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private var micButton: some View {
        Button {
            Task {
                await appModel.toggleSpeechInput()
            }
        } label: {
            Image(systemName: appModel.speechTranscriber.isRecording ? "stop.fill" : "mic")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(appModel.speechTranscriber.isRecording ? .red : LumaStageDesign.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(!appModel.isModelAvailable)
        .help(appModel.speechTranscriber.isRecording ? "Stop Listening" : "Start Voice Input")
    }

    private var sendButton: some View {
        Button(action: sendPrompt) {
            Image(systemName: "arrow.up")
                .font(.title3.weight(.bold))
                .frame(width: 48, height: 48)
                .foregroundStyle(LumaStageDesign.nightBlack)
                .background(Color.white.opacity(canSendPrompt ? 0.84 : 0.32), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSendPrompt)
        .help("Generate Lighting")
    }

    private func iconButton(
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private var contextText: String {
        if appModel.speechTranscriber.isRecording {
            return appModel.displayedTranscript
        }

        if !appModel.aiUnderstoodCommand.isEmpty,
           appModel.aiUnderstoodCommand != "Waiting for voice or text input" {
            return appModel.aiUnderstoodCommand
        }

        if let projectName = appModel.selectedProject?.name {
            return "Working in \(projectName)"
        }

        return "Working in a LumaStage project"
    }

    private var canSendPrompt: Bool {
        appModel.isModelAvailable
            && !appModel.typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var stateTint: Color {
        switch appModel.conversationState {
        case .idle:
            return Color(red: 0.54, green: 0.76, blue: 1.0)
        case .listening, .transcribing:
            return LumaStageDesign.warmAmber
        case .interpreting, .applying:
            return LumaStageDesign.coolBlue
        case .explaining:
            return LumaStageDesign.softGreen
        case .error:
            return .red
        }
    }

    private var stateLabel: String {
        switch appModel.conversationState {
        case .idle:
            return "Auto Design"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .interpreting:
            return "AI Interpreting"
        case .applying:
            return "Applying Lighting"
        case .explaining:
            return "Generated"
        case .error:
            return "Retry Needed"
        }
    }

    private func sendPrompt() {
        Task {
            await appModel.generateFromTypedPrompt()
        }
    }

    private func returnToProjects() {
        Task { @MainActor in
            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }

            appModel.closeProject()
        }
    }
}

#Preview {
    VisionAIComposerBox()
        .environment(AppModel())
}
#endif
