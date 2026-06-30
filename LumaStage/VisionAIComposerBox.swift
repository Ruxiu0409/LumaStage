import SwiftUI

#if os(visionOS)
struct VisionAIComposerBox: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingPatchSheet = false

    var body: some View {
        @Bindable var appModel = appModel
        // Eagerly read the live transcript so `body` re-evaluates on every partial speech result.
        // The prompt field mirrors the transcript while dictating and the listening indicator
        // depends on it; a read only inside the field's binding closure wouldn't reliably form the
        // Observation dependency (the same footgun the RealityView update closure has).
        let _ = appModel.speechTranscriber.transcript
        let isRecording = appModel.speechTranscriber.isRecording
        // While dictating the field shows the live transcript read-only (the words land in
        // `typedPrompt` when recording stops); otherwise it's the editable typed prompt.
        let promptText: Binding<String> = isRecording
            ? Binding(get: { appModel.speechTranscriber.transcript }, set: { _ in })
            : $appModel.typedPrompt

        VStack(alignment: .leading, spacing: 18) {
            topBar
            inputField(text: promptText, isRecording: isRecording)
            feedbackPanel
            cueStrip
            statusRow
            controlRow
            debugPanel
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: appModel.isDebugPanelVisible)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: appModel.selectedCueId)
        .sheet(isPresented: $isShowingPatchSheet) {
            PatchSheetExportView()
                .environment(appModel)
        }
        .padding(24)
        // A fixed width gives this native window (`.windowResizability(.contentSize)`) a definite
        // content size — the rows use `Spacer()`/`maxWidth: .infinity` internally, which would be
        // ambiguous without an outer bound. Height stays content-driven, so the window resizes
        // smoothly as the prompt field grows. The system supplies the move bar; no custom handle.
        .frame(width: 640, alignment: .leading)
        .lumaFloatingPanel()
    }

    /// A top row above the prompt field. Hosts the entry point to the volumetric tabletop stage
    /// editor (a small editable stage model on the desk).
    private var topBar: some View {
        HStack(spacing: 12) {
            Button("編輯舞台", systemImage: "square.stack.3d.up", action: openStageEditor)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .help("在桌面模型上編輯舞台佈局")

            Button("配接表", systemImage: "tablecells") {
                isShowingPatchSheet = true
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .help("檢視並匯出 DMX 配接表 / 燈位表 — 交給真實場地的燈光技師")
            .accessibilityLabel("檢視 DMX 配接表")

            Spacer()

            Button(
                appModel.isVoiceNarrationEnabled ? "關閉語音朗讀" : "開啟語音朗讀",
                systemImage: appModel.isVoiceNarrationEnabled ? "speaker.wave.2.fill" : "speaker.slash"
            ) {
                appModel.toggleVoiceNarration()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .tint(appModel.isVoiceNarrationEnabled ? LumaStageDesign.softGreen : nil)
            .help("語音朗讀 — 開啟後每次生成、走場與單燈調整都會念出來（無障礙模式）")

            Button("燈光除錯", systemImage: appModel.isDebugPanelVisible ? "ladybug.fill" : "ladybug") {
                appModel.toggleDebugPanel()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .tint(appModel.isDebugPanelVisible ? LumaStageDesign.coolBlue : nil)
            .help("顯示燈光除錯面板 — 目前場景的燈具、顏色，以及哪些角色照亮舞台")
        }
    }

    /// The cue stack: a chip per cue (tap to select, long-press to delete), a "+" to add one, and the
    /// GO button that advances the show to the next cue — the same mental model as a lighting console's
    /// cue list + GO key, the leap from "one look" to "a designed show".
    private var cueStrip: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(appModel.cues.enumerated()), id: \.element.id) { index, cue in
                        cueChip(index: index, cue: cue)
                    }

                    Button("新增場景", systemImage: "plus") {
                        appModel.appendCue()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .lumaGazeTarget()
                    .help("新增場景（複製目前場景作為起點）")
                    .accessibilityLabel("新增場景")
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 8)

            Button("GO", systemImage: "play.fill") {
                appModel.goToNextCue()
            }
            .font(.headline.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .lumaGazeTarget()
            .tint(LumaStageDesign.softGreen)
            .disabled(appModel.cues.count <= 1)
            .help("GO — 以過場時間切換到下一個場景")
            .accessibilityLabel("GO，前往下一個場景")
        }
    }

    private func cueChip(index: Int, cue: LightingCue) -> some View {
        let isSelected = cue.id == appModel.selectedCueId
        return Button {
            appModel.selectCue(id: cue.id)
        } label: {
            HStack(spacing: 6) {
                // A non-color selection cue (checkmark + bold) so the live cue reads under low colour
                // vision / Differentiate Without Color, not only via the amber tint.
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                }
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .opacity(0.65)
                Text(cue.localizedDisplayName)
                    .font(.callout.weight(isSelected ? .bold : .semibold))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .lumaGazeTarget()
        .tint(isSelected ? LumaStageDesign.warmAmber : nil)
        .contextMenu {
            Button("刪除場景", systemImage: "trash", role: .destructive) {
                appModel.removeCue(id: cue.id)
            }
            .disabled(appModel.cues.count <= 1)
        }
        .accessibilityLabel("場景 \(index + 1)，\(cue.localizedDisplayName)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("點兩下切換到此場景")
        // A non-gesture path to the destructive delete (the context menu needs a long-press), so Switch
        // Control / Voice Control users can reach it too.
        .accessibilityAction(named: "刪除場景") {
            if appModel.cues.count > 1 { appModel.removeCue(id: cue.id) }
        }
    }

    private func inputField(text: Binding<String>, isRecording: Bool) -> some View {
        // Single-line (no `axis: .vertical`) so the keyboard's Send/Return key submits via
        // `.onSubmit` instead of inserting a newline — a vertical-axis TextField treats Return as a
        // newline and never fires `.onSubmit`. Guarded by `canSendPrompt` so Send on an empty prompt
        // (or while the model is unavailable) is a no-op, matching the Send button's disabled state.
        HStack(spacing: 12) {
            TextField(isRecording ? "聆聽中…" : "輸入任何需求", text: text)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(LumaStageDesign.textPrimary)
                .lineLimit(1)
                .submitLabel(.send)
                .onSubmit { if canSendPrompt { sendPrompt() } }
                // The field mirrors the live transcript read-only while dictating — block editing
                // without dimming the text (`.disabled` would fade the words you're watching appear).
                .allowsHitTesting(!isRecording)

            if isRecording {
                Image(systemName: "waveform")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
                    .accessibilityLabel("聆聽中")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .lumaNativeGlass(radius: 22)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isRecording)
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
            LumaStatusChip(title: appModel.selectedCue?.localizedDisplayName ?? "開場", tint: LumaStageDesign.warmAmber)
            LumaStatusChip(title: "標準夜景", tint: LumaStageDesign.softGreen)

            Spacer()
        }
    }

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button("返回專案", systemImage: "folder", action: returnToProjects)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .lumaGazeTarget()

            Spacer()

            Button(spillTitle, systemImage: appModel.stageImmersionMode == .roomSpill ? "sun.max.fill" : "sun.max") {
                appModel.toggleStageImmersion()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .tint(appModel.stageImmersionMode == .roomSpill ? LumaStageDesign.warmAmber : nil)

            ToggleImmersiveSpaceButton(displayStyle: .icon)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .help("開啟或關閉沉浸式舞台")

            micButton

            sendButton
        }
    }

    private var micButton: some View {
        Button(
            appModel.speechTranscriber.isRecording ? "停止聆聽" : "開始語音輸入",
            systemImage: appModel.speechTranscriber.isRecording ? "stop.fill" : "mic"
        ) {
            Task { await appModel.toggleSpeechInput() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .lumaGazeTarget()
        .tint(appModel.speechTranscriber.isRecording ? .red : nil)
        .disabled(!appModel.isModelAvailable)
    }

    private var sendButton: some View {
        Button("生成燈光", systemImage: "arrow.up", action: sendPrompt)
            .labelStyle(.iconOnly)
            .font(.title3.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .lumaGazeTarget()
            .disabled(!canSendPrompt)
    }

    /// The prominent, adaptive feedback area under the prompt field. In priority order it surfaces:
    /// an error, the live "listening" state, generation progress, and finally the AI's explanation of
    /// the look it produced — so a finished generation shows *what it did*, not just "Generated", and
    /// every earlier step is legible (multi-line, not the old truncated single-line caption).
    private var feedbackPanel: some View {
        let feedback = self.feedback
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: feedback.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(feedback.tint)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: feedback.animates && !reduceMotion)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.headline)
                    .foregroundStyle(LumaStageDesign.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = feedback.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The "why it was designed this way" teaching note (SPEC 03). A third labeled line in
                // the same glass container, styled like `detail` — no fixed font size, so it scales
                // with Dynamic Type and wraps freely.
                if let rationale = feedback.rationale, !rationale.isEmpty {
                    Text("設計理由：\(rationale)")
                        .font(.callout)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("設計理由，\(rationale)")
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .lumaNativeGlass(tint: feedback.tint.opacity(0.12), radius: LumaStageDesign.surfaceRadius)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: appModel.conversationState)
    }

    /// What `feedbackPanel` renders for the current state. View-level (it references SwiftUI colors),
    /// consistent with `stateLabel`/`stateIcon`/`stateTint`.
    private struct ComposerFeedback {
        var icon: String
        var tint: Color
        var title: String
        var detail: String?
        /// A short "why this look was designed this way" teaching note, surfaced as a third labeled
        /// line under the explanation in the `.explaining` state. Empty/absent for every other state.
        var rationale: String?
        var animates: Bool = false
    }

    private var feedback: ComposerFeedback {
        // Errors win: they're set alongside `.error`, so this also covers the `.error` state below.
        if let lastError = appModel.lastError {
            return ComposerFeedback(
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                title: "無法生成燈光",
                detail: lastError
            )
        }

        if appModel.speechTranscriber.isRecording {
            // The dictated words stream into the prompt field above; this panel stays a steady cue.
            return ComposerFeedback(
                icon: "waveform",
                tint: LumaStageDesign.warmAmber,
                title: "聆聽中…",
                detail: "說出你想要的燈光效果 — 完成後點擊停止按鈕。",
                animates: true
            )
        }

        switch appModel.conversationState {
        case .transcribing, .interpreting:
            return ComposerFeedback(
                icon: "brain",
                tint: LumaStageDesign.coolBlue,
                title: "正在設計你的燈光…",
                detail: appModel.aiUnderstoodCommand,
                animates: true
            )
        case .applying:
            return ComposerFeedback(
                icon: "lightbulb.max.fill",
                tint: LumaStageDesign.coolBlue,
                title: "正在套用燈光…",
                detail: appModel.aiUnderstoodCommand,
                animates: true
            )
        case .explaining:
            let explanation = appModel.lastExplanation
            return ComposerFeedback(
                icon: "checkmark.seal.fill",
                tint: LumaStageDesign.softGreen,
                title: explanation.actionSummary,
                detail: "\(explanation.term) — \(explanation.plainText)",
                rationale: explanation.rationale
            )
        case .idle, .listening, .error:
            if !appModel.isModelAvailable {
                return ComposerFeedback(
                    icon: "exclamationmark.circle",
                    tint: LumaStageDesign.warmAmber,
                    title: "Apple Intelligence 無法使用",
                    detail: appModel.generationStatus
                )
            }
            return ComposerFeedback(
                icon: "wand.and.stars",
                tint: LumaStageDesign.coolBlue,
                title: idleTitle,
                detail: idleDetail
            )
        }
    }

    private var idleTitle: String {
        if let projectName = appModel.selectedProject?.name {
            return "正在設計 \(projectName)"
        }
        return "描述你想要的燈光"
    }

    private var idleDetail: String? {
        if !appModel.aiUnderstoodCommand.isEmpty,
           appModel.aiUnderstoodCommand != "等待語音或文字輸入" {
            return appModel.aiUnderstoodCommand
        }
        return "輸入提示或點擊麥克風 — 例如「溫暖的開場，接著明亮聚焦的重點」。"
    }

    // MARK: - Relight debug panel (toggled from `topBar`)

    /// An in-app, toggleable panel showing how the current cue maps onto the immersive scene: a color
    /// swatch + hex/intensity/beam per fixture, and which roles actually light the stage. Replaces the
    /// throwaway os.Logger diagnostics so the state is legible in-headset without the Xcode console.
    @ViewBuilder
    private var debugPanel: some View {
        if appModel.isDebugPanelVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("燈光除錯", systemImage: "ladybug.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.textPrimary)
                    Spacer()
                    Text(appModel.stageImmersionMode == .roomSpill ? "房間溢光" : "完整舞台")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LumaStageDesign.textSecondary)
                }

                if let snapshot = appModel.relightDebugSnapshot {
                    Text("場景 · \(snapshot.cueName) · \(snapshot.renderedCount)/\(snapshot.rows.count) 已渲染")
                        .font(.caption)
                        .foregroundStyle(LumaStageDesign.textSecondary)

                    // A1 dynamic-effects readout: confirms (in-headset) whether the effect engine is engaged
                    // on this cue, and which fixtures are animating — the same gate the renderer uses.
                    Text(snapshot.isHighEnergy
                         ? "動態效果 · 高能量場景 — \(snapshot.animatedCount) 盞燈動態中"
                         : "動態效果 · 靜態場景（提高整體亮度即啟動掃動/閃爍）")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(snapshot.isHighEnergy ? LumaStageDesign.softGreen : LumaStageDesign.textSecondary)

                    ForEach(snapshot.rows) { row in
                        debugFixtureRow(row)
                    }
                } else {
                    Text("未選擇場景")
                        .font(.caption)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: appModel.isModelAvailable ? "checkmark.seal" : "exclamationmark.triangle")
                    Text(appModel.generationStatus)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(appModel.isModelAvailable ? LumaStageDesign.softGreen : LumaStageDesign.warmAmber)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .lumaNativeGlass(tint: LumaStageDesign.coolBlue.opacity(0.10), radius: LumaStageDesign.surfaceRadius)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func debugFixtureRow(_ row: RelightDebugSnapshot.Row) -> some View {
        let rgb = RGBComponents(hex: row.hex) ?? .white
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                .frame(width: 30, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LumaStageDesign.hairline, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.textPrimary)
                    if !row.isRendered {
                        Text("未渲染")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LumaStageDesign.warmAmber)
                    }
                }

                Text(debugDetail(row))
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(LumaStageDesign.textSecondary)
            }

            Spacer(minLength: 0)
        }
        // Dim non-rendered roles — they validate but never light the stage.
        .opacity(row.isRendered ? 1 : 0.5)
    }

    private func debugDetail(_ row: RelightDebugSnapshot.Row) -> String {
        var parts = [row.role.rawValue, row.hex, "\(row.intensityPercent)%", "\(row.beamDegrees)°"]
        if let gobo = row.gobo {
            parts.append("gobo \(gobo.rawValue)")
        }
        if row.effectKind != .none {
            parts.append("fx \(row.effectKind.rawValue)")
        }
        return parts.joined(separator: " · ")
    }

    private var canSendPrompt: Bool {
        // Disabled while dictating: the field then shows the live transcript, but `typedPrompt` still
        // holds the stale pre-dictation value — voice submits via the mic's stop button instead.
        appModel.isModelAvailable
            && !appModel.speechTranscriber.isRecording
            && !appModel.typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var spillTitle: String {
        appModel.stageImmersionMode == .roomSpill
            ? "停止將燈光投射到你的房間"
            : "將舞台燈光投射到你的房間"
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
            return "自動設計"
        case .listening:
            return "聆聽中"
        case .transcribing:
            return "轉錄中"
        case .interpreting:
            return "AI 解讀中"
        case .applying:
            return "套用燈光中"
        case .explaining:
            return "已生成"
        case .error:
            return "需要重試"
        }
    }

    private func sendPrompt() {
        Task {
            await appModel.generateFromTypedPrompt()
        }
    }

    private func openStageEditor() {
        // The tabletop editor is a dedicated passthrough immersive space that ARKit rests on the user's
        // real table. Only one immersive space can be open, so entering editing closes the 1:1 stage
        // space; `ContentView`'s reconciler then opens the editor space once the main window is back.
        guard !appModel.isEditingTabletopStage else { return }
        Task { @MainActor in
            appModel.enterTabletopEditing() // desiredImmersiveScene = .tabletopEditor
            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }
        }
    }

    private func returnToProjects() {
        Task { @MainActor in
            // Clear the project BEFORE closing the stage. Closing the immersive space reopens the
            // main window (`ImmersiveView.onDisappear`), and if a project were still selected that
            // freshly-created window would come up on the AI composer (ContentView's project-open
            // branch) and could stick there instead of re-rendering to the project list. Clearing
            // first means the reopened window shows `ProjectSelectionView` straight away — no race.
            // (`ImmersiveView.body` doesn't observe `selectedProjectId`, so this won't reflow the
            // stage geometry mid-close.)
            appModel.closeProject()

            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }
        }
    }
}

#Preview {
    VisionAIComposerBox()
        .environment(AppModel())
}
#endif
