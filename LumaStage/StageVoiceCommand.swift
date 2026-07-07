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
    /// Start auto-playback of the show — the cue list runs itself, following cue to cue (SPEC 16). When a
    /// music show is loaded, `AppModel` routes this to music playback instead; otherwise to cue-list playback.
    case playShow
    /// Stop auto-playback (music show or cue list), holding the current cue.
    case stopShow

    /// Filler words that may surround a bare command without changing it ("ok go now" is still "go").
    private static let filler: Set<String> = ["please", "now", "okay", "ok", "the", "a", "an", "to", "my"]

    /// English commands as exact token SETS (filler already removed). A command matches only when the
    /// whole utterance — minus filler — IS one of these sets, never when a longer design prompt merely
    /// embeds the phrase. So "add a cooler wash to the next scene" stays a generation prompt instead of
    /// being hijacked into a cue advance (the substring-match bug this replaced).
    private static let englishCommands: [(command: StageVoiceCommand, sets: [Set<String>])] = [
        (.readExplanation, [["read", "it"], ["read", "aloud"], ["read", "it", "aloud"], ["read", "explanation"],
                            ["read", "it", "out", "loud"], ["speak", "it"], ["say", "it"], ["explain", "it"]].map(Set.init)),
        (.addCue, [["add", "cue"], ["new", "cue"], ["another", "cue"], ["duplicate", "cue"],
                   ["add", "scene"], ["new", "scene"]].map(Set.init)),
        (.previousCue, [["previous", "cue"], ["prev", "cue"], ["last", "cue"], ["previous", "scene"],
                        ["go", "back"], ["back"], ["previous"]].map(Set.init)),
        (.nextCue, [["next", "cue"], ["advance", "cue"], ["next", "scene"], ["go", "next"],
                    ["next"], ["advance"], ["go"]].map(Set.init)),
        (.playShow, [["play", "show"], ["run", "show"], ["start", "show"], ["play", "cues"], ["run", "cues"],
                     ["auto", "play"], ["play", "all"], ["start", "playback"], ["play"]].map(Set.init)),
        (.stopShow, [["stop", "show"], ["stop", "playback"], ["halt", "show"], ["stop", "cues"],
                     ["stop", "playing"], ["stop"]].map(Set.init)),
    ]

    /// Chinese commands as needles, longest-first within each command. Chinese has no word boundaries, so
    /// a command matches only when the needle is essentially the whole utterance — its CJK length within a
    /// small slack of the matched needle. So "把燈光調成上一個演出的暖色" stays a generation prompt rather than
    /// stepping to the previous cue (the ASCII-only token guard can't protect CJK).
    private static let chineseCommands: [(command: StageVoiceCommand, needles: [String])] = [
        (.readExplanation, ["念出說明", "說明一下", "解釋一下", "念出", "唸出", "朗讀", "讀出"]),
        (.addCue, ["新增場景", "加一個場景", "加個場景", "複製場景", "增加場景", "多一個場景"]),
        (.previousCue, ["上一個場景", "前一個場景", "回上一個", "上一個", "上一幕", "倒回"]),
        (.nextCue, ["下一個場景", "切下一個", "進下一個", "下一個", "下一幕"]),
        // stopShow BEFORE playShow: "停止播放" contains the bare "播放" needle, so the stop phrases must be
        // tested first or "停止播放" would match playShow (containment, not equality, for CJK).
        (.stopShow, ["停止播放", "停止走場", "停止演出", "停止自動", "停止"]),
        (.playShow, ["播放全部", "自動播放", "開始播放", "開始演出", "自動走場", "播放場景", "跑全場", "播放"]),
    ]

    /// Extra CJK characters tolerated beyond the matched needle — room for a particle like 請/吧 without
    /// admitting a whole design sentence.
    private static let chineseSlack = 2

    static func parse(_ raw: String) -> StageVoiceCommand? {
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // English: the utterance, tokenized and stripped of filler, must EXACTLY equal a command's token
        // set — anchored, so a design sentence that merely contains "next scene" / "go back" falls through.
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let core = Set(tokens.filter { token in !filler.contains(token) && token.allSatisfy(\.isASCII) })
        if !core.isEmpty {
            for entry in englishCommands where entry.sets.contains(core) {
                return entry.command
            }
        }

        // Chinese: anchored by length — the matched needle must be (nearly) the whole CJK utterance.
        let cjkCount = text.filter { !$0.isASCII && $0.isLetter }.count
        if cjkCount > 0 {
            for entry in chineseCommands {
                if let matched = entry.needles.first(where: { text.contains($0) }),
                   cjkCount <= matched.count + chineseSlack {
                    return entry.command
                }
            }
        }

        return nil
    }
}
