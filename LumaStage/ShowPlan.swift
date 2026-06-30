import Foundation

// MARK: - Show plan (SPEC 05 P1, owner A2 — Foundation-only, smoke-tested)
//
// Turns a `SongAnalysis` (sections) into an ordered list of `CueBrief`s — the deterministic bridge
// between "what the song is doing" and "what cue plays". `MusicShowBuilder` consumes this to assemble a
// renderable multi-cue `LightingLook`; the platform `MusicSyncEngine` uses each brief's `startTime` to
// auto-advance cues on the section boundaries. Pure logic so the smoke tests pin the merge/clamp/energy
// math without a simulator.

/// One section turned into a cue: its display name, where it starts, and the energy-derived look hints.
struct CueBrief: Codable, Equatable {
    var name: String                 // display name (繁中, by SectionKind: 開場/主歌/副歌/橋段/…)
    var startTime: Double            // section start (seconds) — drives auto cue advance at playback
    var energy: Double               // 0..1 = f(pace, loudness), clamped
    var keyMode: MusicKeyMode
    var dominantInstruments: [String]
    var suggestedIntensity: Double   // 0..1 (high energy → brighter)
    var highEnergy: Bool             // energy >= LightEffectPlan.highEnergyThreshold

    /// Energy from a section's averaged pace + loudness: pace-weighted, clamped to 0...1.
    static func energy(pace: Double, loudness: Double) -> Double {
        min(max(0.6 * pace + 0.4 * loudness, 0), 1)
    }

    /// Suggested cue intensity from energy: a baseline floor so even a calm cue is visible, rising to full.
    static func suggestedIntensity(forEnergy energy: Double) -> Double {
        min(max(0.35 + 0.6 * energy, 0), 1)
    }

    /// 繁中 cue name for a section kind (the user-facing cue label).
    static func displayName(for kind: SectionKind) -> String {
        switch kind {
        case .intro: return "開場"
        case .verse: return "主歌"
        case .chorus: return "副歌"
        case .bridge: return "橋段"
        case .breakdown: return "間奏"
        case .drop: return "爆發"
        case .outro: return "收尾"
        case .unknown: return "段落"
        }
    }

    /// Builds a brief from a (possibly merged) section.
    init(section: SongSection) {
        let energy = CueBrief.energy(pace: section.pace, loudness: section.loudness)
        self.name = CueBrief.displayName(for: section.kind)
        self.startTime = section.start
        self.energy = energy
        self.keyMode = section.keyMode
        self.dominantInstruments = section.dominantInstruments
        self.suggestedIntensity = CueBrief.suggestedIntensity(forEnergy: energy)
        self.highEnergy = energy >= LightEffectPlan.highEnergyThreshold
    }

    /// A neutral, mid-energy fallback cue (used when the analysis has no usable sections).
    init(neutralName: String, startTime: Double) {
        let energy = 0.5
        self.name = neutralName
        self.startTime = startTime
        self.energy = energy
        self.keyMode = .unknown
        self.dominantInstruments = []
        self.suggestedIntensity = CueBrief.suggestedIntensity(forEnergy: energy)
        self.highEnergy = energy >= LightEffectPlan.highEnergyThreshold
    }
}

/// The ordered cue plan for a whole show.
struct ShowPlan: Codable, Equatable {
    var cues: [CueBrief]

    /// Builds a plan from an analysis. Merges adjacent same-kind sections; folds sections shorter than
    /// `minCueSeconds` into the previous cue; caps the count to `maxCues` by keeping the longest sections'
    /// boundaries. Always yields at least 2 cues (a look needs a selectable cue stack — `LightingLook`
    /// keeps the "non-empty + selection resolves" invariant, and the cue-stack/GO flow wants ≥2). An
    /// empty analysis yields one neutral cue, padded to 2.
    static func make(from analysis: SongAnalysis, maxCues: Int = 6, minCueSeconds: Double = 8) -> ShowPlan {
        let cap = max(2, maxCues)

        // Empty analysis → a single neutral cue (padded to 2 below).
        guard !analysis.sections.isEmpty else {
            return ShowPlan(cues: padToTwo([CueBrief(neutralName: "演出", startTime: 0)]))
        }

        let ordered = analysis.sections.sorted { $0.start < $1.start }

        // 1) Merge adjacent same-kind sections (extend the run; average pace/loudness by duration).
        var merged: [SongSection] = []
        for section in ordered {
            if var last = merged.last, last.kind == section.kind {
                let combined = mergeDurationWeighted(last, section)
                last = combined
                merged[merged.count - 1] = last
            } else {
                merged.append(section)
            }
        }

        // 2) Fold sub-minimum sections into the previous one (or the next, if it's the very first).
        var folded: [SongSection] = []
        for section in merged {
            if section.duration < minCueSeconds, let last = folded.last {
                folded[folded.count - 1] = mergeDurationWeighted(last, section)
            } else {
                folded.append(section)
            }
        }
        // If the first section was sub-minimum it stays as the only entry; that's fine (padded to 2 later).

        // 3) Cap to maxCues: keep the longest sections as cue boundaries, then re-sort by start.
        var capped = folded
        if capped.count > cap {
            let keptStarts = Set(
                capped.sorted { $0.duration > $1.duration }
                    .prefix(cap)
                    .map(\.start)
            )
            capped = capped.filter { keptStarts.contains($0.start) }
        }

        let cues = capped.map(CueBrief.init(section:))
        return ShowPlan(cues: padToTwo(cues))
    }

    /// Merges two sections into one spanning both, averaging pace/loudness weighted by duration, keeping
    /// the first's kind/keyMode, and unioning dominant instruments (order-stable, deduplicated).
    private static func mergeDurationWeighted(_ a: SongSection, _ b: SongSection) -> SongSection {
        let da = max(a.duration, 0.0001)
        let db = max(b.duration, 0.0001)
        let total = da + db
        var instruments = a.dominantInstruments
        for instrument in b.dominantInstruments where !instruments.contains(instrument) {
            instruments.append(instrument)
        }
        return SongSection(
            start: min(a.start, b.start),
            end: max(a.end, b.end),
            kind: a.kind,
            pace: (a.pace * da + b.pace * db) / total,
            loudness: (a.loudness * da + b.loudness * db) / total,
            keyMode: a.keyMode,
            dominantInstruments: instruments
        )
    }

    /// Ensures at least 2 cues: a single cue is duplicated into a neutral second cue so the look keeps a
    /// selectable cue stack.
    private static func padToTwo(_ cues: [CueBrief]) -> [CueBrief] {
        guard cues.count >= 2 else {
            guard let only = cues.first else {
                // Never empty in practice, but stay total.
                let a = CueBrief(neutralName: "開場", startTime: 0)
                let b = CueBrief(neutralName: "收尾", startTime: 0)
                return [a, b]
            }
            var second = only
            second.name = "收尾"
            return [only, second]
        }
        return cues
    }
}
