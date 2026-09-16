import AVFoundation
import Foundation
import Speech

actor AppleSpeechService: DictationService, AudioLevelProviding {
    private var onPartial: (@Sendable (String) -> Void)?
    private var onFailure: (@Sendable (FailureReason) -> Void)?
    private var onLevel: (@Sendable (Double) -> Void)?
    private var smoothedLevel: Double = 0

    private let locale = Locale(identifier: "pt-BR")
    private let audioEngine = AVAudioEngine()
    private static let segmentLimit: Duration = .seconds(50)
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var watchdog: Task<Void, Never>?
    private var transcript = SegmentTranscript()
    private var currentPartial = ""
    private var sessionActive = false
    private var finalContinuation: CheckedContinuation<String?, Never>?
    private var resolved = false
    private var configObserver: NSObjectProtocol?

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) {
        onPartial = handler
    }

    func setFailureHandler(_ handler: @escaping @Sendable (FailureReason) -> Void) {
        onFailure = handler
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
        generation += 1
        invalidateSegment()
        transcript.reset()
        currentPartial = ""
        smoothedLevel = 0
        resolved = false
        sessionActive = true
        do {
            try startEngineAndTask()
            scheduleWatchdog()
        } catch {
            sessionActive = false
            throw error
        }
    }

    func finish() async -> String? {
        guard sessionActive else { return nil }
        sessionActive = false
        watchdog?.cancel()
        watchdog = nil
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
        generation += 1
        invalidateSegment()
        stopCapture()
        task?.cancel()
        request?.endAudio()
        resolve(with: nil)
        reset()
    }

    // MARK: - Segment lifecycle

    private func startEngineAndTask() throws {
        guard let recognizer = ensureRecognizer(), recognizer.isAvailable else {
            throw FailureReason.recognitionUnavailable
        }

        generation += 1
        let gen = generation

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
        nonisolated(unsafe) let tapRequest = request
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            tapRequest.append(buffer)
            guard let channel = buffer.floatChannelData else { return }
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

        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task {
                    await self.handleTaskUpdate(gen: gen, text: text, isFinal: isFinal, failed: false)
                }
            }
            if error != nil {
                Task {
                    await self.handleTaskUpdate(gen: gen, text: "", isFinal: false, failed: true)
                }
            }
        }
    }

    private func ensureRecognizer() -> SFSpeechRecognizer? {
        if let recognizer { return recognizer }
        guard let fresh = SFSpeechRecognizer(locale: locale) else { return nil }
        recognizer = fresh
        return fresh
    }

    private func handleTaskUpdate(gen: Int, text: String, isFinal: Bool, failed: Bool) {
        guard gen == generation else { return }
        if failed {
            guard !resolved else { return }
            if sessionActive {
                rotateSegment(text: currentPartial)
            } else {
                resolve(with: currentPartialText.isEmpty ? nil : currentPartialText)
            }
            return
        }
        if isFinal {
            if sessionActive {
                rotateSegment(text: text)
            } else {
                resolve(with: transcript.combined(text))
            }
            return
        }
        currentPartial = text
        onPartial?(currentPartialText)
    }

    /// Finalizes the current segment with `text` and starts a fresh recognition task.
    private func rotateSegment(text: String) {
        transcript.finalize(with: text)
        currentPartial = ""
        onPartial?(transcript.finalizedPrefix)
        restartRecognition()
    }

    private func restartRecognition() {
        guard sessionActive else { return }
        invalidateSegment()
        do {
            try startEngineAndTask()
            scheduleWatchdog()
        } catch {
            scheduleRetry()
        }
    }

    /// One quick retry before surfacing the failure — recognizer availability
    /// can flicker momentarily between segments.
    private func scheduleRetry() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.retrySegment()
        }
    }

    private func retrySegment() {
        guard sessionActive, !resolved else { return }
        do {
            try startEngineAndTask()
            scheduleWatchdog()
        } catch {
            sessionActive = false
            let reason = (error as? FailureReason) ?? .engineError(error.localizedDescription)
            onFailure?(reason)
        }
    }

    /// Rotates the segment before Apple's ~1 minute per-request cap kills the task.
    private func scheduleWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.segmentLimit)
            await self?.segmentTimedOut()
        }
    }

    private func segmentTimedOut() {
        guard sessionActive, !resolved else { return }
        rotateSegment(text: currentPartial)
    }

    private var currentPartialText: String {
        transcript.combined(currentPartial)
    }

    private func invalidateSegment() {
        task?.cancel()
        task = nil
        request = nil
        watchdog?.cancel()
        watchdog = nil
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
        task?.cancel()
        task = nil
        request = nil
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

    private func installConfigurationObserverIfNeeded() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { @Sendable [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleEngineStopped()
            }
        }
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
