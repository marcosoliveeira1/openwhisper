import Foundation
import Testing

@testable import OpenWhisper

final class MockDictationService: DictationService, @unchecked Sendable {
    var startError: FailureReason?
    var finishResult: String?
    var holdFinish = false

    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private(set) var partialHandler: (@Sendable (String) -> Void)?
    private var finishContinuation: CheckedContinuation<String?, Never>?

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async {
        partialHandler = handler
    }

    func emitPartial(_ text: String) {
        partialHandler?(text)
    }

    func start() async throws {
        if let startError {
            throw startError
        }
        startCount += 1
    }

    func finish() async -> String? {
        if holdFinish {
            return await withCheckedContinuation { continuation in
                finishContinuation = continuation
            }
        }
        return finishResult
    }

    func releaseFinish() {
        finishContinuation?.resume(returning: finishResult)
        finishContinuation = nil
    }

    func cancel() async {
        cancelCount += 1
    }
}

final class MockClipboard: Clipboard {
    private(set) var copied: [String] = []
    func copy(_ text: String) {
        copied.append(text)
    }
}

final class MockAutoPasteService: AutoPasteService, @unchecked Sendable {
    private(set) var pasteCount = 0
    private(set) var pastedPIDs: [pid_t] = []

    func paste(into pid: pid_t?) async {
        pasteCount += 1
        if let pid {
            pastedPIDs.append(pid)
        }
    }
}

@Suite @MainActor struct AppModelTests {
    private func makeStore() -> TranscriptionStore {
        TranscriptionStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")
        )
    }

    private func waitUntil(
        _ condition: @autoclosure () async -> Bool,
        timeout: Duration = .seconds(2)
    ) async {
        let deadline = ContinuousClock.now + timeout
        while await !condition() && ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    @Test func toggleFromIdleStartsRecording() async {
        let model = AppModel(dictation: MockDictationService(), clipboard: MockClipboard(), store: makeStore())
        await model.toggle()
        await waitUntil(model.state == .recording(startedAt: model.state.recordingStartedAt ?? Date()))
        if case .recording = model.state {} else {
            Issue.record("esperado recording, obtido \(model.state)")
        }
    }

    @Test func toggleDuringRecordingFinishesCopiesAndStores() async {
        let speech = MockDictationService()
        speech.finishResult = "olá mundo"
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: store)

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.toggle()
        await waitUntil(model.state == .idle)

        #expect(clipboard.copied == ["olá mundo"])
        let history = await store.all()
        #expect(history.map(\.text) == ["olá mundo"])
        #expect(model.state == .idle)
    }

    @Test func cancelDiscardsWithoutSideEffects() async {
        let speech = MockDictationService()
        speech.finishResult = "nunca deveria copiar"
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: store)

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.cancel()
        await waitUntil(speech.cancelCount == 1)

        #expect(clipboard.copied.isEmpty)
        let history = await store.all()
        #expect(history.isEmpty)
        #expect(model.state == .idle)
    }

    @Test func emptyTranscriptShowsNoSpeechWithoutSideEffects() async {
        let speech = MockDictationService()
        speech.finishResult = "   "
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: store)

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.finish()
        await waitUntil(model.state == .failed(.noSpeech))

        #expect(clipboard.copied.isEmpty)
        let history = await store.all()
        #expect(history.isEmpty)
    }

    @Test func toggleDuringTranscribingIsIgnored() async {
        let speech = MockDictationService()
        speech.holdFinish = true
        speech.finishResult = "texto"
        let model = AppModel(dictation: speech, clipboard: MockClipboard(), store: makeStore())

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.toggle()
        await waitUntil(model.state == .transcribing)

        await model.toggle()
        #expect(model.state == .transcribing)
        #expect(speech.startCount == 1)

        speech.releaseFinish()
        await waitUntil(model.state == .idle)
    }

    @Test func startFailureShowsPermissionDenied() async {
        let speech = MockDictationService()
        speech.startError = .permissionDenied
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: store)

        await model.toggle()
        await waitUntil(model.state == .failed(.permissionDenied))

        #expect(clipboard.copied.isEmpty)
        let history = await store.all()
        #expect(history.isEmpty)
    }

    @Test func toggleFromFailureRestartsRecording() async {
        let speech = MockDictationService()
        speech.startError = .permissionDenied
        let model = AppModel(dictation: speech, clipboard: MockClipboard(), store: makeStore())

        await model.toggle()
        await waitUntil(model.state == .failed(.permissionDenied))

        speech.startError = nil
        await model.toggle()
        await waitUntil(speech.startCount == 2)
        if case .recording = model.state {} else {
            Issue.record("esperado recording após retry, obtido \(model.state)")
        }
    }

    @Test func historyChangesPublishVersionBumps() async {
        let speech = MockDictationService()
        speech.finishResult = "texto novo"
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: MockClipboard(), store: store)

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.finish()
        await waitUntil(model.state == .idle)
        #expect(model.historyVersion == 1)

        model.clearHistory()
        await waitUntil(model.historyVersion == 2)
        let history = await store.all()
        #expect(history.isEmpty)
    }

    @Test func autoPasteEnabledPastesAfterFinish() async {
        let speech = MockDictationService()
        speech.finishResult = "cola isso"
        let paste = MockAutoPasteService()
        let model = AppModel(
            dictation: speech,
            clipboard: MockClipboard(),
            store: makeStore(),
            autoPaste: paste,
            isAutoPasteEnabled: { true }
        )

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.finish()
        await waitUntil(model.state == .idle)
        await waitUntil(paste.pasteCount == 1)

        #expect(paste.pasteCount == 1)
        #expect(model.state == .idle)
    }

    @Test func autoPasteDisabledSkipsPaste() async {
        let speech = MockDictationService()
        speech.finishResult = "não cola"
        let paste = MockAutoPasteService()
        let model = AppModel(
            dictation: speech,
            clipboard: MockClipboard(),
            store: makeStore(),
            autoPaste: paste,
            isAutoPasteEnabled: { false }
        )

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.finish()
        await waitUntil(model.state == .idle)

        #expect(paste.pasteCount == 0)
    }

    @Test func cancelNeverPastes() async {
        let speech = MockDictationService()
        let paste = MockAutoPasteService()
        let model = AppModel(
            dictation: speech,
            clipboard: MockClipboard(),
            store: makeStore(),
            autoPaste: paste,
            isAutoPasteEnabled: { true }
        )

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.cancel()
        await waitUntil(speech.cancelCount == 1)

        #expect(paste.pasteCount == 0)
    }

    @Test func copyToClipboardUsesClipboardService() async {
        let clipboard = MockClipboard()
        let model = AppModel(dictation: MockDictationService(), clipboard: clipboard, store: makeStore())
        model.copyToClipboard("do histórico")
        #expect(clipboard.copied == ["do histórico"])
    }

    @Test func clearHistoryEmptiesStore() async {
        let store = makeStore()
        await store.add("antigo")
        let model = AppModel(dictation: MockDictationService(), clipboard: MockClipboard(), store: store)

        model.clearHistory()
        let history = await store.all()
        await waitUntil(history.isEmpty)
    }

    @Test func cancelDuringTranscribingDiscardsEverything() async {
        let speech = MockDictationService()
        speech.holdFinish = true
        speech.finishResult = "deveria ser descartado"
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: store)

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.toggle()
        await waitUntil(model.state == .transcribing)
        await model.cancel()
        await waitUntil(speech.cancelCount == 1)

        speech.releaseFinish()
        await waitUntil(model.state == .idle)
        #expect(model.state == .idle)
        #expect(clipboard.copied.isEmpty)
        let history = await store.all()
        #expect(history.isEmpty)
    }

    @Test func finishOutsideRecordingIsNoOp() async {
        let speech = MockDictationService()
        speech.startError = .recognitionUnavailable
        let clipboard = MockClipboard()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: makeStore())

        await model.toggle()
        await waitUntil(model.state == .failed(.recognitionUnavailable))
        await model.finish()

        #expect(model.state == .failed(.recognitionUnavailable))
        #expect(clipboard.copied.isEmpty)
    }

    @Test func restartAfterCancelResetsLiveTranscript() async {
        let speech = MockDictationService()
        let model = AppModel(dictation: speech, clipboard: MockClipboard(), store: makeStore())

        await model.toggle()
        await waitUntil(speech.partialHandler != nil)
        speech.emitPartial("rascunho parcial")
        await waitUntil(model.liveTranscript == "rascunho parcial")

        await model.cancel()
        await waitUntil(model.state == .idle)

        await model.toggle()
        await waitUntil(speech.startCount == 2)
        await waitUntil(model.liveTranscript == "")
        #expect(model.liveTranscript == "")
    }

    @Test func interruptedDictationDeliversPartialOnFinish() async {
        let speech = MockDictationService()
        speech.finishResult = "últimas palavras"
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(dictation: speech, clipboard: clipboard, store: store)

        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await waitUntil(speech.partialHandler != nil)
        speech.emitPartial("últimas palavras")
        await waitUntil(model.liveTranscript == "últimas palavras")

        await model.finish()
        await waitUntil(model.state == .idle)

        #expect(clipboard.copied == ["últimas palavras"])
        let history = await store.all()
        #expect(history.map(\.text) == ["últimas palavras"])
    }
}

extension DictationState {
    var recordingStartedAt: Date? {
        if case .recording(let startedAt) = self { return startedAt }
        return nil
    }
}
