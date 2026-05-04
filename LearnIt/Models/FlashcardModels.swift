import Foundation

struct Flashcard: Identifiable, Hashable, Codable {
    let id: String
    let front: String
    let back: String
    let topic: String
    let mnemonic: String?

    init(front: String, back: String, topic: String, mnemonic: String? = nil) {
        self.front = front
        self.back = back
        self.topic = topic
        self.mnemonic = mnemonic
        self.id = Self.makeID(front: front, back: back, topic: topic, mnemonic: mnemonic)
    }

    private static func makeID(front: String, back: String, topic: String, mnemonic: String?) -> String {
        let raw = [topic, front, back, mnemonic ?? ""].joined(separator: "\u{241F}")
        return StableHash.fnv1a64(raw)
    }
}

struct FlashcardDeck: Codable {
    var identifier: String
    var title: String
    var subtitle: String
    var sourceLabel: String
    var cards: [Flashcard]

    var topics: [String] {
        Array(Set(cards.map(\.topic))).sorted()
    }

    static let empty = FlashcardDeck(
        identifier: "empty",
        title: "AWS Certified Cloud Practitioner",
        subtitle: "Import a deck file to start studying.",
        sourceLabel: "None",
        cards: []
    )
}

enum DeckSourceKind: String, Codable {
    case bundled
    case imported
}

enum ImportedDeckFormat: String, Codable {
    case tsv
    case csv
    case json
    case markdown
    case plainText

    var displayName: String {
        switch self {
        case .tsv:
            return "TSV"
        case .csv:
            return "CSV"
        case .json:
            return "JSON"
        case .markdown:
            return "Markdown"
        case .plainText:
            return "Plain Text"
        }
    }
}

struct DeckLibraryItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var sourceLabel: String
    var kind: DeckSourceKind
    var storedDeckFilename: String?
    var importedFormat: ImportedDeckFormat?
    var bookmarkData: Data?

    var badgeLabel: String {
        switch kind {
        case .bundled:
            return "Bundled"
        case .imported:
            return "Imported"
        }
    }
}

struct StableHash {
    static func fnv1a64(_ string: String) -> String {
        let bytes = Array(string.utf8)
        var hash: UInt64 = 14695981039346656037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
