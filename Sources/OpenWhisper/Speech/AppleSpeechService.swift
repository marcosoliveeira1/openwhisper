import AVFoundation
import Foundation
import Speech

actor AppleSpeechService: DictationService {
    private var onPartial: (@Sendable (String) -> Void)?

    private let locale = Locale(identifier: "pt-BR")
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var accumulated = ""
    private var finalContinuation: CheckedContinuation<String?, Never>?
    private var resolved = false
    private var configObserver: NSObjectProtocol?

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) {
        onPartial = handler
    }

    func start() async throws {
        installConfigurationObserverIfNeeded()
        guard try await authorize() else {
            throw FailureReason.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw FailureReason.recognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        accumulated = ""
        resolved = false

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw FailureReason.engineError("nenhum dispositivo de entrada de áudio")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw FailureReason.engineError("falha ao iniciar captura de áudio: \(error.localizedDescription)")
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task {
                    await self.handleResult(text: text, isFinal: isFinal)
                }
            }
            if error != nil {
                Task {
                    await self.handleFailure()
                }
            }
        }
    }

    func finish() async -> String? {
        stopCapture()
        request?.endAudio()
        return await withCheckedContinuation { continuation in
            finalContinuation = continuation
            resolved = false
            Task {
                try? await Task.sleep(for: .seconds(15))
                self.resolveTimeout()
            }
        }
    }

    func cancel() async {
        stopCapture()
        task?.cancel()
        request?.endAudio()
        resolve(with: nil)
        reset()
    }

    private func handleResult(text: String, isFinal: Bool) {
        accumulated = text
        if isFinal {
            resolve(with: text)
        } else {
            onPartial?(text)
        }
    }

    private func handleFailure() {
        resolve(with: accumulated.isEmpty ? nil : accumulated)
    }

    private func installConfigurationObserverIfNeeded() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleEngineStopped()
            }
        }
    }

    private func handleEngineStopped() {
        guard task != nil else { return }
        handleFailure()
    }

    private func resolveTimeout() {
        guard finalContinuation != nil else { return }
        resolve(with: accumulated.isEmpty ? nil : accumulated)
    }

    private func resolve(with text: String?) {
        guard !resolved, let continuation = finalContinuation else { return }
        resolved = true
        finalContinuation = nil
        continuation.resume(returning: text)
    }

    private func reset() {
        request = nil
        task = nil
        accumulated = ""
    }

    private func stopCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func authorize() async throws -> Bool {
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else { return false }
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return true
    }
}
