import Foundation

struct SegmentTranscript: Equatable, Sendable {
    private(set) var finalizedPrefix = ""

    func combined(_ current: String) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return finalizedPrefix }
        guard !finalizedPrefix.isEmpty else { return trimmed }
        return finalizedPrefix + " " + trimmed
    }

    mutating func finalize(with current: String) {
        finalizedPrefix = combined(current)
    }

    mutating func reset() {
        finalizedPrefix = ""
    }
}
