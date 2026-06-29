import Foundation

/// A spoken/typed command that drives the **show** — navigating the cue stack, growing it, or asking the
/// app to read its explanation aloud — rather than editing a single light (`LightCommand`) or running a
/// full AI generation. This is the layer that makes the whole design loop runnable hands-free, which is
/// the basis of the voice-only / accessibility mode: generate by voice, step cues by voice ("go"), and
/// have the result spoken back.
///
/// Like `LightCommand`, it's a pure parser: `parse` returns a command for navigation/narration phrases
/// and `nil` for anything else (which falls through to `LightCommand`, then to generative AI). Keywords
/// are matched in BOTH English and Traditional Chinese because `SpeechTranscriber` feeds mixed input.
/// Kept Foundation-only so the smoke tests pin the parsing without speech or a simulator.
enum StageVoiceCommand: Equatable {
    /// Advance to the next cue in the stack — the console GO key.
    case nextCue
    /// Step back to the previous cue — GO back.
    case previousCue
    /// Append a new cue to the stack (duplicates the current cue).
    case addCue
    /// Speak the current AI explanation / understood command aloud.
    case readExplanation

    /// Filler words that may surround a bare command without changing it ("ok go now" is still "go").
    private static let filler: Set<String> = ["please", "now", "okay", "ok", "the", "a", "to", "請", "一下", "吧"]

    static func parse(_ raw: String) -> StageVoiceCommand? {
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Narration first, so "read the cue" reads aloud rather than navigating.
        if contains(text, ["read it", "read aloud", "read the explanation", "read explanation",
                           "speak it", "say it", "explain it", "念出", "唸出", "朗讀", "讀出", "說明一下", "解釋一下"]) {
            return .readExplanation
        }

        if contains(text, ["add cue", "add a cue", "new cue", "another cue", "duplicate cue",
                           "新增場景", "加一個場景", "加個場景", "複製場景", "增加場景", "多一個場景"]) {
            return .addCue
        }

        // Previous before next so "go back" / "previous cue" isn't shadowed by a "go" / "next" match.
        if contains(text, ["previous cue", "prev cue", "last cue", "previous scene", "go back",
                           "上一個場景", "上一個", "上一幕", "前一個場景", "回上一個", "倒回"]) {
            return .previousCue
        }

        if contains(text, ["next cue", "advance cue", "next scene", "go to next", "go next",
                           "下一個場景", "下一個", "下一幕", "切下一個", "進下一個"]) {
            return .nextCue
        }

        // Bare commands: only when the whole utterance IS the command (plus filler), so a design prompt
        // like "go for a warm sunset" never hijacks into a cue advance.
        let words = Set(text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let core = words.subtracting(filler)
        if core.isEmpty == false, core.isSubset(of: ["go", "next", "advance", "back", "previous"]) {
            if core.contains("back") || core.contains("previous") { return .previousCue }
            return .nextCue
        }

        return nil
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
