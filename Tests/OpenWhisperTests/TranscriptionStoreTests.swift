import Foundation
import Testing

@testable import OpenWhisper

@Suite struct TranscriptionStoreTests {
    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    @Test func addInsertsNewestFirst() async {
        let store = TranscriptionStore(fileURL: makeURL())
        await store.add("primeira")
        await store.add("segunda")
        let all = await store.all()
        #expect(all.map(\.text) == ["segunda", "primeira"])
    }

    @Test func addCapsAtFiftyDroppingOldest() async {
        let store = TranscriptionStore(fileURL: makeURL())
        for i in 1...51 {
            await store.add("texto \(i)")
        }
        let all = await store.all()
        #expect(all.count == 50)
        #expect(all.first?.text == "texto 51")
        #expect(all.last?.text == "texto 2")
    }

    @Test func persistsAcrossInstances() async {
        let url = makeURL()
        let first = TranscriptionStore(fileURL: url)
        await first.add("oi mundo")
        let second = TranscriptionStore(fileURL: url)
        let all = await second.all()
        #expect(all.count == 1)
        #expect(all.first?.text == "oi mundo")
        #expect(all.first?.id != nil)
        #expect(all.first?.createdAt != nil)
    }

    @Test func clearRemovesAllAndPersists() async {
        let url = makeURL()
        let store = TranscriptionStore(fileURL: url)
        await store.add("algo")
        await store.clear()
        let all = await store.all()
        #expect(all.isEmpty)
        let reloaded = TranscriptionStore(fileURL: url)
        let reloadedAll = await reloaded.all()
        #expect(reloadedAll.isEmpty)
    }

    @Test func missingFileStartsEmpty() async {
        let store = TranscriptionStore(fileURL: makeURL())
        let all = await store.all()
        #expect(all.isEmpty)
    }

    @Test func corruptFileStartsEmpty() async {
        let url = makeURL()
        try? Data("{{{nao sou json".utf8).write(to: url)
        let store = TranscriptionStore(fileURL: url)
        let all = await store.all()
        #expect(all.isEmpty)
    }
}
