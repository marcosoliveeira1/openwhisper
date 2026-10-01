import Foundation

/// Error from on-demand AI cleanup of a transcript.
enum PolishError: Error, Equatable {
    case unavailable(String)
    case failed(String)

    var message: String {
        switch self {
        case .unavailable(let reason):
            reason
        case .failed(let detail):
            "Falha na limpeza com IA: \(detail)"
        }
    }
}

/// On-demand transcript cleanup (punctuation, code-switched EN terms).
/// Implemented by FoundationModelsPolisher on macOS 26+; nil elsewhere.
protocol TextPolisher: Sendable {
    /// False when the underlying model can't run (wrong OS, disabled, downloading).
    var isAvailable: Bool { get }
    /// Human-readable reason when `isAvailable` is false.
    var availabilityMessage: String? { get }
    func polish(_ text: String) async throws -> String
    /// Live-window variant: `context` is already-polished text sent as
    /// read-only reference (never rewritten) so the model resolves pronouns,
    /// tense, and sentence boundaries. Default ignores it.
    func polish(_ text: String, context: String) async throws -> String
}

extension TextPolisher {
    func polish(_ text: String, context: String) async throws -> String {
        try await polish(text)
    }
}

/// Prompt + output cleanup. Pure, so it's unit-testable without the model.
enum PolishPrompt {
    /// Max chars per IA call — keeps each request inside the on-device
    /// model's comfortable window and bounds latency per batch.
    static let maxChunkChars = 2000

    static let instructions = """
        You are a transcription cleanup assistant. The user dictates in Brazilian Portuguese \
        mixed with English technical terms (code-switching, e.g. "fazer deploy", "dar pull request", \
        "o endpoint").
        Fix mistranscribed English terms to their correct English spelling, and fix punctuation \
        and capitalization.
        Preserve the original language of each word — do NOT translate Portuguese to English or vice versa.
        Do NOT add, remove, or reorder content. If the text is already correct, return it unchanged.
        Output ONLY the corrected text, with no quotes, no preamble, and no explanation.
        """

    /// Per-call prompt: the input is delimited so the model treats it as data
    /// to correct (not a message to chat back to), and the task is restated
    /// every call because each call runs on a fresh session.
    static func prompt(for text: String) -> String {
        """
        Correct the transcription between the --- markers. Return ONLY the corrected text.
        ---
        \(text)
        ---
        """
    }

    /// Window prompt with read-only intersection: `context` is already-polished
    /// text from the previous window(s). The model must use it only to resolve
    /// ambiguity — never repeat or rewrite it. Empty context falls back to
    /// the plain prompt.
    static func promptWithContext(_ text: String, context: String) -> String {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else { return prompt(for: text) }
        return """
            Previous polished text (context ONLY — do NOT repeat or rewrite it, \
            use it only to resolve pronouns, tense, and sentence boundaries).
            ---
            \(trimmedContext)
            ---
            Correct the transcription between the --- markers. Return ONLY the corrected text.
            ---
            \(text)
            ---
            """
    }

    /// Suffix of already-polished sentences for the next window's context.
    /// Append-only preview never rewrites, so this is just a bounded tail
    /// (default ~300 chars) — enough for sense, small for latency/cost.
    static func contextTail(from polished: [String], maxChars: Int = 300) -> String {
        guard !polished.isEmpty, maxChars > 0 else { return "" }
        let joined = polished.joined(separator: " ")
        guard joined.count > maxChars else { return joined }
        let suffix = joined.suffix(maxChars)
        // Avoid starting mid-word: cut at the first space when possible.
        if let space = suffix.firstIndex(of: " ") {
            return String(suffix[suffix.index(after: space)...])
        }
        return String(suffix)
    }

    /// Minimum size for a timer-window send. Below this the tail is likely a
    /// syllable/fragment the next partial will revise — skip it.
    static func isWindowWorthy(_ tail: String) -> Bool {
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 15 else { return false }
        return trimmed.split(separator: " ", omittingEmptySubsequences: true).count >= 3
    }

    /// Plausibility guard: real cleanup only fixes spelling/punctuation, so
    /// the word count barely moves. A response far outside that band is the
    /// model chatting back or hallucinating — reject it. Pure, unit-testable.
    static func isPlausible(_ output: String, for input: String) -> Bool {
        let inWords = input.split(separator: " ", omittingEmptySubsequences: true).count
        let outWords = output.split(separator: " ", omittingEmptySubsequences: true).count
        guard inWords > 0, outWords > 0 else { return false }
        let ratio = Double(outWords) / Double(inWords)
        return ratio >= 0.5 && ratio <= 2.0
    }

    /// Split long transcripts into sentence-safe batches for sequential IA calls.
    static func chunk(_ text: String) -> [String] {
        guard text.count > maxChunkChars else { return [text] }
        var chunks: [String] = []
        var current = ""
        // Split on sentence-ish boundaries; fall back to words for long runs.
        let sentences = text.components(separatedBy: ". ")
        for (index, sentence) in sentences.enumerated() {
            var piece = sentence
            if index < sentences.count - 1 { piece += ". " }
            if current.count + piece.count > maxChunkChars, !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
            if piece.count > maxChunkChars {
                // Single overlong sentence: hard-split on words.
                for word in piece.split(separator: " ", omittingEmptySubsequences: true) {
                    if current.count + word.count + 1 > maxChunkChars, !current.isEmpty {
                        chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                        current = ""
                    }
                    current += current.isEmpty ? String(word) : " " + word
                }
            } else {
                current += piece
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks.isEmpty ? [text] : chunks
    }

    static func join(_ chunks: [String]) -> String {
        chunks.joined(separator: " ")
    }

    /// Split streaming dictation into closed sentences (stable — safe to send
    /// to the IA) and a trailing open fragment (still being spoken — never
    /// polish this; it changes with every partial and causes "confused" output).
    /// A sentence closes on `.`, `?` or `!`. Pure, unit-testable.
    static func splitLive(_ text: String) -> (stable: [String], pending: String) {
        var stable: [String] = []
        var start = text.startIndex
        var index = text.startIndex
        let terminators: Set<Character> = [".", "?", "!"]
        while index < text.endIndex {
            if terminators.contains(text[index]) {
                let sentence = String(text[start...index])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { stable.append(sentence) }
                start = text.index(after: index)
            }
            index = text.index(after: index)
        }
        let pending = start < text.endIndex
            ? String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (stable, pending)
    }

    /// Word-level diff for live polish: the suffix of `current` beyond the
    /// longest common word-prefix with `sent`. Dictation partials are
    /// append-mostly, so this is the new content not yet sent to the IA.
    /// Identical repeats diff to "" — natural dedup, no resends.
    /// Pure, unit-testable.
    static func newTail(current: String, since sent: String) -> String {
        let currentWords = current.split(separator: " ", omittingEmptySubsequences: true)
        let sentWords = sent.split(separator: " ", omittingEmptySubsequences: true)
        var common = 0
        while common < currentWords.count, common < sentWords.count,
              currentWords[common] == sentWords[common] {
            common += 1
        }
        return currentWords.dropFirst(common).joined(separator: " ")
    }

    /// Defensively strip wrappers the model sometimes adds (quotes, extra blank lines).
    static func clean(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
