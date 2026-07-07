import Foundation
import Observation

// MARK: - Cue-list auto-playback timer (SPEC 16 — GO 升為「播放」)
//
// The non-music counterpart of `MusicSyncEngine`: a main-thread, single-shot rescheduling timer that fires
// each cue's follow/hold time, then asks its owner to advance to the next cue. Deliberately audio-free and
// decoupled from `AppModel` — it talks through the `onFollow` closure, so the decidable pieces (which cue is
// next, how long each holds) live in the pure `CuePlayback` enum + `AppModel`, and this class only owns the
// clock. NOT in the smoke set (it's behavioral timer plumbing); `CuePlayback` carries the tested logic.
//
// Flow: `start(initialHold:)` schedules the first follow after the *current* cue's hold. When it fires,
// `onFollow` advances the selection and returns the NOW-current cue's hold to schedule the next follow — or
// `nil` to stop (the owner reached the last cue). A one-shot timer per step (not a repeating tick) so each
// cue's hold is honoured exactly and a mid-show manual GO can simply `start` again to reset the countdown.

@MainActor
@Observable
final class CuePlaybackEngine {
    /// Whether auto-playback is running (a follow is scheduled). Observed by the UI via `AppModel`.
    private(set) var isPlaying: Bool = false

    /// Fired when a cue's hold elapses. The handler advances to the next cue and returns that cue's hold
    /// (seconds) to schedule the following advance, or `nil` to stop (no successor — playback finished).
    @ObservationIgnored var onFollow: (() -> Double?)?

    @ObservationIgnored private var timer: Timer?

    init() {}

    /// Begin auto-playback: hold the current cue for `initialHold` seconds, then follow. Tears down any
    /// in-flight timer first, so calling `start` again mid-show (e.g. after a manual GO) resets the countdown.
    func start(initialHold: Double) {
        stop()
        isPlaying = true
        schedule(after: initialHold)
    }

    /// Stop auto-playback: cancel the pending follow and clear `isPlaying`. Idempotent — safe to call from
    /// reset paths and when a music show takes over.
    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }

    private func schedule(after seconds: Double) {
        // Floor the interval so a (already-clamped) tiny hold still yields to the run loop rather than firing
        // re-entrantly. Scheduled in `.common` modes so follows keep firing during UI tracking.
        let interval = max(0.05, seconds)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        guard isPlaying else { return }
        if let nextHold = onFollow?() {
            schedule(after: nextHold)
        } else {
            stop()
        }
    }
}
