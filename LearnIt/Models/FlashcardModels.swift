import Foundation

struct Flashcard: Identifiable, Hashable, Codable {
    let id: String
    let front: String
    let back: String
    let topic: String

    init(front: String, back: String, topic: String) {
        self.front = front
        self.back = back
        self.topic = topic
        self.id = Self.makeID(front: front, back: back, topic: topic)
    }

    private static func makeID(front: String, back: String, topic: String) -> String {
        let raw = [topic, front, back].joined(separator: "\u{241F}")
        return StableHash.fnv1a64(raw)
    }
}

struct FlashcardDeck {
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
        subtitle: "Import a TSV deck to start studying.",
        sourceLabel: "None",
        cards: []
    )
}

enum DeckSourceKind: String, Codable {
    case bundled
    case imported
}

struct DeckLibraryItem: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var sourceLabel: String
    var kind: DeckSourceKind
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
