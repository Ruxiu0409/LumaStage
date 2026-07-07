import Foundation

// MARK: - Built-in demo backing track synthesizer (Foundation-only, smoke-tested)
//
// The built-in demo song (`CachedSongAnalyzer` → `demo-song-analysis.json`) ships a hand-authored
// `SongAnalysis` (128 BPM, ~150s, intro→verse→chorus→bridge→chorus→outro) that drives the light show,
// but it had NO audio — the demo played visuals in silence and cues couldn't auto-advance (no audio
// tick). Rather than bundle a copyrighted MP3, we synthesize a fully-original EDM-style backing track
// procedurally, beat-locked to the analysis's exact beat grid + sections. Because it's generated from the
// same `SongAnalysis` the visuals use, the kick lands on every rendered beat and the energy rises into the
// choruses, so playback, beat-lock, and cue auto-advance all line up with the on-stage look.
//
// This file is deliberately `Foundation`-only (no AVFoundation): the render is pure sample math and the
// WAV bytes are plain little-endian packing, so the smoke tests can pin the output shape/format headlessly.
// The platform wiring (write the WAV to Caches once, hand the URL to the playback engine) lives in
// `AppModel.useBuiltInDemoSong`, mirroring how `MusicUnderstandingService` owns the framework side while the
// Foundation core stays testable. The synth is deterministic (no RNG state, no wall-clock) so the same
// analysis always renders byte-identical audio — the smoke test relies on that.

enum DemoTrackSynth {

    /// Output sample rate (mono). 44.1 kHz is universally decodable by `AVAudioPlayer`.
    static let sampleRate = 44_100

    // MARK: Public API

    /// Render + encode a full 16-bit PCM mono WAV for `analysis`. Convenience over
    /// `renderSamples(for:)` + `wavData(fromMono:)`.
    static func wavData(for analysis: SongAnalysis) -> Data {
        wavData(fromMono: renderSamples(for: analysis), sampleRate: sampleRate)
    }

    /// Render the backing track as mono float samples in `[-1, 1]`, one voice-summed sample per frame.
    ///
    /// The track is driven entirely by `analysis`: `beatTimes` place the kick/hats/bass/arp onsets so the
    /// audio pulse matches the visuals' beat-lock exactly, and each `SongSection`'s `loudness`/`pace`/`keyMode`
    /// shape that stretch's energy, groove density, and chord colour. Sections with more energy get a fuller
    /// kick, denser bass, hats, and a chorus arp; the master level swells into choruses so the build reads.
    static func renderSamples(for analysis: SongAnalysis) -> [Float] {
        let sr = Double(sampleRate)

        // Duration: prefer the declared duration, else the last beat, else a short safe minimum.
        let duration = max(analysis.duration, max(analysis.beatTimes.last ?? 0, 1))
        let frameCount = max(1, Int((duration * sr).rounded()))

        // Beat grid: use the analysis's own beats when present (exact visual alignment); else derive from bpm.
        let beats = beatOnsets(for: analysis, duration: duration)
        let beatPeriod = beats.count >= 2 ? (beats[1] - beats[0]) : (60.0 / max(analysis.bpm ?? 128, 1))

        // Precompute per-beat context (section energy/mode/pace + a running beat counter) so the per-sample
        // loop only does cheap lookups. Onsets are also flattened into ascending arrays per voice.
        let sections = analysis.sections
        var samples = [Float](repeating: 0, count: frameCount)

        // --- Kick: one per beat, gain tracking section energy (soft in intro/outro, full in choruses) -------
        for beat in beats {
            let sec = section(at: beat, in: sections)
            let gain = 0.35 + 0.65 * energyNorm(sec?.loudness ?? 0.5)
            addKick(into: &samples, at: beat, sr: sr, gain: Float(gain))
        }

        // --- Bass: root note per section; eighth-notes in fast/energetic sections, quarters otherwise -------
        for (index, beat) in beats.enumerated() {
            let sec = section(at: beat, in: sections)
            let energy = energyNorm(sec?.loudness ?? 0.5)
            guard energy >= 0.18 else { continue }   // intro-quiet stretches stay pad-only
            let major = (sec?.keyMode ?? .minor) == .major
            let rootHz = major ? 65.41 : 55.0        // C2 (major) / A1 (minor)
            let bassGain = Float(0.16 + 0.20 * energy)
            let eighths = (sec?.pace ?? 0.5) >= 0.7
            // Quarter note on the beat …
            addBass(into: &samples, at: beat, freq: rootHz, dur: beatPeriod * (eighths ? 0.48 : 0.92),
                    sr: sr, gain: bassGain)
            // … plus the off-beat eighth in busier sections (walk up to the fifth for movement).
            if eighths, index % 2 == 1 {
                addBass(into: &samples, at: beat + beatPeriod * 0.5, freq: rootHz * semitone(7),
                        dur: beatPeriod * 0.42, sr: sr, gain: bassGain * 0.85)
            }
        }

        // --- Hats: an off-beat tick in mid/high-energy sections; a closed hat on every beat in choruses -----
        for beat in beats {
            let sec = section(at: beat, in: sections)
            let energy = energyNorm(sec?.loudness ?? 0.5)
            if energy >= 0.35 {
                addHat(into: &samples, at: beat + beatPeriod * 0.5, sr: sr, gain: Float(0.10 + 0.06 * energy))
            }
            if energy >= 0.7 {
                addHat(into: &samples, at: beat, sr: sr, gain: Float(0.05 + 0.04 * energy))
            }
        }

        // --- Arp: a bright plucked chord-tone sequence over the choruses so the drop has a melodic top ------
        for (index, beat) in beats.enumerated() {
            let sec = section(at: beat, in: sections)
            guard energyNorm(sec?.loudness ?? 0.5) >= 0.8 else { continue }
            let major = (sec?.keyMode ?? .minor) == .major
            let padRoot = major ? 261.63 : 220.0           // C4 (major) / A3 (minor)
            let steps: [Double] = [0, major ? 4 : 3, 7, 12]  // root, third, fifth, octave
            let step = steps[index % steps.count]
            let freq = padRoot * 2 * semitone(step)          // an octave up from the pad for sparkle
            addPluck(into: &samples, at: beat, freq: freq, dur: beatPeriod * 0.9, sr: sr, gain: 0.14)
        }

        // --- Pad: a sustained chord bed present throughout so nothing is ever dead silent -------------------
        addPad(into: &samples, sections: sections, duration: duration, sr: sr)

        // --- Master: per-section swell, soft-clip, and click-free fades ------------------------------------
        finalizeMaster(&samples, sections: sections, sr: sr)

        return samples
    }

    /// Encode mono float samples in `[-1, 1]` as a canonical 16-bit PCM WAV (`RIFF`/`WAVE`/`fmt `/`data`,
    /// little-endian). Values are clamped then scaled to `Int16`. The header is the standard 44 bytes.
    static func wavData(fromMono samples: [Float], sampleRate: Int = DemoTrackSynth.sampleRate) -> Data {
        let bitsPerSample = 16
        let channels = 1
        let bytesPerSample = bitsPerSample / 8
        let dataSize = samples.count * channels * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var data = Data(capacity: 44 + dataSize)
        data.append(ascii: "RIFF")
        data.append(le32: UInt32(36 + dataSize))          // chunk size = 36 + data
        data.append(ascii: "WAVE")
        data.append(ascii: "fmt ")
        data.append(le32: 16)                             // PCM fmt chunk size
        data.append(le16: 1)                              // audioFormat = PCM
        data.append(le16: UInt16(channels))
        data.append(le32: UInt32(sampleRate))
        data.append(le32: UInt32(byteRate))
        data.append(le16: UInt16(blockAlign))
        data.append(le16: UInt16(bitsPerSample))
        data.append(ascii: "data")
        data.append(le32: UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            // Scale by 32767 so +1.0 → 32767 and -1.0 → -32767 (symmetric, avoids Int16 overflow at -32768).
            let value = Int16(clamped * 32_767)
            data.append(le16: UInt16(bitPattern: value))
        }
        return data
    }

    // MARK: Voices (each adds into the buffer; all deterministic, click-free)

    /// A punchy kick: a sine whose pitch drops from ~110 Hz to ~45 Hz with a fast amplitude decay. The phase
    /// uses the analytic integral of the exponential pitch envelope so it's continuous (no click).
    private static func addKick(into buf: inout [Float], at start: Double, sr: Double, gain: Float) {
        let dur = 0.22
        let k = 26.0                          // pitch-drop rate
        let fStart = 110.0, fEnd = 45.0
        let n0 = max(0, Int(start * sr))
        let n1 = min(buf.count, Int((start + dur) * sr))
        guard n1 > n0 else { return }
        for n in n0..<n1 {
            let t = Double(n) / sr - start
            // ∫₀ᵗ f(s) ds with f(s) = fEnd + (fStart-fEnd)·e^(-k·s)
            let phase = 2 * Double.pi * (fEnd * t + (fStart - fEnd) / k * (1 - exp(-k * t)))
            // Fast body decay, then a short tail ramp to exactly 0 at `dur`: the exp envelope alone is still
            // at ~3% of full level when the write window ends, so without the ramp it would step to zero in
            // one sample — an audible click on every beat.
            let amp = exp(-t * 16) * tailFade(t, dur: dur, release: 0.02)
            buf[n] += Float(sin(phase) * amp) * gain
        }
    }

    /// A round bass note: root sine plus a touch of 2nd/3rd harmonic, with a quick attack and gentle decay.
    private static func addBass(into buf: inout [Float], at start: Double, freq: Double, dur: Double,
                                sr: Double, gain: Float) {
        let n0 = max(0, Int(start * sr))
        let n1 = min(buf.count, Int((start + dur) * sr))
        guard n1 > n0 else { return }
        for n in n0..<n1 {
            let t = Double(n) / sr - start
            let ph = 2 * Double.pi * freq * t
            let tone = sin(ph) + 0.28 * sin(2 * ph) + 0.12 * sin(3 * ph)
            buf[n] += Float(tone * adEnvelope(t, dur: dur, attack: 0.006, release: 0.05)) * gain
        }
    }

    /// A short filtered-noise hat tick: white noise through a fast exponential decay.
    private static func addHat(into buf: inout [Float], at start: Double, sr: Double, gain: Float) {
        let dur = 0.045
        let n0 = max(0, Int(start * sr))
        let n1 = min(buf.count, Int((start + dur) * sr))
        guard n1 > n0 else { return }
        for n in n0..<n1 {
            let t = Double(n) / sr - start
            // Same tail ramp as the kick: the noise envelope is still audible at the write-window edge, so
            // ramp it to 0 at `dur` to avoid a per-onset tick.
            let amp = exp(-t * 90) * tailFade(t, dur: dur, release: 0.008)
            buf[n] += whiteNoise(n) * Float(amp) * gain
        }
    }

    /// A bright plucked note (sine + octave), quick pluck envelope — the chorus melodic sparkle.
    private static func addPluck(into buf: inout [Float], at start: Double, freq: Double, dur: Double,
                                 sr: Double, gain: Float) {
        let n0 = max(0, Int(start * sr))
        let n1 = min(buf.count, Int((start + dur) * sr))
        guard n1 > n0 else { return }
        for n in n0..<n1 {
            let t = Double(n) / sr - start
            let ph = 2 * Double.pi * freq * t
            let tone = sin(ph) + 0.4 * sin(2 * ph)
            let amp = exp(-t * 7) * adEnvelope(t, dur: dur, attack: 0.004, release: 0.03)
            buf[n] += Float(tone * amp) * gain
        }
    }

    /// A sustained triad pad bed spanning the whole song. Each section contributes a root/third/fifth chord
    /// (major or minor third per `keyMode`) built from slightly detuned sines with a slow LFO tremolo, cross-
    /// faded at section edges so it never clicks. Its level tracks section energy so choruses swell.
    private static func addPad(into buf: inout [Float], sections: [SongSection], duration: Double, sr: Double) {
        // If the analysis carried no sections, lay a single neutral minor pad over the whole track.
        let spans: [SongSection] = sections.isEmpty
            ? [SongSection(start: 0, end: duration, kind: .unknown, pace: 0.5, loudness: 0.5,
                           keyMode: .minor, dominantInstruments: [])]
            : sections

        for sec in spans {
            let major = sec.keyMode == .major
            let root = major ? 261.63 : 220.0                    // C4 / A3
            let chord = [root, root * semitone(major ? 4 : 3), root * semitone(7)]
            let level = Float(0.06 + 0.06 * energyNorm(sec.loudness))
            let fade = 0.4                                        // seconds of edge cross-fade
            let n0 = max(0, Int(sec.start * sr))
            let n1 = min(buf.count, Int(sec.end * sr))
            guard n1 > n0 else { continue }
            for n in n0..<n1 {
                let t = Double(n) / sr
                let local = t - sec.start
                let span = sec.end - sec.start
                // Cross-fade in/out at the section edges.
                let edge = min(1, min(local, span - local) / fade)
                let trem = 0.85 + 0.15 * sin(2 * Double.pi * 0.4 * t)   // slow tremolo
                var voice = 0.0
                for (i, f) in chord.enumerated() {
                    let detune = 1.0 + (Double(i) - 1) * 0.0015          // gentle chorus detune
                    voice += sin(2 * Double.pi * f * detune * t)
                }
                buf[n] += Float(voice / Double(chord.count) * trem * Double(max(0, edge))) * level
            }
        }
    }

    /// Master bus: a per-section level swell (so choruses are clearly louder than the intro), a `tanh`
    /// soft-clip for headroom, and short fades at the very start/end so the file never clicks on load/finish.
    private static func finalizeMaster(_ buf: inout [Float], sections: [SongSection], sr: Double) {
        let count = buf.count
        guard count > 0 else { return }
        let fadeIn = Int(0.02 * sr)
        let fadeOut = Int(1.5 * sr)
        let masterGain: Float = 0.9

        for n in 0..<count {
            let t = Double(n) / sr
            let sec = section(at: t, in: sections)
            let swell = Float(0.55 + 0.45 * energyNorm(sec?.loudness ?? 0.5))
            var v = buf[n] * masterGain * swell
            v = tanhf(v * 1.2)                              // soft-clip, keeps peaks under 1.0
            if n < fadeIn { v *= Float(n) / Float(max(1, fadeIn)) }
            if n > count - fadeOut { v *= Float(count - n) / Float(max(1, fadeOut)) }
            buf[n] = v
        }
    }

    // MARK: Helpers

    /// Beat onset times: the analysis's own `beatTimes` when it has ≥2 (exact visual alignment), else a grid
    /// generated from `bpm` (default 128) across the duration.
    private static func beatOnsets(for analysis: SongAnalysis, duration: Double) -> [Double] {
        if analysis.beatTimes.count >= 2 {
            return analysis.beatTimes.filter { $0.isFinite && $0 >= 0 && $0 < duration }
        }
        let bpm = max(analysis.bpm ?? 128, 1)
        let period = 60.0 / bpm
        var out: [Double] = []
        var t = 0.0
        while t < duration { out.append(t); t += period }
        return out
    }

    /// The section covering time `t` (first whose `[start, end)` contains it); nil if none.
    private static func section(at t: Double, in sections: [SongSection]) -> SongSection? {
        sections.first { t >= $0.start && t < $0.end } ?? sections.last { t >= $0.start }
    }

    /// Map a 0..1 `loudness` reading onto a normalized 0..1 energy with a sensible spread (0.3→0, 0.9→1),
    /// clamped. Keeps quiet sections from going fully silent and loud ones from over-driving.
    private static func energyNorm(_ loudness: Double) -> Double {
        min(1, max(0, (loudness - 0.3) / 0.6))
    }

    /// A tail-only fade that is 1.0 until `release` seconds before `dur`, then ramps linearly to 0 at `dur`
    /// (and 0 past it). Used by voices whose exponential decay hasn't reached silence by the end of their
    /// write window (kick/hat) so the buffer never steps to zero in a single sample (a click).
    private static func tailFade(_ t: Double, dur: Double, release: Double) -> Double {
        guard t < dur else { return 0 }
        guard release > 0 else { return 1 }
        return min(1, max(0, (dur - t) / release))
    }

    /// A simple attack/release envelope over a note of length `dur`, sustaining at 1.0 in the middle.
    private static func adEnvelope(_ t: Double, dur: Double, attack: Double, release: Double) -> Double {
        guard t >= 0, t <= dur else { return 0 }
        if t < attack { return t / attack }
        if t > dur - release { return max(0, (dur - t) / release) }
        return 1
    }

    /// Deterministic white noise in `[-1, 1]` indexed by sample number (a hash, so it's stateless/reproducible).
    private static func whiteNoise(_ i: Int) -> Float {
        var x = UInt64(bitPattern: Int64(i)) &* 0x2545_F491_4F6C_DD1D &+ 0x9E37_79B9_7F4A_7C15
        x ^= x >> 33; x = x &* 0xFF51_AFD7_ED55_8CCD; x ^= x >> 33
        let u = Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)   // [0, 1)
        return Float(u * 2 - 1)
    }

    /// Equal-temperament ratio for `n` semitones (2^(n/12)).
    private static func semitone(_ n: Double) -> Double { pow(2.0, n / 12.0) }
}

// MARK: - Little-endian WAV byte packing

private extension Data {
    mutating func append(ascii string: String) {
        append(contentsOf: string.utf8)
    }
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
    mutating func append(le32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
