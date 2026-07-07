#if os(iOS)
import Foundation
import SwiftUI

/// **Group submaster fader bank** — the iPad's live-control surface, and the heart of the demo beat
/// 「把 iPad 遞給評委，三指推三組過副歌」(hand the judge the iPad, ride three groups through the chorus
/// with three fingers). A horizontal row of **vertical** group faders + a prominent GO footer.
///
/// One fader per `StandardFixtureGroup` (前光 / 背景洗 / 上舞台 / 動態 / 全部). Sending to a group with no
/// members in the live rig is a harmless host-side no-op, so the bank shows the full canonical set
/// regardless of the current look.
///
/// **Multi-touch is the key feature**: each `GroupSubmasterFader` is its own view carrying its own
/// `DragGesture`, so iPadOS delivers concurrent touches to several faders at once (multiple fingers
/// riding multiple submasters). They are deliberately *not* wrapped in one shared gesture — a single
/// gesture would serialise to one touch and break the three-finger ride.
struct PanelFaderBankView: View {
    let model: LumaPanelModel

    /// Which group (if any) is currently soloed. While a solo is active, that group rides to 1.0 and the
    /// others are held at 0.0; clearing the solo restores each fader's own `level`. Latching (tap to
    /// toggle) rather than momentary so the operator can solo with one hand and ride faders with the other.
    @State private var soloedGroupId: String?

    private let groups = StandardFixtureGroup.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(groups, id: \.id) { group in
                        GroupSubmasterFader(
                            model: model,
                            group: group,
                            soloedGroupId: $soloedGroupId
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }

            GoFooter(model: model)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.vertical.3")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("分組推桿")
                .font(.headline)
            Spacer()
            Text(model.isConnected ? "現場控制" : "未連線")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isConnected ? .green : .secondary)
        }
    }
}

// MARK: - One vertical submaster fader

/// A single group submaster: a custom vertical fader (track + draggable knob) with a live percentage, a
/// momentary **bump** button, and a latching **solo** toggle. Owns its own `@State var level` so the
/// fader is *optimistic* — its visual follows the finger immediately and does not wait for the host echo
/// (a console fader never lags its own throw).
private struct GroupSubmasterFader: View {
    let model: LumaPanelModel
    let group: StandardFixtureGroup
    @Binding var soloedGroupId: String?

    /// The fader's own committed level (0...1). Optimistic — drives the visual directly. When this group
    /// is soloed the throw shows full; when another group is soloed it shows 0; otherwise it shows `level`.
    ///
    /// Rests at **1.0 (full)**, NOT 0: the group master is a *proportional* dimmer folded as
    /// `cueIntensity × master` whose neutral is 1.0 (no attenuation), so an untouched fader at full matches
    /// the host's default (no master entry → 1.0) and the stage's actual lit cue. Starting at 0 would show
    /// every fader empty while the stage is fully lit, and snap the group dark on first touch.
    @State private var level: Double = 1

    private static let throwHeight: CGFloat = 220
    private let faderWidth: CGFloat = 64
    private let adjustStep = 0.05

    private var isSoloed: Bool { soloedGroupId == group.id }
    private var isSuppressedBySolo: Bool { soloedGroupId != nil && !isSoloed }

    /// What the throw should render: full while soloed, empty while another group solos, else `level`.
    private var displayedLevel: Double {
        if isSoloed { return 1 }
        if isSuppressedBySolo { return 0 }
        return level
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("\(Int((displayedLevel * 100).rounded()))%")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSuppressedBySolo ? .tertiary : .primary)

            faderTrack

            Text(group.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            bumpButton
            soloButton
        }
        .frame(width: faderWidth)
        // Fold the throw + readout into one adjustable VoiceOver element; the bump/solo buttons stay
        // separate (they have their own labels below).
        .accessibilityElement(children: .contain)
    }

    // MARK: Throw

    private var faderTrack: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let knob = faderWidth - 18
            let value = max(0, min(1, displayedLevel))
            let fill = value * height
            // Knob centre travels the throw between knob/2 (bottom) and height - knob/2 (top); the ZStack
            // is bottom-aligned, so move the knob up by `value × (height - knob)`.
            let knobLift = value * (height - knob)

            ZStack(alignment: .bottom) {
                // Unfilled track.
                Capsule()
                    .fill(Color(.tertiarySystemFill))

                // Filled portion (group accent so each fader reads distinctly without relying on colour
                // alone — the % readout + label carry the value non-visually).
                Capsule()
                    .fill(trackTint)
                    .frame(height: fill)

                // Knob.
                Circle()
                    .fill(Color(.systemBackground))
                    .overlay(Circle().strokeBorder(trackTint, lineWidth: 3))
                    .frame(width: knob, height: knob)
                    .shadow(radius: 2, y: 1)
                    .offset(y: -knobLift)
            }
            .contentShape(Rectangle())
            // Each fader carries its OWN DragGesture so iPadOS can deliver concurrent multi-touch — do
            // not hoist this into a shared parent gesture (that would serialise to a single finger).
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard model.isConnected, soloedGroupId == nil else { return }
                        // Top of the track = 1.0, bottom = 0.0.
                        let raw = 1 - (drag.location.y / height)
                        ride(to: raw)
                    }
            )
        }
        .frame(width: faderWidth, height: Self.throwHeight)
        .opacity(isSuppressedBySolo ? 0.45 : 1)
        .accessibilityLabel(group.displayName)
        .accessibilityValue("\(Int((displayedLevel * 100).rounded()))%")
        // Lets VoiceOver users ride the submaster with swipe-up/down in ~5% steps.
        .accessibilityAdjustableAction { direction in
            guard model.isConnected, soloedGroupId == nil else { return }
            switch direction {
            case .increment: ride(to: level + adjustStep)
            case .decrement: ride(to: level - adjustStep)
            @unknown default: break
            }
        }
    }

    private var trackTint: Color {
        switch group {
        case .front: return .orange
        case .backgroundWash: return .blue
        case .upstage: return .teal
        case .movers: return .purple
        case .all: return .pink
        }
    }

    /// Commit a new level (clamped 0...1) optimistically and push it to the host.
    private func ride(to newValue: Double) {
        let clamped = max(0, min(1, newValue))
        level = clamped
        model.send(.setGroupMaster(groupId: group.id, level: clamped))
    }

    // MARK: Bump

    /// Momentary flash: press → group to full, release → release back to following the cue. Uses a
    /// zero-distance `DragGesture` so press and release are distinct phases (a plain `Button` only fires
    /// on release, which can't drive a momentary bump). NOTE: bump feel (how snappy the on/off reads on
    /// stage) is **device-tuned** — re-verify the flash timing on a real Vision Pro link.
    private var bumpButton: some View {
        Text("閃")
            .font(.subheadline.weight(.bold))
            .frame(width: faderWidth - 6, height: 44)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.send(.bumpGroup(groupId: group.id, on: true)) }
                    .onEnded { _ in model.send(.bumpGroup(groupId: group.id, on: false)) }
            )
            .disabled(!model.isConnected)
            .accessibilityLabel("\(group.displayName)瞬亮")
            .accessibilityHint("按住打到全亮，放開恢復")
    }

    // MARK: Solo

    /// Latching solo: tap to send this group to 1.0 and every other group to 0.0; tap again to restore
    /// each fader's own level. SIMPLIFICATION: solo is coordinated through the shared `soloedGroupId`
    /// binding and each fader reacts in `onChange` — the soloed fader rides itself to 1.0 and the others
    /// ride to 0.0; on clear, everyone re-sends their stored `level`. Non-colour state cue: a filled
    /// `circle.fill` glyph + bold "SOLO", not tint alone.
    private var soloButton: some View {
        Button {
            soloedGroupId = isSoloed ? nil : group.id
        } label: {
            Label("SOLO", systemImage: isSoloed ? "circle.fill" : "circle")
                .font(.caption2.weight(isSoloed ? .heavy : .semibold))
                .labelStyle(.titleAndIcon)
                .frame(width: faderWidth - 6, height: 44)
        }
        .buttonStyle(.bordered)
        .tint(isSoloed ? .yellow : nil)
        .disabled(!model.isConnected)
        .accessibilityLabel("\(group.displayName)獨奏")
        .accessibilityValue(isSoloed ? "開啟" : "關閉")
        .accessibilityAddTraits(isSoloed ? [.isSelected] : [])
        // React to ANY group's solo state so every fader pushes the right master while a solo is active.
        .onChange(of: soloedGroupId) { _, newValue in
            guard model.isConnected else { return }
            if newValue == nil {
                // Solo cleared — restore this fader's own committed level on the host.
                model.send(.setGroupMaster(groupId: group.id, level: level))
            } else if newValue == group.id {
                model.send(.setGroupMaster(groupId: group.id, level: 1))
            } else {
                model.send(.setGroupMaster(groupId: group.id, level: 0))
            }
        }
    }
}

// MARK: - GO footer

/// The show-runner's GO key and the current/next cue label — mirrors the GO button styling in
/// `PanelLightingView`'s cue control (`.borderedProminent`, green, "GO" + play.fill).
private struct GoFooter: View {
    let model: LumaPanelModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(nextLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 播放/停止：自動連續跑完整個 cue list（SPEC 16）。與手動 GO 並存 —— 播放中仍可按 GO 手動跳場。
            Button {
                model.send(isPlaying ? .stopCueList : .playCueList)
            } label: {
                Label(isPlaying ? "停止" : "播放",
                      systemImage: isPlaying ? "stop.fill" : "play.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 80, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(isPlaying ? .red : .green)
            .disabled(!model.isConnected || cueCount <= 1)
            .accessibilityLabel(isPlaying ? "停止播放" : "播放，自動連續走場")
            .accessibilityHint(isPlaying ? "停止自動走場，停在目前場景" : "依每個場景的停留時間自動切到下一個場景")

            Button {
                model.send(.goToNextCue)
            } label: {
                Label("GO", systemImage: "forward.fill")
                    .font(.title3.weight(.bold))
                    .frame(minWidth: 80, minHeight: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.green)
            .disabled(!model.isConnected || cueCount <= 1)
            .accessibilityLabel("GO，手動前往下一個場景")
            .accessibilityHint("以過場時間切換到下一個場景")
        }
    }

    /// Whether the host is auto-running the cue list, so the transport button shows 停止 rather than 播放.
    private var isPlaying: Bool { model.host?.isPlayingCueList == true }

    private var cues: [LightingCue] { model.lighting?.cues ?? [] }
    private var cueCount: Int { cues.count }

    private var selectedIndex: Int {
        guard let look = model.lighting else { return 0 }
        return cues.firstIndex(where: { $0.id == look.selectedCueId }) ?? 0
    }

    /// e.g. "場景 1/2 · 開場" — current cue number, total, and its localized name.
    private var currentLabel: String {
        guard cueCount > 0 else { return "尚無場景" }
        let name = model.selectedCue?.localizedDisplayName ?? ""
        return "場景 \(selectedIndex + 1)/\(cueCount)" + (name.isEmpty ? "" : " · \(name)")
    }

    /// The cue GO will advance to (wraps), so the operator sees what's coming.
    private var nextLabel: String {
        guard cueCount > 1 else { return "只有一個場景" }
        let nextIndex = (selectedIndex + 1) % cueCount
        return "下一個：\(cues[nextIndex].localizedDisplayName)"
    }
}

#Preview {
    PanelFaderBankView(model: .mockPreview())
}
#endif
