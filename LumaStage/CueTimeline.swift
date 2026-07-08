import Foundation

// MARK: - Playback timeline geometry (SPEC 20 WI-10 — 播放頁時間軌)
//
// The decidable core behind the playback page's progress track: lay a row of blocks (one per cue) along a
// time axis and map an elapsed time / a tapped fraction back to a cue index. Pure and Foundation-only so it
// stays smoke-tested; `PlaybackTimelineView` is the thin visionOS consumer.
//
// Two block sources:
//   • a general cue-list look — each block's width = `CuePlayback.holdDuration(for:)` (the SPEC 16 clamped
//     hold) + the cue's `transition.duration`, `start` accumulated;
//   • a music show — each block takes its `SongSection.start` / `duration` directly, aligned to the cues by
//     index (`cue_music_<i>`), so the cursor (driven by `MusicSyncEngine.currentTime`) reads true song time.

/// One cue's segment on the timeline. `id == cueId` so `ForEach` is stable and taps map back to a cue.
struct CueTimelineBlock: Equatable, Identifiable {
    let id: String            // = cueId
    let index: Int            // 0-based, matches the cues order
    let cueId: String
    let displayName: String
    let start: Double         // seconds from the timeline origin
    let duration: Double
    var end: Double { start + duration }
}

enum CueTimeline {
    /// General look: block width = clamped hold + transition duration, `start` accumulated left→right.
    static func blocks(for cues: [LightingCue]) -> [CueTimelineBlock] {
        var result: [CueTimelineBlock] = []
        result.reserveCapacity(cues.count)
        var cursor = 0.0
        for (index, cue) in cues.enumerated() {
            let duration = CuePlayback.holdDuration(for: cue) + cue.transition.duration
            result.append(CueTimelineBlock(
                id: cue.id, index: index, cueId: cue.id,
                displayName: cue.localizedDisplayName, start: cursor, duration: duration
            ))
            cursor += duration
        }
        return result
    }

    /// Music show: block start/duration come straight from the analyzed `SongSection`s; `cueIds` /
    /// `displayNames` align to the sections by index (falling back to a synthesized `cue_music_<i>` id and
    /// the id as the label if the caller passes short arrays).
    static func musicBlocks(sections: [SongSection], cueIds: [String], displayNames: [String]) -> [CueTimelineBlock] {
        var result: [CueTimelineBlock] = []
        result.reserveCapacity(sections.count)
        for (index, section) in sections.enumerated() {
            let cueId = index < cueIds.count ? cueIds[index] : "cue_music_\(index)"
            let displayName = index < displayNames.count ? displayNames[index] : cueId
            result.append(CueTimelineBlock(
                id: cueId, index: index, cueId: cueId,
                displayName: displayName, start: section.start, duration: section.duration
            ))
        }
        return result
    }

    /// Total timeline length = the last block's end; 0 for an empty timeline.
    static func totalDuration(of blocks: [CueTimelineBlock]) -> Double {
        blocks.last?.end ?? 0
    }

    /// Progress cursor position as a 0...1 fraction of the timeline; clamped, and 0 when `total <= 0`.
    static func cursorFraction(elapsed: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(elapsed / total, 0), 1)
    }

    /// The cue index at an elapsed time: the block whose `[start, end)` contains `elapsed`. Before the first
    /// block → the first index; past the last block (or in a gap between sections) → the last block whose
    /// `start <= elapsed`. `nil` only for an empty timeline.
    static func currentIndex(atElapsed elapsed: Double, blocks: [CueTimelineBlock]) -> Int? {
        guard let first = blocks.first else { return nil }
        if elapsed < first.start { return first.index }
        var candidate = first.index
        for block in blocks {
            if elapsed >= block.start, elapsed < block.end {
                return block.index
            }
            if elapsed >= block.start {
                candidate = block.index
            }
        }
        return candidate
    }

    /// The cue index at a tapped 0...1 position along the track. `nil` only for an empty timeline; fraction 0
    /// → first, 1 → last.
    static func index(atFraction fraction: Double, blocks: [CueTimelineBlock]) -> Int? {
        let total = totalDuration(of: blocks)
        guard total > 0 else { return blocks.first?.index }
        let clamped = min(max(fraction, 0), 1)
        return currentIndex(atElapsed: clamped * total, blocks: blocks)
    }
}
