import Foundation
#if os(visionOS) || os(iOS)
import AVFoundation
import QuartzCore
import os

// MARK: - Music playback + cross-thread clock (SPEC 05, owner B2 — platform layer, NOT in smoke set)
//
// Two cooperating types:
//
//   • `MusicSyncEngine` (@MainActor @Observable) — owns the `AVAudioPlayer`, drives a ~30 Hz main-thread
//     tick that publishes `currentTime` and fires section-boundary callbacks (owner C wires those to
//     `AppModel` cue advance). When a `MusicBeatClock` is supplied, `play()` anchors the shared clock
//     source so the render-thread `LightEffectSystem` can beat-lock; with no clock the audio still plays,
//     the source stays inactive, and the effect system free-runs.
//
//   • `MusicSyncClockSource` (plain `final class`, thread-safe, NOT actor-isolated) — the hand-off between
//     the main-thread engine (writer) and the render-thread effect system (reader). `snapshot()` is
//     `nonisolated` and lock-guarded so it's safe to call from `SceneUpdateContext.update` every frame
//     without an actor hop. Playback and visual lock-relay share one `CACurrentMediaTime()` time base, so
//     they don't drift apart (a constant offset is acceptable; long-song micro-drift is a known caveat per
//     the spec — re-anchor to the player's own timeline if it ever matters).

// MARK: MusicSyncClockSource — render-thread-readable clock

/// Cross-thread clock source: the engine writes (`setActive`/`clear` on the main actor), the
/// `LightEffectSystem` reads (`snapshot()` off the main actor, on the render thread). Thread safety comes
/// from a single `OSAllocatedUnfairLock` guarding the stored anchor; the critical section only reads/writes
/// the stored pair — `CACurrentMediaTime()` (itself thread-safe) is sampled outside the lock so we never
/// call out under it.
final class MusicSyncClockSource: @unchecked Sendable {
    static let shared = MusicSyncClockSource()

    /// The active anchor: the `CACurrentMediaTime()` value captured at the instant playback began, plus the
    /// beat grid to project. `nil` whenever playback is stopped or running without a clock.
    private struct Anchor {
        var startMediaTime: Double
        var clock: MusicBeatClock
    }

    private let lock = OSAllocatedUnfairLock<Anchor?>(initialState: nil)

    private init() {}

    /// Activate beat-locking from `startMediaTime` (a `CACurrentMediaTime()` value) using `clock`.
    func setActive(startMediaTime: Double, clock: MusicBeatClock) {
        lock.withLock { $0 = Anchor(startMediaTime: startMediaTime, clock: clock) }
    }

    /// Deactivate; subsequent `snapshot()` calls return `nil` until the next `setActive`.
    func clear() {
        lock.withLock { $0 = nil }
    }

    /// Render-thread read: current music time (`CACurrentMediaTime() - startMediaTime`) + the beat grid, or
    /// `nil` when inactive. `nonisolated` and safe off the main actor — the lock guards the stored anchor and
    /// the only work inside it is a copy of the small `Anchor` value; `now` is sampled outside the lock.
    func snapshot() -> (time: Double, clock: MusicBeatClock)? {
        let now = CACurrentMediaTime()
        guard let anchor = lock.withLock({ $0 }) else { return nil }
        return (now - anchor.startMediaTime, anchor.clock)
    }
}

// MARK: MusicSyncEngine — playback + main-thread tick

@MainActor
@Observable
final class MusicSyncEngine {
    /// Whether audio is currently playing.
    private(set) var isPlaying: Bool = false
    /// Playback position in seconds (same clock as `setSectionStarts`), published ~30 Hz while playing.
    private(set) var currentTime: Double = 0
    /// The beat grid handed to `load`; `nil` means free-running (no beat lock).
    private(set) var clock: MusicBeatClock?

    /// Fired once, in order, each time playback crosses a section start. The argument is the section index.
    /// Owner C wires this to `AppModel` cue advance.
    var onSectionBoundary: ((Int) -> Void)?

    // Backing playback + timing state. Not observed — they drive `currentTime`/`isPlaying`, which are.
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playerDelegate: PlayerDelegate?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var sectionStarts: [Double] = []
    /// Index of the next section boundary we haven't yet fired. Monotonic so each boundary fires exactly once.
    @ObservationIgnored private var nextBoundaryIndex: Int = 0

    /// ~30 Hz: smooth enough for cue-boundary timing, cheap on the main run loop.
    private static let tickInterval: TimeInterval = 1.0 / 30.0

    init() {}

    /// Prepare an audio file for playback. On any failure, lands in a safe non-playing state (no player, no
    /// clock active) rather than throwing. Stores `clock` for `play()` to anchor; pass `nil` to free-run.
    func load(url: URL, clock: MusicBeatClock?) {
        stop()  // tear down any prior playback + clear the shared source

        self.clock = clock
        currentTime = 0
        nextBoundaryIndex = 0

        // visionOS/iOS both have AVAudioSession; configure for playback so the spotlights-as-show audio is
        // heard even with the ringer/silent considerations. Best-effort: a session failure shouldn't block
        // loading the file.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            let delegate = PlayerDelegate { [weak self] in
                // The AVAudioPlayer delegate fires off the main actor, so hop onto it before touching the
                // @MainActor engine. (A Task hop, not assumeIsolated, because we're genuinely off-main here.)
                Task { @MainActor in self?.handlePlaybackFinished() }
            }
            newPlayer.delegate = delegate
            newPlayer.prepareToPlay()
            self.player = newPlayer
            self.playerDelegate = delegate
        } catch {
            // Safe non-playing state.
            player = nil
            playerDelegate = nil
            isPlaying = false
            self.clock = nil
        }
    }

    /// Start (or resume) playback. Anchors `MusicSyncClockSource.shared` to the current media time iff a
    /// clock was loaded, starts the publish tick, and marks `isPlaying`. No-op if there's no loaded player.
    func play() {
        guard let player else { return }

        // One shared time base for audio + visual lock: capture the anchor at the instant playback begins.
        let anchor = CACurrentMediaTime()
        let started = player.play()
        guard started else { return }

        // Beat-lock only when we have a grid; otherwise the source stays inactive and the effect system
        // free-runs on its own per-frame time.
        if let clock {
            MusicSyncClockSource.shared.setActive(startMediaTime: anchor, clock: clock)
        }

        isPlaying = true
        startTick()
    }

    /// Stop playback, clear the shared clock source, halt the tick, and reset `isPlaying`. Idempotent.
    func stop() {
        player?.stop()
        player?.currentTime = 0
        MusicSyncClockSource.shared.clear()
        isPlaying = false
        currentTime = 0
        nextBoundaryIndex = 0
        stopTick()
    }

    /// Section start times in seconds (ascending; same clock as `currentTime`). Resets the boundary cursor to
    /// the first section at or after the current position, so wiring starts mid-load behaves sanely.
    func setSectionStarts(_ starts: [Double]) {
        sectionStarts = starts.sorted()
        nextBoundaryIndex = sectionStarts.firstIndex(where: { $0 > currentTime }) ?? sectionStarts.count
    }

    // MARK: Tick

    private func startTick() {
        stopTick()
        // Scheduled on the current (main) run loop in the common modes so it keeps firing during UI tracking.
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTick() {
        tick?.invalidate()
        tick = nil
    }

    private func onTick() {
        guard let player, isPlaying else { return }
        currentTime = player.currentTime
        fireBoundariesUpTo(currentTime)
    }

    /// Fire every section boundary whose start time we've crossed, in order, each exactly once.
    private func fireBoundariesUpTo(_ time: Double) {
        while nextBoundaryIndex < sectionStarts.count, sectionStarts[nextBoundaryIndex] <= time {
            let index = nextBoundaryIndex
            nextBoundaryIndex += 1
            onSectionBoundary?(index)
        }
    }

    /// AVAudioPlayer reached the end: settle the final position, fire any remaining boundaries, then stop.
    private func handlePlaybackFinished() {
        if let player {
            currentTime = player.duration
            fireBoundariesUpTo(currentTime)
        }
        stop()
    }
}

// MARK: - AVAudioPlayer delegate shim

/// Bridges `AVAudioPlayerDelegate` (whose callbacks arrive off the main actor) to a main-actor closure. Kept
/// separate from the `@MainActor` engine so it can be `nonisolated` and conform without isolation conflicts.
private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

#endif
