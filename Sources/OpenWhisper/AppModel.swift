import Foundation
import SwiftUI

enum DictationState: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case failed(FailureReason)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isPaused = false
    @Published private(set) var historyVersion = 0
    @Published private(set) var levelSamples: [Double] = Array(repeating: 0.08, count: 12)
    /// Live IA preview during recording: polished stable sentences, joined.
    @Published private(set) var livePolishedText = ""
    @Published private(set) var livePolishActive = false
    @Published private(set) var livePolishError: String? = nil
    /// True while this session polishes closed sentences live.
    @Published private(set) var livePolishOn = false

    private var pausedAt: Date?

    private let dictation: any DictationService
    private let clipboard: any Clipboard
    private let store: TranscriptionStore
    private let autoPaste: (any AutoPasteService)?
    private let polisher: (any TextPolisher)?
    private let isAutoPasteEnabled: () -> Bool
    private let isLivePolishEnabled: () -> Bool
    private var targetPID: pid_t?
    /// Serial live-polish loop (one IA call at a time, in order).
    private var livePolishTask: Task<Void, Never>?
    /// Window timer: safety net for long unpunctuated speech — every N seconds
    /// any new tail is sent even without a pause, with polished context.
    private var liveWindowTask: Task<Void, Never>?
    /// Units queued for the serial loop but not yet polished (text + its
    /// read-only context snapshot).
    private struct LiveUnit {
        let text: String
        let context: String
    }
    private var livePendingQueue: [LiveUnit] = []
    /// Units already polished live, in send order (preview = joined).
    private var livePolishedSentences: [String] = []
    /// Raw-text prefix already sent to the IA this session. The loop only
    /// ever sends `newTail` beyond this — each word goes once, in order.
    private var liveConsumedRaw = ""
    /// Debounce for unpunctuated speech (see polishStableTail).
    private var liveDebounceTask: Task<Void, Never>?
    /// Silence before the stable tail is sent. Internal for tests.
    var liveStabilityDelay: Duration = .seconds(3)
    /// Window-timer override for tests. When nil, the loop uses
    /// `liveWindowSeconds()` (Settings, default 10s).
    var liveWindowDelay: Duration?
    private let liveWindowSeconds: () -> Int

    init(
        dictation: any DictationService,
        clipboard: any Clipboard,
        store: TranscriptionStore,
        autoPaste: (any AutoPasteService)? = nil,
        polisher: (any TextPolisher)? = nil,
        isAutoPasteEnabled: @escaping () -> Bool = { false },
        isLivePolishEnabled: @escaping () -> Bool = { true },
        liveWindowSeconds: @escaping () -> Int = { 10 }
    ) {
        self.dictation = dictation
        self.clipboard = clipboard
        self.store = store
        self.autoPaste = autoPaste
        self.polisher = polisher
        self.isAutoPasteEnabled = isAutoPasteEnabled
        self.isLivePolishEnabled = isLivePolishEnabled
        self.liveWindowSeconds = liveWindowSeconds
        Task {
            await dictation.setPartialHandler { [weak self] text in
                Task { @MainActor in
                    self?.handlePartial(text)
                }
            }
            await dictation.setFailureHandler { [weak self] reason in
                Task { @MainActor in
                    guard let self, case .recording = self.state else { return }
                    self.state = .failed(reason)
                }
            }
            if let levelProvider = dictation as? AudioLevelProviding {
                await levelProvider.setLevelHandler { [weak self] level in
                    Task { @MainActor in
                        self?.pushLevel(level)
                    }
                }
            }
        }
    }

    private func pushLevel(_ level: Double) {
        levelSamples.removeFirst()
        levelSamples.append(max(0.06, min(1, level)))
    }

    /// Partial updates only matter while recording.
    /// Closed sentences go to the serial live-polish loop immediately; the
    /// debounce covers unpunctuated speech (Apple partials rarely carry
    /// `.?!` mid-speech) once the transcript stabilizes.
    private func handlePartial(_ text: String) {
        guard case .recording = state else { return }
        liveTranscript = text
        scheduleLivePolish(for: text)
        armLiveDebounce(for: text)
    }

    /// Immediate path: new stable content appeared. Sends only the part
    /// beyond `liveConsumedRaw` (a pause tail may already cover its head),
    /// with polished context as read-only intersection.
    private func scheduleLivePolish(for text: String) {
        guard livePolishOn, polisher?.isAvailable == true else { return }
        let (stable, _) = PolishPrompt.splitLive(text)
        guard !stable.isEmpty else { return }
        let region = stable.joined(separator: " ")
        let unit = PolishPrompt.newTail(current: region, since: liveConsumedRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty else { return }
        liveConsumedRaw = region.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueueLive(PolishPrompt.chunk(unit))
    }

    /// Pause fallback: when the transcript stops changing for
    /// `liveStabilityDelay`, polish the stable tail too. The word-diff dedups
    /// identical repeats — no resends, no per-syllable spam.
    private func armLiveDebounce(for text: String) {
        guard livePolishOn, polisher?.isAvailable == true else { return }
        liveDebounceTask?.cancel()
        liveDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.liveStabilityDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.polishStableTail(text)
        }
    }

    private func polishStableTail(_ snapshot: String) {
        guard case .recording = state, livePolishOn,
              polisher?.isAvailable == true else { return }
        let tail = PolishPrompt.newTail(current: snapshot, since: liveConsumedRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return }
        liveConsumedRaw = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueueLive(PolishPrompt.chunk(tail))
    }

    /// Window safety net: every N seconds, send any new tail even while the
    /// user is still speaking (no pause needed). Skips fragments too small to
    /// be worth a call; the already-polished text goes as read-only context
    /// (intersection) so the model keeps sense across windows.
    func polishWindowTick() {
        guard case .recording = state, livePolishOn,
              polisher?.isAvailable == true, !isPaused else { return }
        let snapshot = liveTranscript
        let tail = PolishPrompt.newTail(current: snapshot, since: liveConsumedRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty, PolishPrompt.isWindowWorthy(tail) else { return }
        liveConsumedRaw = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        enqueueLive(PolishPrompt.chunk(tail))
    }

    private func startLiveWindowLoop() {
        stopLiveWindowLoop()
        liveWindowTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let interval = await self.currentWindowInterval()
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                self.polishWindowTick()
            }
        }
    }

    private func currentWindowInterval() async -> Duration {
        if let override = liveWindowDelay { return override }
        let seconds = max(5, min(30, liveWindowSeconds()))
        return .seconds(seconds)
    }

    private func stopLiveWindowLoop() {
        liveWindowTask?.cancel()
        liveWindowTask = nil
    }

    /// Append units and run the serial loop (one IA call at a time, in order —
    /// no overlapping requests, no stale overwrite). Each unit carries the
    /// polished-so-far context snapshot as read-only intersection.
    private func enqueueLive(_ units: [String]) {
        guard !units.isEmpty else { return }
        let context = PolishPrompt.contextTail(from: livePolishedSentences)
        livePendingQueue.append(contentsOf: units.map { LiveUnit(text: $0, context: context) })
        guard livePolishTask == nil else { return }
        livePolishActive = true
        livePolishTask = Task { [weak self] in
            guard let self else { return }
            while let unit = await self.nextLiveSentence() {
                if Task.isCancelled { break }
                do {
                    let polished = try await self.polisher?.polish(unit.text, context: unit.context) ?? unit.text
                    await self.appendLivePolished(polished: polished)
                } catch let error as PolishError {
                    // Consumed already advanced at enqueue time, so a failed
                    // unit never resends live; the next window retries new words.
                    await self.setLivePolishError(error.message)
                } catch {
                    await self.setLivePolishError("Falha na limpeza com IA: \(error.localizedDescription)")
                }
            }
            await self.finishLivePolishLoop()
        }
    }

    private func nextLiveSentence() async -> LiveUnit? {
        guard !livePendingQueue.isEmpty else { return nil }
        return livePendingQueue.removeFirst()
    }

    private func appendLivePolished(polished: String) async {
        livePolishedSentences.append(PolishPrompt.clean(polished))
        livePolishedText = livePolishedSentences.joined(separator: " ")
        livePolishError = nil
    }

    private func setLivePolishError(_ message: String) async {
        livePolishError = message
    }

    private func finishLivePolishLoop() async {
        livePolishTask = nil
        livePolishActive = false
    }

    func toggle() {
        switch state {
        case .idle, .failed:
            startDictation()
        case .recording:
            finishDictation()
        case .transcribing:
            break
        }
    }

    func finish() {
        switch state {
        case .recording:
            finishDictation()
        default:
            break
        }
    }

    /// Copy icon in the live IA box: copies the polished-so-far text without
    /// closing or touching history — the committed transcription still goes
    /// through Finalizar (original text).
    func copyLivePolished() {
        guard case .recording = state else { return }
        let text = livePolishedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clipboard.copy(text)
    }

    func togglePause() {
        guard case .recording(let startedAt) = state else { return }
        if isPaused {
            let duration = Date().timeIntervalSince(pausedAt ?? Date())
            state = .recording(startedAt: startedAt.addingTimeInterval(duration))
            isPaused = false
            pausedAt = nil
            Task { [weak self] in
                await self?.dictation.resume()
            }
        } else {
            isPaused = true
            pausedAt = Date()
            Task { [weak self] in
                await self?.dictation.pause()
            }
        }
    }

    func cancel() {
        guard state != .idle else { return }
        Task {
            await dictation.cancel()
        }
        FocusRestorer.activate(pid: targetPID)
        targetPID = nil
        state = .idle
        isPaused = false
        pausedAt = nil
        liveTranscript = ""
        resetLivePolish()
    }

    /// Stop the serial loop and clear session state. Called on start (fresh
    /// session), cancel, and deliver.
    private func resetLivePolish() {
        livePolishTask?.cancel()
        livePolishTask = nil
        liveDebounceTask?.cancel()
        liveDebounceTask = nil
        stopLiveWindowLoop()
        livePendingQueue = []
        liveConsumedRaw = ""
        livePolishedSentences = []
        livePolishedText = ""
        livePolishActive = false
        livePolishError = nil
    }

    func copyToClipboard(_ text: String) {
        clipboard.copy(text)
    }

    func clearHistory() {
        Task {
            await store.clear()
            historyVersion += 1
        }
    }

    private func startDictation() {
        liveTranscript = ""
        isPaused = false
        pausedAt = nil
        resetLivePolish()
        // Live IA preview for closed sentences; off when the model can't run
        // or the user disabled it in Settings.
        livePolishOn = (polisher?.isAvailable == true) && isLivePolishEnabled()
        levelSamples = Array(repeating: 0.08, count: 12)
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        state = .recording(startedAt: Date())
        if livePolishOn { startLiveWindowLoop() }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await dictation.start()
            } catch let reason as FailureReason {
                state = .failed(reason)
            } catch {
                state = .failed(.engineError(error.localizedDescription))
            }
        }
    }

    /// Finish stops capture and delivers the ORIGINAL text immediately:
    /// copy + history + close + auto-paste. The live IA box is a preview
    /// with its own copy icon — it never blocks or replaces this path.
    /// The live-polish loop is stopped here.
    private func finishDictation() {
        guard case .recording = state else { return }
        livePolishOn = false
        livePolishTask?.cancel()
        livePolishTask = nil
        liveDebounceTask?.cancel()
        liveDebounceTask = nil
        stopLiveWindowLoop()
        livePendingQueue = []
        livePolishActive = false
        state = .transcribing
        Task { [weak self] in
            guard let self else { return }
            let serviceText = await dictation.finish()
            // The box on screen mirrors the service's accumulated text; if the
            // engine fails to deliver a final result, that text is still valid.
            let effective = serviceText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? liveTranscript
            await completeFinish(text: effective)
        }
    }

    /// Finish path: copy + history + close + auto-paste.
    private func deliver(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .failed(.noSpeech)
            return
        }
        clipboard.copy(trimmed)
        await store.add(trimmed)
        historyVersion += 1
        state = .idle
        let pid = targetPID
        targetPID = nil
        liveTranscript = ""
        resetLivePolish()
        if isAutoPasteEnabled(), let autoPaste {
            Task {
                await autoPaste.paste(into: pid)
            }
        }
    }

    private func completeFinish(text: String) async {
        await deliver(text: text)
    }
}
