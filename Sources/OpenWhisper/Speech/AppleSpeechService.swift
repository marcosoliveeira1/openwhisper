import AVFoundation
import Foundation
import Speech
import os

private let speechLog = Logger(subsystem: "br.marcos.openwhisper", category: "speech")

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
    private var taskFailureStreak = 0
    private var isPaused = false

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
        taskFailureStreak = 0
        isPaused = false
        sessionActive = true
        do {
            try startEngineAndTask()
            scheduleWatchdog()
        } catch {
            sessionActive = false
            throw error
        }
    }

    /// Halts capture and recognition while keeping the accumulated transcript.
    func pause() async {
        guard sessionActive, !isPaused, !resolved else { return }
        isPaused = true
        speechLog.info("paused")
        request?.endAudio()
        invalidateSegment()
        stopCapture()
    }

    func resume() async {
        guard sessionActive, isPaused, !resolved else { return }
        isPaused = false
        speechLog.info("resumed")
        do {
            try startEngineAndTask()
            scheduleWatchdog()
        } catch {
            scheduleRetry()
        }
    }

    func finish() async -> String? {
        speechLog.info("finish: active=\(self.sessionActive), paused=\(self.isPaused), request=\(self.request != nil), task=\(self.task != nil), partial=\(self.currentPartial.count), prefix=\(self.transcript.finalizedPrefix.count)")
        guard sessionActive else { return nil }
        if isPaused {
            sessionActive = false
            isPaused = false
            let text = currentPartialText
            speechLog.info("finish while paused, resolving \(text.count) chars")
            return text.isEmpty ? nil : text
        }
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
        isPaused = false
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
        speechLog.info("segment started (gen \(gen), onDevice=\(recognizer.supportsOnDeviceRecognition), available=\(recognizer.isAvailable))")

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
                    await self.handleTaskUpdate(gen: gen, text: text, isFinal: isFinal, failed: false, errorText: nil)
                }
            }
            if let error {
                speechLog.error("recognition task error: \(error.localizedDescription, privacy: .public)")
                Task {
                    await self.handleTaskUpdate(gen: gen, text: "", isFinal: false, failed: true, errorText: error.localizedDescription)
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

    private func handleTaskUpdate(gen: Int, text: String, isFinal: Bool, failed: Bool, errorText: String?) {
        guard gen == generation else { return }
        if failed {
            guard !resolved else { return }
            taskFailureStreak += 1
            speechLog.error("task failed (streak \(self.taskFailureStreak)): \(errorText ?? "unknown", privacy: .public)")
            if sessionActive, taskFailureStreak < 2 {
                rotateSegment(text: currentPartial)
            } else if sessionActive {
                sessionActive = false
                onFailure?(.engineError(errorText ?? "reconhecimento de fala indisponível"))
            } else {
                resolve(with: currentPartialText.isEmpty ? nil : currentPartialText)
            }
            return
        }
        taskFailureStreak = 0
        if isFinal {
            if sessionActive, !isPaused {
                speechLog.info("segment final: \(text.count) chars (prefix \(self.transcript.finalizedPrefix.count))")
                rotateSegment(text: text)
            } else if sessionActive {
                // Final arrived while paused: bank the text, don't restart.
                transcript.finalize(with: text)
                currentPartial = ""
                onPartial?(transcript.finalizedPrefix)
            } else {
                resolve(with: transcript.combined(text))
            }
            return
        }
        guard !isPaused else { return }
        // On-device hypotheses can reset mid-session (e.g. after a pause):
        // the new partial replaces instead of extending. Carry the previous
        // text into the finalized prefix so it isn't lost.
        if currentPartial.count >= 10, text.count < currentPartial.count / 2 {
            speechLog.info("hypothesis reset (\(self.currentPartial.count) → \(text.count) chars); carrying prefix forward")
            transcript.finalize(with: currentPartial)
        }
        currentPartial = text
        speechLog.debug("partial: \(self.currentPartialText.count) chars")
        onPartial?(currentPartialText)
    }

    /// Finalizes the current segment with `text` and starts a fresh recognition task.
    private func rotateSegment(text: String) {
        transcript.finalize(with: text)
        currentPartial = ""
        onPartial?(transcript.finalizedPrefix)
        speechLog.info("rotating segment (prefix \(self.transcript.finalizedPrefix.count) chars)")
        restartRecognition()
    }

    private func restartRecognition() {
        guard sessionActive, !isPaused else { return }
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
        speechLog.error("finish timed out after 15s (partial \(self.currentPartialText.count) chars)")
        resolve(with: currentPartialText.isEmpty ? nil : currentPartialText)
    }

    private func resolve(with text: String?) {
        guard !resolved, let continuation = finalContinuation else { return }
        resolved = true
        finalContinuation = nil
        task?.cancel()
        task = nil
        request = nil
        speechLog.info("resolved with \(text?.count ?? -1) chars")
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
