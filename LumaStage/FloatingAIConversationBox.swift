import SwiftUI

struct FloatingAIConversationBox: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: LumaStageDesign.sectionSpacing) {
            iPadHeader
            textPromptSection(text: $appModel.typedPrompt)
            understoodSection
            explanationSection

            if let lastError = appModel.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lumaPanel()
    }

    private var iPadHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Text Lighting Command", systemImage: "keyboard")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(LumaStageDesign.textPrimary)

                Text("iPad uses typed fine-tuning. Voice control stays on Apple Vision Pro.")
                    .font(.caption)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            LumaStatusChip(title: appModel.conversationState.displayName, tint: stateTint)
        }
    }

    private func textPromptSection(text: Binding<String>) -> some View {
        LumaControlSection(
            title: "Text Input",
            subtitle: "Describe the lighting adjustment for the current cue",
            systemImage: "text.cursor"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Example: Make the front light warmer and change the background to deep blue", text: text, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(12)
                    .frame(minHeight: 92, alignment: .topLeading)
                    .background(LumaStageDesign.nightBlack.opacity(0.58), in: RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: LumaStageDesign.cornerRadius)
                            .stroke(LumaStageDesign.hairline, lineWidth: 1)
                    }
                    .submitLabel(.send)
                    .onSubmit(sendPrompt)

                HStack(spacing: 10) {
                    Text(appModel.generationStatus)
                        .font(.caption2)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .lineLimit(2)

                    Spacer()

                    Button(action: sendPrompt) {
                        Label("Send", systemImage: "arrow.up")
                            .frame(minWidth: 92)
                    }
                    .lumaGlassButton(prominent: true)
                    .disabled(!canSendPrompt)
                }
            }
        }
    }

    private var understoodSection: some View {
        LumaControlSection(title: "AI Understanding", systemImage: "sparkles") {
            Text(appModel.aiUnderstoodCommand)
                .font(.callout.weight(.medium))
                .foregroundStyle(LumaStageDesign.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanationSection: some View {
        LumaControlSection(
            title: appModel.lastExplanation.term,
            subtitle: appModel.lastExplanation.actionSummary,
            systemImage: "lightbulb"
        ) {
            Text(appModel.lastExplanation.plainText)
                .font(.callout)
                .foregroundStyle(LumaStageDesign.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stateTint: Color {
        switch appModel.conversationState {
        case .idle:
            return LumaStageDesign.textSecondary
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

    private var canSendPrompt: Bool {
        appModel.isModelAvailable
            && !appModel.typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPrompt() {
        Task {
            await appModel.generateFromTypedPrompt()
        }
    }
}

#Preview {
    FloatingAIConversationBox()
        .environment(AppModel())
}
