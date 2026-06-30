import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
import Speech
#endif

@MainActor
@Observable
final class SpeechTranscriber {
    var isRecording = false
    var transcript = ""
    var lastError: String?

#if canImport(Speech) && canImport(AVFoundation)
    private let audioEngine = AVAudioEngine()
    private let recognizer = SpeechTranscriber.makeRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Prefers a Traditional-Chinese recognizer (the app's primary language) when the device supports it,
    /// then the current locale, then en_US — so Chinese voice commands and design prompts can actually be
    /// dictated (mixed Chinese/English). `SFSpeechRecognizer(locale:)` returns nil for an unsupported locale,
    /// so this walks the preference list until one is available. Mirrors the locale gating used for generation.
    private static func makeRecognizer() -> SFSpeechRecognizer? {
        for identifier in ["zh-TW", "zh-Hant-TW", "zh-Hant", Locale.current.identifier, "en_US"] {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) {
                return recognizer
            }
        }
        return SFSpeechRecognizer()
    }
#endif

    func start() async throws {
#if canImport(Speech) && canImport(AVFoundation)
        guard await requestSpeechAuthorization() else {
            lastError = "尚未取得語音辨識權限。"
            throw SpeechTranscriberError.permissionDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            lastError = "語音辨識目前無法使用。"
            throw SpeechTranscriberError.recognizerUnavailable
        }

        stop()
        transcript = ""
        lastError = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [
            // English lighting + show-control vocabulary…
            "wash", "spot", "front light", "background wash", "dimmer", "intensity", "brightness",
            "GO", "next cue", "previous cue", "blackout",
            // …and the Traditional-Chinese terms a zh-TW recognizer should bias toward (the primary language).
            "暖色", "冷色", "藍色", "紅色", "綠色", "開場", "重點",
            "下一個場景", "上一個場景", "新增場景", "念出說明"
        ]
        recognitionRequest = request

        // The default session category (.soloAmbient) can't record; switch to .playAndRecord so dictation
        // works and any narration ducks/routes to the speaker. Best-effort — don't fail dictation on it.
        // AVAudioSession exists on iOS/visionOS but not macOS (this file's canImport(AVFoundation) guard is
        // also satisfied under the macOS SDK during headless analysis), so gate it on the platform.
#if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
#endif

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    self?.lastError = error.localizedDescription
                    self?.stop()
                }
            }
        }
#else
        lastError = "此平台不支援語音辨識。"
        throw SpeechTranscriberError.recognizerUnavailable
#endif
    }

    @discardableResult
    func stop() -> String {
#if canImport(Speech) && canImport(AVFoundation)
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.finish()
        recognitionTask = nil
#endif
        isRecording = false
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

#if canImport(Speech)
    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
#endif
}

enum SpeechTranscriberError: Error, LocalizedError {
    case permissionDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "麥克風或語音辨識權限遭拒。"
        case .recognizerUnavailable:
            return "語音辨識目前無法使用。"
        }
    }
}
