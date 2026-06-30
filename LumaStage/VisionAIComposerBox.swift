import SwiftUI
import UniformTypeIdentifiers

#if os(visionOS)
struct VisionAIComposerBox: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingPatchSheet = false
    @State private var isShowingMusicSheet = false

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
        .sheet(isPresented: $isShowingMusicSheet) {
            MusicShowSheet()
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

            Button("音樂", systemImage: "music.note") {
                isShowingMusicSheet = true
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .lumaGazeTarget()
            .tint(appModel.isMusicShowActive ? LumaStageDesign.coolBlue : nil)
            .help("匯入歌曲，裝置端離線分析後自動生成整場節拍同步演出；也能鎖定設備檔")
            .accessibilityLabel(appModel.isMusicShowActive ? "音樂演出（已載入）" : "音樂演出")
            .accessibilityValue(musicAccessibilityValue)

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

            if appModel.isMusicShowActive {
                LumaStatusChip(title: musicStatusChipTitle, tint: LumaStageDesign.coolBlue)
                    .accessibilityLabel("音樂演出狀態")
                    .accessibilityValue(musicAccessibilityValue)
            }

            Spacer()
        }
    }

    /// Compact "playing/stopped · BPM" label for the live music chip in `statusRow`.
    private var musicStatusChipTitle: String {
        let state = appModel.isMusicPlaying ? "播放中" : "已停止"
        if let bpm = appModel.musicBPM {
            return "\(state) · BPM \(Int(bpm.rounded()))"
        }
        return state
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

    /// VoiceOver value for the topBar music button — the live show status read aloud after the label.
    private var musicAccessibilityValue: String {
        guard appModel.isMusicShowActive else { return "尚未載入歌曲" }
        var parts: [String] = []
        if let title = appModel.currentSongTitle { parts.append(title) }
        if let bpm = appModel.musicBPM { parts.append("每分鐘 \(Int(bpm.rounded())) 拍") }
        parts.append(appModel.isMusicPlaying ? "播放中" : "已停止")
        return parts.joined(separator: "，")
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

// MARK: - Music show sheet

/// The music surface reached from the topBar "音樂" button. Import an audio file (or use the bundled
/// demo song), then — once the on-device analysis has produced a show — see the song / BPM and a
/// play / stop toggle. Also the entry point to the rig-constraint ("設備檔") editor. All generation +
/// analysis happens in `AppModel`; this view only drives that contract.
private struct MusicShowSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isImportingSong = false
    @State private var isShowingRigEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceSection
                    if appModel.isMusicShowActive {
                        statusSection
                    }
                    rigSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("音樂演出")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .lumaGazeTarget()
                }
            }
            .sheet(isPresented: $isShowingRigEditor) {
                RigConstraintEditorView()
                    .environment(appModel)
            }
            .fileImporter(
                isPresented: $isImportingSong,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await appModel.importSong(url: url) }
                case .failure:
                    break
                }
            }
        }
        .frame(minWidth: 460, minHeight: 480)
    }

    // MARK: Pick a song

    private var sourceSection: some View {
        LumaControlSection(
            title: "選擇歌曲",
            subtitle: "裝置端離線分析節拍與段落，自動生成整場節拍同步演出。",
            systemImage: "waveform"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button("匯入音檔", systemImage: "square.and.arrow.down") {
                    isImportingSong = true
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(LumaStageDesign.coolBlue)
                .lumaGazeTarget()
                .frame(maxWidth: .infinity)
                .help("從檔案選擇一首歌（裝置端分析，不會上傳）")
                .accessibilityLabel("匯入音檔")
                .accessibilityHint("選擇一首歌曲，裝置端離線分析後自動生成演出")

                Button("使用內建示範曲", systemImage: "music.note.list") {
                    Task { await appModel.useBuiltInDemoSong() }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .lumaGazeTarget()
                .frame(maxWidth: .infinity)
                .help("使用預先分析好的內建示範曲 — 現場零失敗")
                .accessibilityLabel("使用內建示範曲")
                .accessibilityHint("載入預先分析的示範曲，現場零失敗")
            }
        }
    }

    // MARK: Live show status

    private var statusSection: some View {
        LumaControlSection(
            title: "演出狀態",
            subtitle: "依段落自動走場，視覺鎖定真實節拍。",
            systemImage: "music.note"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LumaMetricRow(
                    title: "歌曲",
                    value: appModel.currentSongTitle ?? "—",
                    tint: LumaStageDesign.textPrimary
                )
                LumaMetricRow(
                    title: "節拍",
                    value: appModel.musicBPM.map { "BPM \(Int($0.rounded()))" } ?? "—",
                    tint: LumaStageDesign.coolBlue
                )

                Button(
                    appModel.isMusicPlaying ? "停止演出" : "播放演出",
                    systemImage: appModel.isMusicPlaying ? "stop.fill" : "play.fill"
                ) {
                    if appModel.isMusicPlaying {
                        appModel.stopMusicShow()
                    } else {
                        appModel.playMusicShow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(appModel.isMusicPlaying ? LumaStageDesign.warmAmber : LumaStageDesign.softGreen)
                .lumaGazeTarget()
                .frame(maxWidth: .infinity)
                .help(appModel.isMusicPlaying ? "停止播放，停止節拍同步走場" : "開始播放，cue 隨段落自動走")
                .accessibilityLabel(appModel.isMusicPlaying ? "停止演出" : "播放演出")
                .accessibilityValue(appModel.isMusicPlaying ? "播放中" : "已停止")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    // MARK: Rig constraint entry

    private var rigSection: some View {
        LumaControlSection(
            title: "設備檔",
            subtitle: "鎖定你實際擁有的燈具數量與型號，生成一律遵守。",
            systemImage: "lightbulb.2"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(rigSummary)
                    .font(.callout)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("編輯設備檔", systemImage: "slider.horizontal.3") {
                    isShowingRigEditor = true
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .lumaGazeTarget()
                .frame(maxWidth: .infinity)
                .help("設定燈具數量與允許的型號 — 套用後對音樂演出與 AI 生成都生效")
                .accessibilityLabel("編輯設備檔")
                .accessibilityValue(rigSummary)
            }
        }
    }

    private var rigSummary: String {
        let constraint = appModel.rigConstraint
        if constraint.isUnconstrained {
            return "目前不限數量、不限型號。"
        }
        let countText = constraint.fixtureCount.map { "\($0) 盞燈" } ?? "不限數量"
        let modelText: String
        if constraint.allowedModels.isEmpty {
            modelText = "不限型號"
        } else {
            modelText = constraint.allowedModels
                .map { RigConstraintEditorView.displayName(for: $0) }
                .joined(separator: "、")
        }
        return "\(countText)；\(modelText)。"
    }
}

// MARK: - Rig constraint editor

/// Edits a local copy of `appModel.rigConstraint` — a fixture-count limit (or 不限) plus an allowed
/// model whitelist (empty = 不限型號) — and commits it via `appModel.setRigConstraint(_:)`. Selection
/// uses a checkmark (non-color) indicator for accessibility.
private struct RigConstraintEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var limitCount: Bool = false
    @State private var fixtureCount: Int = 8
    @State private var allowedModels: Set<LightingFixtureVisualModel> = []

    private static let countRange = 1...12

    /// Chinese display name for a fixture model, reusing the catalog's `displayName` (falls back to the
    /// raw case name for any model not in the catalog).
    static func displayName(for model: LightingFixtureVisualModel) -> String {
        LightingFixtureCatalog.item(for: model)?.displayName ?? model.rawValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    countSection
                    modelSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("設備檔")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .lumaGazeTarget()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用") {
                        appModel.setRigConstraint(
                            RigConstraint(
                                fixtureCount: limitCount ? fixtureCount : nil,
                                allowedModels: Array(allowedModels)
                            )
                        )
                        dismiss()
                    }
                    .lumaGazeTarget()
                    .accessibilityHint("套用設備檔，對音樂演出與 AI 生成都生效")
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear(perform: loadFromModel)
    }

    private func loadFromModel() {
        let constraint = appModel.rigConstraint
        if let count = constraint.fixtureCount {
            limitCount = true
            fixtureCount = min(max(count, Self.countRange.lowerBound), Self.countRange.upperBound)
        } else {
            limitCount = false
        }
        allowedModels = Set(constraint.allowedModels)
    }

    // MARK: Fixture count

    private var countSection: some View {
        LumaControlSection(
            title: "燈具數量",
            subtitle: "生成的燈數不會超過此上限；關閉表示不限。",
            systemImage: "number"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $limitCount.animation(nil)) {
                    Text("限制數量")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LumaStageDesign.textPrimary)
                }
                .toggleStyle(.switch)
                .lumaGazeTarget()
                .accessibilityHint("開啟以設定燈具數量上限，關閉表示不限")

                if limitCount {
                    Stepper(value: $fixtureCount, in: Self.countRange) {
                        HStack {
                            Text("數量")
                                .font(.callout)
                                .foregroundStyle(LumaStageDesign.textSecondary)
                            Spacer()
                            Text("\(fixtureCount) 盞")
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(LumaStageDesign.textPrimary)
                        }
                    }
                    .lumaGazeTarget()
                    .accessibilityLabel("燈具數量")
                    .accessibilityValue("\(fixtureCount) 盞")
                } else {
                    Text("目前不限數量")
                        .font(.callout)
                        .foregroundStyle(LumaStageDesign.textSecondary)
                }
            }
        }
    }

    // MARK: Allowed models

    private var modelSection: some View {
        LumaControlSection(
            title: "允許的型號",
            subtitle: allowedModels.isEmpty ? "未選擇任何型號 — 代表不限型號。" : "生成只會用到勾選的型號。",
            systemImage: "lightbulb.2"
        ) {
            VStack(spacing: 0) {
                ForEach(LightingFixtureVisualModel.allCases, id: \.self) { model in
                    modelRow(model)
                    if model != LightingFixtureVisualModel.allCases.last {
                        Divider().overlay(LumaStageDesign.hairline)
                    }
                }
            }
        }
    }

    private func modelRow(_ model: LightingFixtureVisualModel) -> some View {
        let isSelected = allowedModels.contains(model)
        return Button {
            if isSelected {
                allowedModels.remove(model)
            } else {
                allowedModels.insert(model)
            }
        } label: {
            HStack(spacing: 12) {
                // Non-color selection indicator: a filled checkmark when chosen, an empty circle
                // otherwise — legible under Differentiate Without Color, not only via tint.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LumaStageDesign.coolBlue : LumaStageDesign.textSecondary)
                Text(Self.displayName(for: model))
                    .font(.callout.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(LumaStageDesign.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .lumaGazeTarget()
        .accessibilityLabel(Self.displayName(for: model))
        .accessibilityValue(isSelected ? "已選擇" : "未選擇")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("點兩下\(isSelected ? "取消選擇" : "選擇")此型號")
    }
}

#Preview {
    VisionAIComposerBox()
        .environment(AppModel())
}
#endif
