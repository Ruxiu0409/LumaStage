import SwiftUI

/// Minimal settings sheet for entering the OpenAI API key used by `OpenAILightingService`.
///
/// The key is written straight into the device Keychain via `OpenAIKeychain.store(_:)` (or cleared
/// via `OpenAIKeychain.delete()`); it never touches `UserDefaults` or the app binary. After any
/// change this view calls the injected `appModel.refreshModelAvailability()` so the AI composer's
/// availability gate re-reads the new state immediately.
///
/// Styled with the same `LumaStageDesign` tokens (`lumaFloatingPanel` / `lumaGazeTarget`) and ≥60pt
/// gaze targets as the rest of the launch surface, presented as a sheet from `ProjectSelectionView`.
struct OpenAISettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    /// The text the user is typing. Never pre-filled with the stored key (a `SecureField` masks it,
    /// and re-exposing a secret into editable state is unnecessary) — we only track whether one is set.
    @State private var draftKey: String = ""
    /// Mirrors `OpenAIKeychain.load() != nil`; refreshed on appear and after every store/delete.
    @State private var hasStoredKey: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LumaStageDesign.sectionSpacing) {
                    statusSection
                    entrySection
                    privacyNote
                }
                .padding(24)
            }
            .foregroundStyle(LumaStageDesign.textPrimary)
            .navigationTitle("OpenAI 設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .lumaGazeTarget()
                }
            }
        }
        .onAppear(perform: refreshStatus)
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LumaSectionHeader(
                title: "雲端燈光生成",
                subtitle: "設定 OpenAI API 金鑰後，AI 燈光生成會優先走雲端，連線失敗時自動退回裝置端。",
                systemImage: "cloud"
            )

            HStack(spacing: 8) {
                Image(systemName: hasStoredKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(hasStoredKey ? LumaStageDesign.softGreen : LumaStageDesign.warmAmber)

                Text(hasStoredKey ? "已設定 API 金鑰" : "尚未設定 API 金鑰")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(LumaStageDesign.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .lumaNativeGlass(
            tint: (hasStoredKey ? LumaStageDesign.softGreen : LumaStageDesign.warmAmber).opacity(0.12),
            radius: LumaStageDesign.surfaceRadius,
            fallbackOpacity: 0.34
        )
    }

    private var entrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LumaSectionHeader(title: "API 金鑰", systemImage: "key.fill")

            SecureField("貼上 OpenAI API 金鑰（sk-…）", text: $draftKey)
                .textContentType(.password)
                .submitLabel(.done)
                .onSubmit(saveKey)
                .frame(minHeight: LumaStageDesign.minGazeTarget)
                .padding(.horizontal, 14)
                .lumaNativeGlass(radius: LumaStageDesign.cornerRadius, fallbackOpacity: 0.3)

            HStack(spacing: 12) {
                Button("清除金鑰", systemImage: "trash") {
                    clearKey()
                }
                .font(.callout.weight(.semibold))
                .lumaGlassButton()
                .lumaGazeTarget()
                .tint(LumaStageDesign.magenta)
                .disabled(!hasStoredKey)

                Spacer()

                Button("儲存金鑰", systemImage: "checkmark") {
                    saveKey()
                }
                .font(.callout.weight(.semibold))
                .lumaGlassButton(prominent: true)
                .lumaGazeTarget()
                .tint(LumaStageDesign.coolBlue)
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .lumaNativeGlass(radius: LumaStageDesign.surfaceRadius, fallbackOpacity: 0.34)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.callout.weight(.semibold))
                .foregroundStyle(LumaStageDesign.coolBlue)

            VStack(alignment: .leading, spacing: 6) {
                Text("金鑰只存於本機 Keychain；demo 直連 OpenAI，正式版應改走自家 proxy。")
                    .font(.caption)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("「強制裝置端（隱私模式）」開關本次未實作，已延後。")
                    .font(.caption2)
                    .foregroundStyle(LumaStageDesign.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .lumaNativeGlass(radius: LumaStageDesign.cornerRadius, fallbackOpacity: 0.28)
    }

    // MARK: - Actions

    private func refreshStatus() {
        hasStoredKey = OpenAIKeychain.load() != nil
    }

    private func saveKey() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        OpenAIKeychain.store(trimmed)
        draftKey = ""
        refreshStatus()
        // Re-read availability so the AI composer's gate reflects the newly stored key.
        appModel.refreshModelAvailability()
    }

    private func clearKey() {
        OpenAIKeychain.delete()
        draftKey = ""
        refreshStatus()
        appModel.refreshModelAvailability()
    }
}

#Preview {
    OpenAISettingsView()
        .environment(AppModel())
}
