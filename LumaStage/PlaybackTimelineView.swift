import SwiftUI

#if os(visionOS)
/// SPEC 20 WI-10 — the playback page's progress timeline. Lays out one block per cue (width ∝ its
/// duration), highlights the current cue, animates a progress cursor, and lets the user tap a block to jump
/// to that cue. A thin consumer of the Foundation-only `CueTimeline` (block geometry) — transport reuses
/// `AppModel.togglePlayback` / `isShowRunning`, and tapping a block routes through `selectCueFromTimeline`
/// (which also reschedules the follow countdown when auto-playing).
struct PlaybackTimelineView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wall-clock stamp captured when the selected cue last changed / playback (re)started. Used to
    /// interpolate the progress cursor for a NON-music cue-list show; a music show reads the continuous
    /// `MusicSyncEngine.currentTime` (`appModel.musicElapsedSeconds`) instead.
    @State private var cueStartWallClock = Date()

    private static let cursorTick = 1.0 / 30.0

    var body: some View {
        let blocks = currentBlocks
        let total = CueTimeline.totalDuration(of: blocks)

        VStack(alignment: .leading, spacing: 8) {
            header
            // Reduce Motion: no continuous cursor animation — the cursor snaps to the current cue's block
            // start on each cue change (discrete). Otherwise a paused-when-idle 30 Hz schedule advances it.
            if reduceMotion {
                track(blocks: blocks, total: total,
                      fraction: cursorFraction(blocks: blocks, total: total, now: Date(), animate: false))
            } else {
                TimelineView(.animation(minimumInterval: Self.cursorTick, paused: !appModel.isShowRunning)) { context in
                    track(blocks: blocks, total: total,
                          fraction: cursorFraction(blocks: blocks, total: total, now: context.date, animate: true))
                }
            }
        }
        .onChange(of: appModel.selectedCueId) { _, _ in cueStartWallClock = Date() }
        .onChange(of: appModel.isShowRunning) { _, running in if running { cueStartWallClock = Date() } }
    }

    // MARK: - Transport header

    private var header: some View {
        HStack(spacing: 10) {
            Label("播放時間軌", systemImage: "rectangle.split.3x1")
                .font(.callout.weight(.semibold))
                .foregroundStyle(LumaStageDesign.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(appModel.isShowRunning ? "停止" : "播放",
                   systemImage: appModel.isShowRunning ? "stop.fill" : "play.circle.fill") {
                appModel.togglePlayback()
            }
            .font(.headline.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .lumaGazeTarget()
            .tint(appModel.isShowRunning ? .red : LumaStageDesign.softGreen)
            .disabled(!appModel.isMusicShowActive && appModel.cues.count <= 1)
            .help(appModel.isShowRunning ? "停止播放，停在目前場景" : "播放 — 自動連續跑完整個場景清單")

            Button("GO", systemImage: "forward.fill") {
                appModel.goToNextCue()
            }
            .font(.headline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .lumaGazeTarget()
            .tint(LumaStageDesign.softGreen)
            .disabled(appModel.cues.count <= 1)
            .help("GO — 手動切換到下一個場景")
        }
    }

    // MARK: - Track

    private func track(blocks: [CueTimelineBlock], total: Double, fraction: Double) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let safeTotal = max(total, 0.0001)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(blocks) { block in
                        blockSegment(block)
                            // Explicit proportional width (no inter-segment spacing) so block boundaries land
                            // exactly at cumulative fractions and the cursor at `fraction × width` lines up.
                            .frame(width: max(8, width * CGFloat(block.duration / safeTotal)))
                    }
                }

                // Progress cursor — only while a show is running or a music show is loaded (otherwise the
                // playhead would sit misleadingly at 0 on a paused, un-started timeline).
                if appModel.isShowRunning || appModel.isMusicShowActive {
                    Capsule()
                        .fill(LumaStageDesign.warmAmber)
                        .frame(width: 3)
                        .offset(x: min(max(CGFloat(fraction) * width - 1.5, 0), width - 3))
                        .shadow(color: LumaStageDesign.warmAmber.opacity(0.7), radius: 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 56)
    }

    private func blockSegment(_ block: CueTimelineBlock) -> some View {
        let isSelected = block.cueId == appModel.selectedCueId
        return Button {
            appModel.selectCueFromTimeline(id: block.cueId)
        } label: {
            Text(block.displayName)
                .font(.caption.weight(isSelected ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? LumaStageDesign.coolBlue.opacity(0.55) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? LumaStageDesign.coolBlue : LumaStageDesign.hairline,
                                      lineWidth: isSelected ? 2 : 1)
                )
                .foregroundStyle(LumaStageDesign.textPrimary)
                .padding(1)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("場景 \(block.index + 1)：\(block.displayName)")
        .accessibilityHint(isSelected ? "目前場景" : "跳到這個場景")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Blocks + cursor math (thin wrappers over `CueTimeline`)

    private var currentBlocks: [CueTimelineBlock] {
        let cues = appModel.cues
        if appModel.isMusicShowActive {
            let sections = appModel.musicShowSections
            if !sections.isEmpty {
                return CueTimeline.musicBlocks(
                    sections: sections,
                    cueIds: cues.map(\.id),
                    displayNames: cues.map(\.localizedDisplayName)
                )
            }
        }
        return CueTimeline.blocks(for: cues)
    }

    private func cursorFraction(blocks: [CueTimelineBlock], total: Double, now: Date, animate: Bool) -> Double {
        CueTimeline.cursorFraction(elapsed: elapsedSeconds(blocks: blocks, now: now, animate: animate), total: total)
    }

    private func elapsedSeconds(blocks: [CueTimelineBlock], now: Date, animate: Bool) -> Double {
        if appModel.isMusicShowActive {
            // Music: real song time (30 Hz). Reduce Motion snaps to the current section's start.
            return animate ? appModel.musicElapsedSeconds : (currentBlock(blocks)?.start ?? 0)
        }
        guard let block = currentBlock(blocks) else { return 0 }
        // General cue list: interpolate from the current block's start using the wall clock while running;
        // freeze at the block start when stopped or under Reduce Motion.
        if animate, appModel.isShowRunning {
            return block.start + max(0, now.timeIntervalSince(cueStartWallClock))
        }
        return block.start
    }

    private func currentBlock(_ blocks: [CueTimelineBlock]) -> CueTimelineBlock? {
        blocks.first(where: { $0.cueId == appModel.selectedCueId })
    }
}
#endif
