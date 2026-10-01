import Foundation
import Testing

@testable import OpenWhisper

final class MockPolisher: TextPolisher, @unchecked Sendable {
    var available = true
    var unavailableMessage: String? = "modelo indisponível"
    var result: String?
    var failure: PolishError?
    private(set) var polishedInputs: [String] = []
    private(set) var polishedContexts: [String] = []
    var delay: Duration = .zero

    var isAvailable: Bool { available }
    var availabilityMessage: String? { available ? nil : unavailableMessage }

    func polish(_ text: String) async throws -> String {
        try await polish(text, context: "")
    }

    func polish(_ text: String, context: String) async throws -> String {
        polishedInputs.append(text)
        polishedContexts.append(context)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let failure { throw failure }
        return result ?? text
    }
}

@Suite @MainActor struct PolishPromptTests {
    @Test func cleanStripsWrappingQuotes() {
        #expect(PolishPrompt.clean("\"Olá mundo.\"") == "Olá mundo.")
    }

    @Test func cleanTrimsWhitespace() {
        #expect(PolishPrompt.clean("\n  texto limpo  \n") == "texto limpo")
    }

    @Test func cleanLeavesPlainTextAlone() {
        #expect(PolishPrompt.clean("fazer deploy do endpoint") == "fazer deploy do endpoint")
    }

    @Test func promptWrapsInputWithDelimiters() {
        let prompt = PolishPrompt.prompt(for: "alô testando")
        #expect(prompt.contains("alô testando"))
        #expect(prompt.contains("---"))
        #expect(prompt.contains("ONLY the corrected text"))
    }

    @Test func plausibleAcceptsRealCleanup() {
        #expect(PolishPrompt.isPlausible("Fazer deploy do endpoint.", for: "fazer deploi do endpointe"))
        #expect(PolishPrompt.isPlausible("Alô.", for: "Alô"))
        #expect(PolishPrompt.isPlausible("Alô, testando.", for: "alô testando"))
    }

    @Test func plausibleRejectsChattyHallucination() {
        // The reported live failure: 2 spoken words → 8-word echo + junk.
        #expect(!PolishPrompt.isPlausible(
            "Alô, testando the transcription, 23, alô, testing.", for: "alô testando"
        ))
        #expect(!PolishPrompt.isPlausible("Como posso ajudar você hoje?", for: "alô"))
        #expect(!PolishPrompt.isPlausible("", for: "alô testando"))
        #expect(!PolishPrompt.isPlausible("texto", for: ""))
    }

    @Test func chunkKeepsShortTextWhole() {
        #expect(PolishPrompt.chunk("texto curto") == ["texto curto"])
    }

    @Test func chunkSplitsLongTextOnSentences() {
        let long = String(repeating: "Frase completa aqui. ", count: 200)
        let chunks = PolishPrompt.chunk(long)
        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.count <= PolishPrompt.maxChunkChars)
        }
        // Nothing lost: joined words match the original words.
        let originalWords = long.split(separator: " ", omittingEmptySubsequences: true)
        let joinedWords = chunks.joined(separator: " ").split(separator: " ", omittingEmptySubsequences: true)
        #expect(joinedWords == originalWords)
    }

    @Test func joinConcatenatesWithSpaces() {
        #expect(PolishPrompt.join(["a.", "b."]) == "a. b.")
    }

    @Test func splitLiveSeparatesStableAndPending() {
        let (stable, pending) = PolishPrompt.splitLive("Primeira frase. Segunda incompleta")
        #expect(stable == ["Primeira frase."])
        #expect(pending == "Segunda incompleta")
    }

    @Test func splitLiveAllClosedLeavesNoPending() {
        let (stable, pending) = PolishPrompt.splitLive("Uma. Duas? Três!")
        #expect(stable == ["Uma.", "Duas?", "Três!"])
        #expect(pending == "")
    }

    @Test func splitLiveNoTerminatorIsAllPending() {
        let (stable, pending) = PolishPrompt.splitLive("falando ainda sem ponto")
        #expect(stable.isEmpty)
        #expect(pending == "falando ainda sem ponto")
    }

    @Test func splitLiveEmptyText() {
        let (stable, pending) = PolishPrompt.splitLive("")
        #expect(stable.isEmpty)
        #expect(pending == "")
    }

    @Test func newTailReturnsWholeTextWhenNothingSent() {
        #expect(PolishPrompt.newTail(current: "ola mundo", since: "") == "ola mundo")
    }

    @Test func newTailReturnsOnlyNewSuffix() {
        #expect(PolishPrompt.newTail(current: "ola mundo tudo bem", since: "ola mundo") == "tudo bem")
    }

    @Test func newTailEmptyWhenNothingNew() {
        #expect(PolishPrompt.newTail(current: "ola mundo", since: "ola mundo") == "")
        #expect(PolishPrompt.newTail(current: "ola mundo", since: "ola mundo extra?") == "")
    }

    @Test func newTailRestartsAfterDivergence() {
        #expect(PolishPrompt.newTail(current: "ola planeta", since: "ola mundo") == "planeta")
    }

    @Test func promptWithContextEmptyFallsBackToPlain() {
        #expect(PolishPrompt.promptWithContext("alô testando", context: "") == PolishPrompt.prompt(for: "alô testando"))
        #expect(PolishPrompt.promptWithContext("alô testando", context: "  \n ") == PolishPrompt.prompt(for: "alô testando"))
    }

    @Test func promptWithContextIncludesBothAndGuard() {
        let prompt = PolishPrompt.promptWithContext("parte nova aqui", context: "Frase anterior polida.")
        #expect(prompt.contains("parte nova aqui"))
        #expect(prompt.contains("Frase anterior polida."))
        #expect(prompt.contains("do NOT repeat"))
    }

    @Test func contextTailEmptyWhenNothingPolished() {
        #expect(PolishPrompt.contextTail(from: []) == "")
        #expect(PolishPrompt.contextTail(from: [], maxChars: 100) == "")
    }

    @Test func contextTailReturnsAllWhenShort() {
        #expect(PolishPrompt.contextTail(from: ["Primeira.", "Segunda?"]) == "Primeira. Segunda?")
    }

    @Test func contextTailTruncatesLongHistory() {
        let long = String(repeating: "palavra ", count: 100)
        let tail = PolishPrompt.contextTail(from: [long])
        #expect(tail.count <= 300)
        #expect(long.hasSuffix(tail))
    }

    @Test func contextTailZeroMaxCharsIsEmpty() {
        #expect(PolishPrompt.contextTail(from: ["Algo."], maxChars: 0) == "")
    }

    @Test func isWindowWorthyRejectsFragments() {
        #expect(!PolishPrompt.isWindowWorthy(""))
        #expect(!PolishPrompt.isWindowWorthy("oi"))
        #expect(!PolishPrompt.isWindowWorthy("falando ainda"))
        #expect(!PolishPrompt.isWindowWorthy("ola mundo"))
    }

    @Test func isWindowWorthyAcceptsRealSpeech() {
        #expect(PolishPrompt.isWindowWorthy("ola mundo sem ponto"))
        #expect(PolishPrompt.isWindowWorthy("vou fazer o deploy do endpoint amanhã"))
    }
}

@Suite @MainActor struct PolishFlowTests {
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

    @Test func finishCopiesOriginalDirectlyAndCloses() async {
        let speech = MockDictationService()
        speech.finishResult = "fazer deploi do endpointe"
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(
            dictation: speech, clipboard: clipboard, store: store,
            polisher: MockPolisher()
        )
        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await model.finish()
        await waitUntil(model.state == .idle)
        // No review screen: the ORIGINAL text is copied, stored, done.
        #expect(clipboard.copied == ["fazer deploi do endpointe"])
        let history = await store.all()
        #expect(history.map(\.text) == ["fazer deploi do endpointe"])
    }

    @Test func copyLivePolishedCopiesWithoutClosing() async {
        let polisher = MockPolisher()
        polisher.result = "Fazer deploy."
        let speech = MockDictationService()
        let clipboard = MockClipboard()
        let store = makeStore()
        let model = AppModel(
            dictation: speech, clipboard: clipboard, store: store, polisher: polisher
        )
        await model.toggle()
        await waitUntil(speech.partialHandler != nil)
        speech.emitPartial("fazer deploi.")
        await waitUntil(model.livePolishedText == "Fazer deploy.")

        await model.copyLivePolished()
        #expect(clipboard.copied == ["Fazer deploy."])
        // Stays recording, no history — the committed text goes via Finalizar.
        guard case .recording = model.state else {
            Issue.record("esperado recording, obtido \(model.state)")
            return
        }
        let history = await store.all()
        #expect(history.isEmpty)
        await model.cancel()
    }

    @Test func copyLivePolishedEmptyDoesNothing() async {
        let speech = MockDictationService()
        let clipboard = MockClipboard()
        let model = AppModel(
            dictation: speech, clipboard: clipboard, store: makeStore(),
            polisher: MockPolisher()
        )
        await model.toggle()
        await waitUntil(speech.partialHandler != nil)
        await model.copyLivePolished()
        #expect(clipboard.copied.isEmpty)
        await model.cancel()
    }
}

@Suite @MainActor struct LivePolishTests {
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

    private func recordingModel(
        polisher: MockPolisher = MockPolisher(),
        liveEnabled: Bool = true,
        windowDelay: Duration? = nil
    ) async -> (AppModel, MockDictationService, MockPolisher) {
        let speech = MockDictationService()
        let model = AppModel(
            dictation: speech, clipboard: MockClipboard(), store: makeStore(),
            polisher: polisher, isLivePolishEnabled: { liveEnabled }
        )
        model.liveWindowDelay = windowDelay
        await model.toggle()
        await waitUntil(speech.startCount == 1)
        await waitUntil(speech.partialHandler != nil)
        return (model, speech, polisher)
    }

    @Test func openFragmentNeverGoesToIA() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("falando ainda sem ponto")
        await waitUntil(model.liveTranscript == "falando ainda sem ponto")
        // Give the loop a chance to (incorrectly) fire.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(polisher.polishedInputs.isEmpty)
        #expect(model.livePolishedText == "")
        await model.cancel()
    }

    @Test func closedSentenceIsPolishedOnce() async {
        let polisher = MockPolisher()
        polisher.result = "Fazer deploy."
        let (model, speech, _) = await recordingModel(polisher: polisher)
        speech.emitPartial("fazer deploi.")
        await waitUntil(model.livePolishedText == "Fazer deploy.")
        #expect(polisher.polishedInputs == ["fazer deploi."])
        // Same sentence repeated in later partials is NOT re-sent.
        speech.emitPartial("fazer deploi. e mais coisa")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(polisher.polishedInputs == ["fazer deploi."])
        await model.cancel()
    }

    @Test func secondSentenceAppendsInOrder() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("Primeira.")
        await waitUntil(polisher.polishedInputs == ["Primeira."])
        speech.emitPartial("Primeira. Segunda?")
        await waitUntil(model.livePolishedText == "Primeira. Segunda?")
        #expect(polisher.polishedInputs == ["Primeira.", "Segunda?"])
        await model.cancel()
    }

    @Test func liveOffSendsNothing() async {
        let (model, speech, polisher) = await recordingModel(liveEnabled: false)
        #expect(model.livePolishOn == false)
        speech.emitPartial("Frase fechada. Outra.")
        await waitUntil(model.liveTranscript == "Frase fechada. Outra.")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(polisher.polishedInputs.isEmpty)
        #expect(model.livePolishedText == "")
        await model.cancel()
    }

    @Test func unavailablePolisherDisablesLive() async {
        let polisher = MockPolisher()
        polisher.available = false
        let (model, speech, _) = await recordingModel(polisher: polisher)
        #expect(model.livePolishOn == false)
        speech.emitPartial("Frase fechada.")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.livePolishedText == "")
        await model.cancel()
    }

    @Test func liveErrorSurfacesWithoutWedgingLoop() async {
        let polisher = MockPolisher()
        polisher.failure = .failed("timeout")
        let (model, speech, _) = await recordingModel(polisher: polisher)
        speech.emitPartial("Primeira.")
        await waitUntil(model.livePolishError != nil)
        #expect(model.livePolishedText == "")
        // Loop still processes the next sentence after a failure.
        polisher.failure = nil
        speech.emitPartial("Primeira. Segunda.")
        await waitUntil(model.livePolishedText == "Segunda.")
        await model.cancel()
    }

    @Test func stablePausePolishesUnpunctuatedTail() async {
        let (model, speech, polisher) = await recordingModel()
        model.liveStabilityDelay = .milliseconds(50)
        speech.emitPartial("ola mundo sem ponto")
        await waitUntil(model.livePolishedText == "ola mundo sem ponto")
        #expect(polisher.polishedInputs == ["ola mundo sem ponto"])
        await model.cancel()
    }

    @Test func identicalRepeatAfterPauseSendsNothing() async {
        let (model, speech, polisher) = await recordingModel()
        model.liveStabilityDelay = .milliseconds(50)
        speech.emitPartial("ola mundo")
        await waitUntil(model.livePolishedText == "ola mundo")
        speech.emitPartial("ola mundo")
        try? await Task.sleep(for: .milliseconds(150))
        #expect(polisher.polishedInputs == ["ola mundo"])
        await model.cancel()
    }

    @Test func pauseThenPunctuatedContinuesWithoutOverlap() async {
        let (model, speech, polisher) = await recordingModel()
        model.liveStabilityDelay = .milliseconds(50)
        speech.emitPartial("ola mundo")
        await waitUntil(model.livePolishedText == "ola mundo")
        speech.emitPartial("ola mundo tudo bem.")
        await waitUntil(model.livePolishedText == "ola mundo tudo bem.")
        // Pause tail + only the new part — "ola mundo" polished once.
        #expect(polisher.polishedInputs == ["ola mundo", "tudo bem."])
        await model.cancel()
    }

    @Test func windowTickSendsTailWithoutPause() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("vou fazer o deploy do endpoint amanhã")
        await waitUntil(model.liveTranscript == "vou fazer o deploy do endpoint amanhã")
        await model.polishWindowTick()
        await waitUntil(model.livePolishedText == "vou fazer o deploy do endpoint amanhã")
        #expect(polisher.polishedInputs == ["vou fazer o deploy do endpoint amanhã"])
        await model.cancel()
    }

    @Test func windowTickSkipsTinyFragment() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("oi")
        await waitUntil(model.liveTranscript == "oi")
        await model.polishWindowTick()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(polisher.polishedInputs.isEmpty)
        await model.cancel()
    }

    @Test func windowTickSendsNothingWhenNothingNew() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("vou fazer o deploy do endpoint amanhã")
        await waitUntil(model.liveTranscript == "vou fazer o deploy do endpoint amanhã")
        await model.polishWindowTick()
        await waitUntil(polisher.polishedInputs.count == 1)
        await model.polishWindowTick()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(polisher.polishedInputs.count == 1)
        await model.cancel()
    }

    @Test func windowTickCarriesPriorContext() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("Primeira frase fechada.")
        await waitUntil(model.livePolishedText == "Primeira frase fechada.")
        #expect(polisher.polishedContexts.first == "")
        speech.emitPartial("Primeira frase fechada. continuando o raciocínio sem ponto final")
        await waitUntil(model.liveTranscript == "Primeira frase fechada. continuando o raciocínio sem ponto final")
        await model.polishWindowTick()
        await waitUntil(polisher.polishedInputs.count == 2)
        #expect(polisher.polishedInputs[1] == "continuando o raciocínio sem ponto final")
        #expect(polisher.polishedContexts[1] == "Primeira frase fechada.")
        await model.cancel()
    }

    @Test func windowTickSkippedWhenPaused() async {
        let (model, speech, polisher) = await recordingModel()
        speech.emitPartial("vou fazer o deploy do endpoint amanhã")
        await waitUntil(model.liveTranscript == "vou fazer o deploy do endpoint amanhã")
        await model.togglePause()
        await model.polishWindowTick()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(polisher.polishedInputs.isEmpty)
        await model.cancel()
    }

    @Test func windowLoopFiresAutomatically() async {
        let (model, speech, polisher) = await recordingModel(windowDelay: .milliseconds(50))
        speech.emitPartial("vou fazer o deploy do endpoint amanhã de manhã")
        await waitUntil(!polisher.polishedInputs.isEmpty, timeout: .seconds(3))
        #expect(polisher.polishedInputs == ["vou fazer o deploy do endpoint amanhã de manhã"])
        await model.cancel()
    }

    @Test func windowLoopStoppedOnFinish() async {
        let (model, speech, polisher) = await recordingModel(windowDelay: .milliseconds(50))
        speech.finishResult = "texto final aqui agora"
        await model.finish()
        await waitUntil(model.state == .idle)
        // Loop must not fire after finish — no live sends on the final text.
        #expect(polisher.polishedInputs.isEmpty)
    }
}
