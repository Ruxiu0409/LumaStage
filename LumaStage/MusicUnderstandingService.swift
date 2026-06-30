import Foundation

// MARK: - Music understanding (SPEC 05 P2, owner B1 — platform layer, NOT in the smoke set)
//
// The platform implementation of the Foundation-only `SongAnalyzing` boundary. This is the ONLY file that
// touches the on-device WWDC26 `MusicUnderstanding` framework: it runs a `MusicUnderstandingSession` over an
// audio URL and converts the framework's `SessionResult` into the platform-agnostic `SongAnalysis` mirror that
// everything downstream (ShowPlan, MusicShowBuilder, MusicSyncEngine) consumes. Per the spec, if the framework's
// result property / enum member names differ slightly from the documented surface, ONLY this conversion layer is
// touched — the Foundation models stay fixed.
//
// TOLERANCE IS MANDATORY: every dimension (key/pace/loudness/instruments/structure) reads defensively and falls
// back to a neutral default on any failure. We only throw `SongAnalysisError.analysisFailed` when the session
// itself can't be created or `analyze()` throws — never because a single dimension is missing.
//
// This file imports MusicUnderstanding / AVFoundation / CoreMedia, so it is platform-only (`#if os(visionOS) ||
// os(iOS)`) and is deliberately kept OUT of the headless smoke-test compile set.

#if os(visionOS) || os(iOS)

import AVFoundation
import CoreMedia

#if canImport(MusicUnderstanding)
import MusicUnderstanding

/// On-device song analysis backed by Apple's WWDC26 `MusicUnderstanding` framework. Fully offline, private,
/// no network. Produces a `SongAnalysis` from any audio URL.
struct MusicUnderstandingService: SongAnalyzing {
    func analyze(url: URL, title: String) async throws -> SongAnalysis {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )

        // Only a failure to CREATE the session or to RUN analyze() aborts. Everything past this point is
        // tolerant: a missing dimension degrades to a neutral default rather than throwing.
        let session: MusicUnderstandingSession
        do {
            session = try await MusicUnderstandingSession(asset: asset)
        } catch {
            throw SongAnalysisError.analysisFailed("無法建立音樂分析工作階段：\(Self.describe(error))")
        }

        let results: MusicUnderstandingSession.SessionResult
        do {
            results = try await session.analyze()
        } catch {
            throw SongAnalysisError.analysisFailed("音樂分析失敗：\(Self.describe(error))")
        }

        return Self.makeAnalysis(from: results, url: url, title: title)
    }

    /// Localised-ish description of a framework error, mapping the known `MusicUnderstandingError` cases.
    private static func describe(_ error: Error) -> String {
        if let mu = error as? MusicUnderstandingError {
            switch mu {
            case .sessionInProgress: return "已有分析進行中"
            case .emptyAnalysisSet:  return "分析項目為空"
            case .invalidAsset:      return "音訊檔案無效"
            case .internalError:     return "音樂分析框架內部錯誤"
            @unknown default:        return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: Conversion (SessionResult → SongAnalysis)

    /// Pure-ish conversion (the only platform dependency is CMTime → seconds). Tolerant throughout: every
    /// dimension is optional on `SessionResult`, so each is guarded and degrades to a neutral default.
    static func makeAnalysis(
        from results: MusicUnderstandingSession.SessionResult,
        url: URL,
        title: String
    ) -> SongAnalysis {
        // --- Beats / bars / bpm (from RhythmResult) -------------------------------------------------------
        let beatTimes = (results.rhythm?.beats ?? []).map(\.seconds).filter { $0.isFinite }
        let barTimes = (results.rhythm?.bars ?? []).map(\.seconds).filter { $0.isFinite }

        var bpm: Double? = nil
        if let rawBPM = results.rhythm?.beatsPerMinute, rawBPM.isFinite, rawBPM > 0 {
            bpm = Double(rawBPM)
        }

        // --- Overall duration -----------------------------------------------------------------------------
        let duration = Self.deriveDuration(results: results, beatTimes: beatTimes, barTimes: barTimes)

        // --- Sections (from StructureResult.sections: [CMTimeRange], no labels) ---------------------------
        let rawRanges = results.structure?.sections ?? []
        var sections: [SongSection] = rawRanges.compactMap { range in
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite, end > start else { return nil }
            // `StructureResult.sections` carries no label, so `kind` stays `.unknown` for real songs.
            return Self.makeSection(start: start, end: end, kind: .unknown, results: results)
        }

        // Sort by start, then clamp overlaps so the result is sorted + non-overlapping (the documented
        // invariant of `SongAnalysis.sections`).
        sections.sort { $0.start < $1.start }
        sections = Self.normalize(sections)

        // If the framework gave us no usable structure, synthesize one full-duration `.unknown` section so the
        // downstream ShowPlan / MusicShowBuilder still have something to build a (neutral) show from.
        if sections.isEmpty {
            let end = duration > 0 ? duration : max(beatTimes.last ?? 0, 1)
            sections = [Self.makeSection(start: 0, end: end, kind: .unknown, results: results)]
        }

        return SongAnalysis(
            title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
            duration: duration,
            bpm: bpm,
            beatTimes: beatTimes,
            barTimes: barTimes,
            sections: sections
        )
    }

    /// Build one `SongSection` from a section time range, deriving every per-section feel from the real
    /// typed members (`pace`/`loudness`/`key`/`instrumentActivity`). Each dimension is independently optional.
    private static func makeSection(
        start: Double,
        end: Double,
        kind: SectionKind,
        results: MusicUnderstandingSession.SessionResult
    ) -> SongSection {
        let span = start...max(start, end)
        let mid = (start + end) / 2

        return SongSection(
            start: start,
            end: end,
            kind: kind,
            pace: Self.averagePace(in: span, results: results) ?? 0.5,
            loudness: Self.averageLoudness(in: span, results: results) ?? 0.5,
            keyMode: Self.keyMode(at: mid, results: results),
            dominantInstruments: Self.dominantInstruments(in: span, results: results)
        )
    }

    // MARK: Section-kind label mapping

    /// Bucket a free-form section label string into a `SectionKind`. `StructureResult.sections` is `[CMTimeRange]`
    /// with no label, so this is unused for real songs today — but it's kept as the canonical label→kind mapping
    /// should a future SDK attach labels, and matches the demo JSON's labelled sections. Lowercased substring
    /// match so vendor labels like "Chorus 1" / "PRE-CHORUS" / "verse_2" all land sensibly. Unknown → `.unknown`.
    static func sectionKind(fromLabel rawLabel: String) -> SectionKind {
        let label = rawLabel.lowercased()
        // Order matters: check the more specific labels first (e.g. "breakdown" before "break").
        if label.contains("intro") { return .intro }
        if label.contains("outro") || label.contains("ending") || label.contains("coda") { return .outro }
        if label.contains("breakdown") { return .breakdown }
        if label.contains("drop") { return .drop }
        if label.contains("bridge") { return .bridge }
        if label.contains("chorus") || label.contains("hook") || label.contains("refrain") { return .chorus }
        if label.contains("verse") { return .verse }
        return .unknown
    }

    // MARK: Pace (0..1, section average)

    /// Average of the `PaceResult` ranged values that overlap the span, normalized into 0..1. `PaceResult.ranges`
    /// is `[RangedValue<Double>]` with `.value` already ~0...1 and `.range` a `CMTimeRange`. Weight each value by
    /// its seconds of overlap with the span; if nothing overlaps, fall back to the plain mean. Returns nil if no
    /// pace dimension or no usable ranges.
    private static func averagePace(
        in span: ClosedRange<Double>,
        results: MusicUnderstandingSession.SessionResult
    ) -> Double? {
        guard let ranges = results.pace?.ranges, !ranges.isEmpty else { return nil }

        var weighted = 0.0
        var totalWeight = 0.0
        var meanAccumulator = 0.0
        var meanCount = 0.0
        for ranged in ranges {
            guard let secondsRange = Self.secondsRange(ranged.range) else { continue }
            meanAccumulator += ranged.value
            meanCount += 1
            let overlap = Self.overlap(span, secondsRange)
            guard overlap > 0 else { continue }
            weighted += ranged.value * overlap
            totalWeight += overlap
        }
        guard meanCount > 0 else { return nil }
        // No overlapping ranged values → fall back to the plain mean of all samples (still tolerant).
        if totalWeight <= 0 {
            return Self.clamp01(meanAccumulator / meanCount)
        }
        return Self.clamp01(weighted / totalWeight)
    }

    // MARK: Loudness (0..1, section average; LUFS → 0..1)

    /// Section-average loudness, normalized 0..1. Prefers the time-varying `shortTerm`, then `momentary`, then
    /// the single `integrated` LUFS scalar — all real typed members of `LoudnessResult` (`[TimedValue<Float>]` /
    /// `TimedValue<Float>`, `.time.seconds`, `.value` a Float LUFS). Each LUFS value maps through `loudnessToUnit`
    /// (≈ -30…0 LUFS → 0…1, clamped). Returns nil if there's no loudness dimension.
    private static func averageLoudness(
        in span: ClosedRange<Double>,
        results: MusicUnderstandingSession.SessionResult
    ) -> Double? {
        guard let loudness = results.loudness else { return nil }

        // Time-varying loudness (shortTerm preferred, then momentary). Each is a [TimedValue<Float>].
        for samples in [loudness.shortTerm, loudness.momentary] where !samples.isEmpty {
            var sum = 0.0
            var count = 0.0
            for sample in samples {
                let time = sample.time.seconds
                guard time.isFinite, span.contains(time) else { continue }
                sum += Self.loudnessToUnit(Double(sample.value))
                count += 1
            }
            if count > 0 { return Self.clamp01(sum / count) }
            // No sample inside the span → plain mean of all samples (still tolerant).
            let mean = samples.map { Self.loudnessToUnit(Double($0.value)) }.reduce(0, +) / Double(samples.count)
            return Self.clamp01(mean)
        }

        // Fall back to the single integrated LUFS scalar.
        return Self.loudnessToUnit(Double(loudness.integrated.value))
    }

    /// Map a LUFS loudness reading to 0..1. Roughly: -30 LUFS (quiet) → 0, 0 LUFS (very loud) → 1, clamped.
    /// LUFS is negative for typical program material; this gives a perceptually sane spread for stage energy.
    static func loudnessToUnit(_ lufs: Double) -> Double {
        guard lufs.isFinite else { return 0.5 }
        let floorLUFS = -30.0
        let ceilLUFS = 0.0
        return clamp01((lufs - floorLUFS) / (ceilLUFS - floorLUFS))
    }

    // MARK: Key mode (at a time point)

    /// `KeyResult` value at the given time → `.major` / `.minor` / `.unknown`. `KeyResult.ranges` is
    /// `[RangedValue<KeySignature>]`; we find the entry whose `.range` contains `time` (else the nearest by
    /// range midpoint), then map `.value.mode` (`.major`/`.minor`) to `MusicKeyMode`. None → `.unknown`.
    private static func keyMode(
        at time: Double,
        results: MusicUnderstandingSession.SessionResult
    ) -> MusicKeyMode {
        guard let ranges = results.key?.ranges, !ranges.isEmpty else { return .unknown }

        // Prefer the entry whose range contains `time`; else the nearest by range midpoint.
        let containing = ranges.first { ranged in
            guard let r = Self.secondsRange(ranged.range) else { return false }
            return r.contains(time)
        }
        let chosen = containing ?? ranges.min(by: { lhs, rhs in
            Self.midpointDistance(lhs.range, to: time) < Self.midpointDistance(rhs.range, to: time)
        })
        guard let signature = chosen?.value else { return .unknown }
        switch signature.mode {
        case .major: return .major
        case .minor: return .minor
        @unknown default: return .unknown
        }
    }

    /// Absolute distance from a `CMTimeRange`'s midpoint (in seconds) to a target time; `.infinity` if degenerate.
    private static func midpointDistance(_ range: CMTimeRange, to time: Double) -> Double {
        guard let r = Self.secondsRange(range) else { return .infinity }
        let mid = (r.lowerBound + r.upperBound) / 2
        return abs(mid - time)
    }

    // MARK: Dominant instruments (top-N by activity in the span)

    /// Top-N instrument names active within the span, from `InstrumentActivityResult.activity`
    /// (`[Instrument: [TimedValue<Float>]]`). Per section, average each instrument's `.value` over `.time`
    /// within the span, take the highest-scoring few, and emit `instrument.rawValue` strings. Empty when there's
    /// no instrument-activity dimension or no samples land in the span.
    private static func dominantInstruments(
        in span: ClosedRange<Double>,
        results: MusicUnderstandingSession.SessionResult,
        topN: Int = 3
    ) -> [String] {
        guard let activity = results.instrumentActivity?.activity else { return [] }

        var scores: [(name: String, score: Double)] = []
        for (instrument, samples) in activity {
            let name = instrument.rawValue
            guard !name.isEmpty else { continue }
            var sum = 0.0
            var count = 0.0
            for sample in samples {
                let time = sample.time.seconds
                guard time.isFinite, span.contains(time) else { continue }
                sum += Double(sample.value)
                count += 1
            }
            if count > 0 { scores.append((name, sum / count)) }
        }

        return scores
            .sorted { $0.score > $1.score }
            .prefix(topN)
            .map(\.name)
    }

    // MARK: Small math helpers

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// `CMTimeRange` → `ClosedRange<Double>` in seconds. nil if degenerate/non-finite.
    private static func secondsRange(_ range: CMTimeRange) -> ClosedRange<Double>? {
        let lo = range.start.seconds
        let hi = range.end.seconds
        guard lo.isFinite, hi.isFinite, hi >= lo else { return nil }
        return lo...hi
    }

    /// Overlap (in seconds) between two closed ranges; 0 if disjoint. A zero-width range counts as a tiny
    /// epsilon if it sits inside the span, so point samples still register.
    private static func overlap(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> Double {
        let lo = max(a.lowerBound, b.lowerBound)
        let hi = min(a.upperBound, b.upperBound)
        if hi > lo { return hi - lo }
        if hi == lo, a.contains(lo) { return 0.0001 }  // point sample inside the span
        return 0
    }

    /// Best-effort overall duration: prefer the last beat/bar time, else the last section end, else 0.
    private static func deriveDuration(
        results: MusicUnderstandingSession.SessionResult,
        beatTimes: [Double],
        barTimes: [Double]
    ) -> Double {
        let lastBeat = beatTimes.last ?? 0
        let lastBar = barTimes.last ?? 0
        let lastSection = (results.structure?.sections ?? [])
            .map { $0.end.seconds }
            .filter { $0.isFinite }
            .max() ?? 0
        return max(lastBeat, max(lastBar, lastSection))
    }

    /// Ensure a start-sorted section array is non-overlapping by clamping each section's start to the previous
    /// section's end (dropping any section that collapses to non-positive duration after clamping).
    private static func normalize(_ sections: [SongSection]) -> [SongSection] {
        var out: [SongSection] = []
        var previousEnd = -Double.greatestFiniteMagnitude
        for var section in sections {
            if section.start < previousEnd { section.start = previousEnd }
            guard section.end > section.start else { continue }
            previousEnd = section.end
            out.append(section)
        }
        return out
    }
}

#else

// MARK: - Framework absent

/// When the `MusicUnderstanding` SDK isn't present, live analysis is unsupported. The built-in demo song
/// (`CachedSongAnalyzer`) still works because it decodes a bundled JSON and never touches the framework — so
/// the demo path stays zero-fail even here.
struct MusicUnderstandingService: SongAnalyzing {
    func analyze(url: URL, title: String) async throws -> SongAnalysis {
        throw SongAnalysisError.unsupported
    }
}

#endif  // canImport(MusicUnderstanding)

// MARK: - Built-in demo song (ZERO-FAIL path — does NOT require the framework to run live)
//
// The demo-safe analyzer: it returns a hand-authored `SongAnalysis` decoded from the bundled
// `demo-song-analysis.json` resource (a realistic ~150s, 128 BPM song). If that resource is missing for any
// reason, it falls back to an inline-constructed equivalent so it NEVER throws. This is what "使用內建示範曲"
// uses on stage, so it deliberately has no dependency on `MusicUnderstanding` being able to run.

struct CachedSongAnalyzer: SongAnalyzing {
    /// Bundle to load the JSON resource from (injectable for tests/previews).
    var bundle: Bundle = .main

    func analyze(url: URL, title: String) async throws -> SongAnalysis {
        // `url`/`title` are accepted to satisfy `SongAnalyzing`, but the demo song's analysis is fixed.
        if var analysis = Self.loadBundled(from: bundle) {
            if !title.isEmpty { analysis.title = title }
            return analysis
        }
        // Resource missing → inline fallback so the demo never fails.
        var analysis = Self.inlineDemo()
        if !title.isEmpty { analysis.title = title }
        return analysis
    }

    /// Decode `demo-song-analysis.json` from the bundle. Returns nil on any failure (missing/corrupt).
    static func loadBundled(from bundle: Bundle) -> SongAnalysis? {
        guard let url = bundle.url(forResource: "demo-song-analysis", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let analysis = try? JSONDecoder().decode(SongAnalysis.self, from: data) else {
            return nil
        }
        return analysis
    }

    /// An inline-constructed equivalent of the bundled demo (≈150s, 128 BPM, intro→verse→chorus→bridge→
    /// chorus→outro). Beats/bars are generated to match 128 BPM so `makeBeatClock()` and the beat grid stay
    /// consistent with the JSON.
    static func inlineDemo() -> SongAnalysis {
        let bpm = 128.0
        let duration = 150.0
        let beatPeriod = 60.0 / bpm  // 0.46875

        var beatTimes: [Double] = []
        var t = 0.0
        while t < duration {
            beatTimes.append(t)
            t += beatPeriod
        }
        // One bar every 4 beats (4/4).
        let barTimes = stride(from: 0, to: beatTimes.count, by: 4).map { beatTimes[$0] }

        let sections: [SongSection] = [
            SongSection(start: 0,   end: 15,  kind: .intro,  pace: 0.30, loudness: 0.35, keyMode: .minor, dominantInstruments: ["pad", "piano"]),
            SongSection(start: 15,  end: 45,  kind: .verse,  pace: 0.50, loudness: 0.55, keyMode: .minor, dominantInstruments: ["drums", "bass", "vocals"]),
            SongSection(start: 45,  end: 75,  kind: .chorus, pace: 0.85, loudness: 0.85, keyMode: .major, dominantInstruments: ["drums", "bass", "synth", "vocals"]),
            SongSection(start: 75,  end: 95,  kind: .bridge, pace: 0.55, loudness: 0.60, keyMode: .minor, dominantInstruments: ["guitar", "drums", "vocals"]),
            SongSection(start: 95,  end: 130, kind: .chorus, pace: 0.90, loudness: 0.90, keyMode: .major, dominantInstruments: ["drums", "bass", "synth", "vocals"]),
            SongSection(start: 130, end: 150, kind: .outro,  pace: 0.35, loudness: 0.40, keyMode: .major, dominantInstruments: ["pad", "piano"]),
        ]

        return SongAnalysis(
            title: "示範曲（128 BPM）",
            duration: duration,
            bpm: bpm,
            beatTimes: beatTimes,
            barTimes: barTimes,
            sections: sections
        )
    }
}

// MARK: - Preview analyzer

/// A tiny fixed analysis for SwiftUI previews — two short sections, valid bpm/beats so `makeBeatClock()` and
/// `ShowPlan.make` produce something renderable without any framework or bundle dependency.
struct PreviewSongAnalyzer: SongAnalyzing {
    func analyze(url: URL, title: String) async throws -> SongAnalysis {
        let bpm = 120.0
        let beatPeriod = 60.0 / bpm  // 0.5
        let duration = 20.0
        var beatTimes: [Double] = []
        var t = 0.0
        while t < duration {
            beatTimes.append(t)
            t += beatPeriod
        }
        let barTimes = stride(from: 0, to: beatTimes.count, by: 4).map { beatTimes[$0] }

        return SongAnalysis(
            title: title.isEmpty ? "預覽曲" : title,
            duration: duration,
            bpm: bpm,
            beatTimes: beatTimes,
            barTimes: barTimes,
            sections: [
                SongSection(start: 0,  end: 10, kind: .verse,  pace: 0.45, loudness: 0.50, keyMode: .minor, dominantInstruments: ["drums", "bass"]),
                SongSection(start: 10, end: 20, kind: .chorus, pace: 0.85, loudness: 0.85, keyMode: .major, dominantInstruments: ["drums", "synth", "vocals"]),
            ]
        )
    }
}

#endif  // os(visionOS) || os(iOS)
