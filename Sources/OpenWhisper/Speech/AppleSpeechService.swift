import AVFoundation
import Foundation
import Speech

actor AppleSpeechService: DictationService, AudioLevelProviding {
    private var onPartial: (@Sendable (String) -> Void)?
    private var onLevel: (@Sendable (Double) -> Void)?
    private var smoothedLevel: Double = 0

    private let locale = Locale(identifier: "pt-BR")
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = SegmentTranscript()
    private var currentPartial = ""
    private var sessionActive = false
    private var finalContinuation: CheckedContinuation<String?, Never>?
    private var resolved = false
    private var configObserver: NSObjectProtocol?

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) {
        onPartial = handler
    }

    func setLevelHandler(_ handler: @escaping @Sendable (Double) -> Void) {
        onLevel = handler
        smoothedLevel = 0
    }

    private func emitLevel(_ level: Double) {
        smoothedLevel = max(level, smoothedLevel * 0.82)
        onLevel?(smoothedLevel)
    }

    func start() async throws {
        installConfigurationObserverIfNeeded()
        guard try await authorize() else {
            throw FailureReason.permissionDenied
        }
        transcript.reset()
        currentPartial = ""
        smoothedLevel = 0
        resolved = false
        sessionActive = true
        do {
            try startEngineAndTask()
        } catch {
            sessionActive = false
            throw error
        }
    }

    func finish() async -> String? {
        sessionActive = false
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
        sessionActive = false
        stopCapture()
        task?.cancel()
        request?.endAudio()
        resolve(with: nil)
        reset()
    }

    private func startEngineAndTask() throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw FailureReason.recognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw FailureReason.engineError("nenhum dispositivo de entrada de áudio")
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let self, let channel = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            let data = channel[0]
            var sum: Float = 0
            for i in 0..<frames {
                let sample = data[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frames))
            let db = 20 * log10(max(rms, 1e-6))
            let level = Double(max(0, min(1, (db + 55) / 40)))
            Task {
                await self.emitLevel(level)
            }
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                throw FailureReason.engineError("falha ao iniciar captura de áudio: \(error.localizedDescription)")
            }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task {
                    await self.handleTaskUpdate(text: text, isFinal: isFinal, failed: false)
                }
            }
            if error != nil {
                Task {
                    await self.handleTaskUpdate(text: self.currentPartialText, isFinal: false, failed: true)
                }
            }
        }
    }

    private var currentPartialText: String {
        transcript.combined(currentPartial)
    }

    private func handleTaskUpdate(text: String, isFinal: Bool, failed: Bool) {
        if failed {
            guard sessionActive else { return }
            restartAfterSegmentEnd(text: text)
            return
        }
        if isFinal {
            if sessionActive {
                restartAfterSegmentEnd(text: text)
            } else {
                resolve(with: transcript.combined(text))
            }
            return
        }
        currentPartial = text
        onPartial?(currentPartialText)
    }

    private func restartAfterSegmentEnd(text: String) {
        transcript.finalize(with: text)
        currentPartial = ""
        onPartial?(transcript.finalizedPrefix)
        restartRecognition()
    }

    private func restartRecognition() {
        guard sessionActive else { return }
        task = nil
        do {
            try startEngineAndTask()
        } catch {
            sessionActive = false
            handleFailure()
        }
    }

    private func handleFailure() {
        resolve(with: currentPartialText.isEmpty ? nil : currentPartialText)
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
        guard sessionActive else { return }
        restartRecognition()
    }

    private func resolveTimeout() {
        guard finalContinuation != nil else { return }
        resolve(with: currentPartialText.isEmpty ? nil : currentPartialText)
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
        currentPartial = ""
        transcript.reset()
        smoothedLevel = 0
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
