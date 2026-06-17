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
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
#endif

    func start() async throws {
#if canImport(Speech) && canImport(AVFoundation)
        guard await requestSpeechAuthorization() else {
            lastError = "Speech recognition permission has not been granted."
            throw SpeechTranscriberError.permissionDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognition is currently unavailable."
            throw SpeechTranscriberError.recognizerUnavailable
        }

        stop()
        transcript = ""
        lastError = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [
            "wash",
            "spot",
            "front light",
            "background wash",
            "dimmer",
            "intensity",
            "brightness"
        ]
        recognitionRequest = request

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
        lastError = "Speech recognition is not supported on this platform."
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
            return "Microphone or speech recognition permission was denied."
        case .recognizerUnavailable:
            return "Speech recognition is currently unavailable."
        }
    }
}
