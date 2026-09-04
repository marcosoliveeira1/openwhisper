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
    @Published private(set) var historyVersion = 0
    @Published private(set) var levelSamples: [Double] = Array(repeating: 0.08, count: 12)

    private let dictation: any DictationService
    private let clipboard: any Clipboard
    private let store: TranscriptionStore
    private let autoPaste: (any AutoPasteService)?
    private let isAutoPasteEnabled: () -> Bool
    private var targetPID: pid_t?

    init(
        dictation: any DictationService,
        clipboard: any Clipboard,
        store: TranscriptionStore,
        autoPaste: (any AutoPasteService)? = nil,
        isAutoPasteEnabled: @escaping () -> Bool = { false }
    ) {
        self.dictation = dictation
        self.clipboard = clipboard
        self.store = store
        self.autoPaste = autoPaste
        self.isAutoPasteEnabled = isAutoPasteEnabled
        Task {
            await dictation.setPartialHandler { [weak self] text in
                Task { @MainActor in
                    self?.liveTranscript = text
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
        finishDictation()
    }

    func cancel() {
        guard state != .idle else { return }
        Task {
            await dictation.cancel()
        }
        FocusRestorer.activate(pid: targetPID)
        targetPID = nil
        state = .idle
        liveTranscript = ""
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
        levelSamples = Array(repeating: 0.08, count: 12)
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        state = .recording(startedAt: Date())
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

    private func finishDictation() {
        guard case .recording = state else { return }
        state = .transcribing
        Task { [weak self] in
            guard let self else { return }
            let text = await dictation.finish()
            await completeFinish(text: text ?? "")
        }
    }

    private func completeFinish(text: String) async {
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
        if isAutoPasteEnabled(), let autoPaste {
            Task {
                await autoPaste.paste(into: pid)
            }
        }
    }
}
