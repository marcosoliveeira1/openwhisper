import Foundation

struct MenuModel: Equatable {
    struct Item: Equatable {
        enum Kind: Equatable {
            case transcription(text: String)
            case empty
            case clear
            case settings
            case about
            case quit
        }

        let title: String
        let kind: Kind
    }

    let items: [Item]
}

enum HistoryMenuBuilder {
    static let labelLimit = 60

    static func build(entries: [Transcription]) -> [MenuModel.Item] {
        var items: [MenuModel.Item] = []
        if entries.isEmpty {
            items.append(MenuModel.Item(title: "Sem transcrições", kind: .empty))
        } else {
            for entry in entries {
                items.append(MenuModel.Item(title: truncate(entry.text), kind: .transcription(text: entry.text)))
            }
        }
        items.append(MenuModel.Item(title: "Limpar histórico", kind: .clear))
        items.append(MenuModel.Item(title: "Configurações…", kind: .settings))
        items.append(MenuModel.Item(title: "Sobre OpenWhisper", kind: .about))
        items.append(MenuModel.Item(title: "Sair", kind: .quit))
        return items
    }

    static func truncate(_ text: String, limit: Int = labelLimit) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }
}
