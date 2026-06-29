import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Speaks short feedback aloud for the voice-only / accessibility mode — so a user who can't see (or
/// isn't looking at) the floating composer can still follow what the AI just did, step cues, and hear
/// the explanation. A thin wrapper over `AVSpeechSynthesizer` that prefers a Traditional-Chinese voice
/// and degrades to a no-op where AVFoundation is unavailable.
///
/// Not in the smoke-test compile set: it holds no pure logic worth pinning. The testable hands-free
/// logic (what counts as a "next cue" / "read it" utterance) lives in `StageVoiceCommand`.
@MainActor
final class SpeechNarrator {
#if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
#endif

    /// Speaks `text`, interrupting anything currently being spoken. Empty/whitespace is ignored.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
#if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
            ?? AVSpeechSynthesisVoice(language: "zh-Hant")
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
#endif
    }

    func stop() {
#if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
#endif
    }
}
