import SwiftUI

#if os(visionOS)
struct VisionAIComposerBox: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 18) {
            inputField(text: $appModel.typedPrompt)
            statusRow
            controlRow
            contextRow
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lumaFloatingPanel()
    }

    private func inputField(text: Binding<String>) -> some View {
        TextField("Ask anything", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .foregroundStyle(LumaStageDesign.textPrimary)
            .lineLimit(2...4)
            .submitLabel(.send)
            .onSubmit(sendPrompt)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .lumaNativeGlass(radius: 22)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: stateIcon)
                Text(stateLabel)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(stateTint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .lumaNativeGlass(tint: stateTint.opacity(0.18), radius: 14)

            if let projectName = appModel.selectedProject?.name {
                LumaStatusChip(title: projectName, tint: LumaStageDesign.coolBlue)
            }
            LumaStatusChip(title: appModel.selectedCue?.localizedDisplayName ?? "Opening", tint: LumaStageDesign.warmAmber)
            LumaStatusChip(title: "Standard Night", tint: LumaStageDesign.softGreen)

            Spacer()
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button("Back to Projects", systemImage: "folder", action: returnToProjects)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)

            Spacer()

            Button(spillTitle, systemImage: appModel.stageImmersionMode == .roomSpill ? "sun.max.fill" : "sun.max") {
                appModel.toggleStageImmersion()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(appModel.stageImmersionMode == .roomSpill ? LumaStageDesign.warmAmber : nil)

            ToggleImmersiveSpaceButton(displayStyle: .icon)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .help("Open or close the immersive stage")

            micButton

            sendButton
        }
    }

    private var micButton: some View {
        Button(
            appModel.speechTranscriber.isRecording ? "Stop Listening" : "Start Voice Input",
            systemImage: appModel.speechTranscriber.isRecording ? "stop.fill" : "mic"
        ) {
            Task { await appModel.toggleSpeechInput() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(appModel.speechTranscriber.isRecording ? .red : nil)
        .disabled(!appModel.isModelAvailable)
    }

    private var sendButton: some View {
        Button("Generate Lighting", systemImage: "arrow.up", action: sendPrompt)
            .labelStyle(.iconOnly)
            .font(.title3.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(!canSendPrompt)
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
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text(appModel.generationStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(LumaStageDesign.textSecondary)
        .padding(.horizontal, 4)
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

    private var spillTitle: String {
        appModel.stageImmersionMode == .roomSpill
            ? "Stop spilling light onto your room"
            : "Spill stage light onto your room"
    }

    private var stateTint: Color {
        switch appModel.conversationState {
        case .idle:
            return LumaStageDesign.coolBlue
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

    private var stateIcon: String {
        switch appModel.conversationState {
        case .idle:
            return "wand.and.stars"
        case .listening:
            return "waveform"
        case .transcribing:
            return "text.bubble"
        case .interpreting:
            return "brain"
        case .applying:
            return "lightbulb.max"
        case .explaining:
            return "checkmark.seal"
        case .error:
            return "exclamationmark.triangle"
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
