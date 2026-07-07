import Foundation

// MARK: - Cue-list auto-playback logic (SPEC 16 — GO 升為「播放」)
//
// The decidable core behind "press 播放 and the cue list runs itself" — the non-music counterpart of the
// music show's `MusicSyncEngine` section-boundary advance. Everything here is pure and Foundation-only so it
// stays smoke-tested; `CuePlaybackEngine` (the timer) and the UI are thin consumers.
//
// A cue holds for its follow/hold time, then auto-follows to the next cue, running once to the last cue and
// stopping there (NO wrap — a real console cue list plays through once unless a loop is programmed). Manual
// GO still wraps; that asymmetry is deliberate (see `nextIndex(after:count:)`).

enum CuePlayback {
    /// Follow time used when a cue doesn't specify its own `holdDuration`. Comfortably longer than the
    /// default 2.5s cross-fade so each cue reads as settled before the next fires.
    static let defaultHoldSeconds: Double = 6

    /// Lower bound on a cue's hold. Floors a 0/near-0 (or negative) value so a malformed hold can't spin the
    /// scheduler into back-to-back advances.
    static let minHoldSeconds: Double = 1.5

    /// Upper bound on a cue's hold. Caps an absurd value so a bad number can't strand playback for hours.
    static let maxHoldSeconds: Double = 600

    /// Effective follow/hold time (seconds) a cue holds before auto-advancing. `holdDuration == nil` → the
    /// default; a non-finite value (NaN/±inf) → the default; anything else → clamped to `[min, max]`.
    static func holdDuration(for cue: LightingCue) -> Double {
        guard let hold = cue.holdDuration, hold.isFinite else {
            return defaultHoldSeconds
        }
        return min(max(hold, minHoldSeconds), maxHoldSeconds)
    }

    /// The next cue index when auto-playing — **does not wrap**. Returns `index + 1` while a successor
    /// exists, or `nil` at (or past) the last cue, which the engine reads as "playback finished, hold here".
    static func nextIndex(after index: Int, count: Int) -> Int? {
        let next = index + 1
        guard next >= 0, next < count else { return nil }
        return next
    }

    /// Whether a cue list can auto-play at all: it needs at least two cues to have somewhere to advance to.
    static func canAutoPlay(cueCount: Int) -> Bool {
        cueCount >= 2
    }
}
