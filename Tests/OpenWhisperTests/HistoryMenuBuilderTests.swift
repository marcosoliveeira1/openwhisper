import Foundation
import Testing

@testable import OpenWhisper

@Suite struct HistoryMenuBuilderTests {
    private func entry(_ text: String) -> Transcription {
        Transcription(id: UUID(), text: text, createdAt: Date())
    }

    private func kinds(_ items: [MenuModel.Item]) -> [MenuModel.Item.Kind] {
        items.map(\.kind)
    }

    @Test func truncatesLongTextAtLimitWithEllipsis() {
        let long = String(repeating: "a", count: 80)
        let items = HistoryMenuBuilder.build(entries: [entry(long)])
        #expect(items[0].title == String(repeating: "a", count: 60) + "…")
        #expect(items[0].title.count == 61)
    }

    @Test func shortTextKeptWholeAndNewlinesFlattened() {
        let items = HistoryMenuBuilder.build(entries: [entry("linha um\nlinha dois")])
        #expect(items[0].title == "linha um linha dois")
        #expect(items[0].title == HistoryMenuBuilder.truncate("linha um\nlinha dois"))
    }

    @Test func orderingFollowsStoreOrderNewestFirst() {
        let newest = entry("mais recente")
        let oldest = entry("mais antiga")
        let items = HistoryMenuBuilder.build(entries: [newest, oldest])
        #expect(items[0].title == "mais recente")
        #expect(items[1].title == "mais antiga")
    }

    @Test func emptyHistoryShowsDisabledPlaceholderWithFixedItems() {
        let items = HistoryMenuBuilder.build(entries: [])
        #expect(items[0].title == "Sem transcrições")
        #expect(items[0].kind == .empty)
        #expect(kinds(items).count == 3)
        #expect(kinds(items).contains(.clear))
        #expect(kinds(items).contains(.quit))
    }

    @Test func fixedItemsAlwaysPresent() {
        let items = HistoryMenuBuilder.build(entries: [entry("texto")])
        #expect(kinds(items).contains(.clear))
        #expect(kinds(items).contains(.quit))
        #expect(items.last?.title == "Sair")
    }

    @Test func transcriptionItemCarriesFullTextAsPayload() {
        let full = String(repeating: "b", count: 100)
        let items = HistoryMenuBuilder.build(entries: [entry(full)])
        guard case .transcription(let payload) = items[0].kind else {
            Issue.record("primeiro item deveria ser transcrição")
            return
        }
        #expect(payload == full)
        #expect(payload.count == 100)
    }
}
