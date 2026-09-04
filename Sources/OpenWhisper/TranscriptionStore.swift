import Foundation
import os

struct Transcription: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
}

actor TranscriptionStore {
    private static let capacity = 50

    private let fileURL: URL
    private let logger = Logger(subsystem: "br.marcos.openwhisper", category: "store")
    private var entries: [Transcription] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    func add(_ text: String) {
        let entry = Transcription(id: UUID(), text: text, createdAt: Date())
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        persist()
    }

    func all() -> [Transcription] {
        entries
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("falha ao persistir histórico: \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> [Transcription] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([Transcription].self, from: data)
        } catch {
            Logger(subsystem: "br.marcos.openwhisper", category: "store")
                .error("histórico corrompido, iniciando vazio: \(error.localizedDescription)")
            return []
        }
    }
}
