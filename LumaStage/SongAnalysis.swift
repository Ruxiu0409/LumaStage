import Foundation

// MARK: - Song analysis mirror (SPEC 05 P1, owner A2 — Foundation-only, smoke-tested)
//
// A platform-agnostic mirror of what the on-device WWDC26 `MusicUnderstanding` framework returns,
// expressed in seconds (`Double`) rather than `CMTime` so it has no AVFoundation/QuartzCore dependency
// and the smoke tests can pin it without a simulator. The platform `MusicUnderstandingService`
// (owner B1) is the only place that touches the real framework: it converts `SessionResult` into one
// of these. Everything downstream (ShowPlan, MusicShowBuilder) consumes this pure value type, so the
// deterministic "analysis → show" backbone runs even when the framework is unavailable (built-in demo
// song ships a cached JSON of this exact shape).

/// The musical role of a song section, mapped from the framework's structure labels (unknown → `.unknown`).
enum SectionKind: String, Codable {
    case intro
    case verse
    case chorus
    case bridge
    case breakdown
    case drop
    case outro
    case unknown
}

/// Whether the section's key reads as major (bright) or minor (dark); `.unknown` when undetermined.
enum MusicKeyMode: String, Codable {
    case major
    case minor
    case unknown
}

/// One detected section of the song, in seconds, with per-section averaged feel (pace/loudness/key/instruments).
struct SongSection: Codable, Equatable {
    var start: Double            // seconds
    var end: Double              // seconds
    var kind: SectionKind
    var pace: Double             // 0..1 (perceived tempo/energy feel, averaged within the section)
    var loudness: Double         // 0..1 (normalized, averaged within the section)
    var keyMode: MusicKeyMode
    var dominantInstruments: [String]   // e.g. ["drums","vocals"] (may be empty)

    var duration: Double { max(0, end - start) }
}

/// The whole-song analysis: the timeline (beats/bars), tempo, and the ordered, non-overlapping sections.
/// The conversion layer guarantees `sections` is sorted by `start` and non-overlapping.
struct SongAnalysis: Codable, Equatable {
    var title: String
    var duration: Double             // seconds
    var bpm: Double?                 // from beatsPerMinute (may be nil)
    var beatTimes: [Double]          // seconds of each beat
    var barTimes: [Double]           // seconds of each bar
    var sections: [SongSection]      // sorted by start, non-overlapping

    /// Derives a `MusicBeatClock` from the tempo + first-beat offset. When `bpm` is present and valid it
    /// is used directly with the first beat as the downbeat offset; otherwise, with ≥2 beats, the bpm is
    /// estimated from the median inter-beat interval; with no usable tempo it returns nil (the caller
    /// falls back to self-accumulated time).
    func makeBeatClock() -> MusicBeatClock? {
        let startOffset = beatTimes.first ?? 0

        if let bpm, bpm > 0 {
            return MusicBeatClock(bpm: bpm, startOffset: startOffset)
        }

        guard beatTimes.count >= 2 else { return nil }

        // Estimate bpm from the median gap between consecutive beats (robust to a few mis-detections).
        var intervals: [Double] = []
        intervals.reserveCapacity(beatTimes.count - 1)
        for index in 1..<beatTimes.count {
            let gap = beatTimes[index] - beatTimes[index - 1]
            if gap > 0 { intervals.append(gap) }
        }
        guard !intervals.isEmpty else { return nil }

        intervals.sort()
        let median: Double
        let mid = intervals.count / 2
        if intervals.count % 2 == 0 {
            median = (intervals[mid - 1] + intervals[mid]) / 2
        } else {
            median = intervals[mid]
        }
        guard median > 0 else { return nil }

        return MusicBeatClock(bpm: 60.0 / median, startOffset: startOffset)
    }
}

/// Injectable analysis boundary (same pattern as `LightingLookGenerating`). Foundation-only protocol;
/// the platform implementation (real framework + the cached demo song) lives in `MusicUnderstandingService`.
protocol SongAnalyzing {
    func analyze(url: URL, title: String) async throws -> SongAnalysis
}

/// Errors the analysis boundary can surface.
enum SongAnalysisError: Error {
    case unsupported
    case empty
    case analysisFailed(String)
}
