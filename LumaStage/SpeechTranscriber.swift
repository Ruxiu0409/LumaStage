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

    /// Follows the system / Siri locale (`Locale.current`) — the SAME locale Apple Intelligence requires
    /// set for on-device generation (e.g. English (US) for the demo, where the user speaks English; or a
    /// supported Chinese locale). So speech recognition, the Foundation Models model, and the language the
    /// user actually speaks all agree. Falls back to en-US, then the default recognizer, if `.current` has
    /// no recognizer. (An earlier version hard-preferred zh-TW, which would mis-transcribe English commands
    /// on an English-locale demo device — the recogniser must match what the operator actually says.)
    private static func makeRecognizer() -> SFSpeechRecognizer? {
        if let current = SFSpeechRecognizer(locale: Locale.current) {
            return current
        }
        if let english = SFSpeechRecognizer(locale: Locale(identifier: "en_US")) {
            return english
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
            // …plus Traditional-Chinese terms that help when the device locale IS Chinese (the recognizer
            // follows Locale.current; on the en-US demo device the English terms above carry it).
            "暖色", "冷色", "藍色", "紅色", "綠色", "開場", "重點",
            "下一個場景", "上一個場景", "新增場景"
        ]
        recognitionRequest = request

        // The default session category (.soloAmbient) can't record; switch to .playAndRecord so dictation
        // works reliably. Best-effort — don't fail dictation on it.
        // AVAudioSession exists on iOS/visionOS but not macOS (this file's canImport(AVFoundation) guard is
        // also satisfied under the macOS SDK during headless analysis), so gate it on the platform.
#if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
#endif

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        // Capture the request locally so the audio-thread tap never touches @MainActor `self` (a Swift 6
        // data race). SFSpeechAudioBufferRecognitionRequest is safe to append to off the main actor.
        let tapBlock: AVAudioNodeTapBlock = { [request] buffer, _ in
            request.append(buffer)
        }
        // Vision 26 only has the non-throwing installTap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0), block: tapBlock)

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
    case audioSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "麥克風或語音辨識權限遭拒。"
        case .recognizerUnavailable:
            return "語音辨識目前無法使用。"
        case .audioSessionUnavailable:
            return "無法啟動麥克風錄音（音訊格式不相容）。"
        }
    }
}
