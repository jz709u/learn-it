import Foundation

enum TSVFlashcardParser {
    static func parse(contentsOf url: URL, sourceLabel: String) throws -> FlashcardDeck {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let lines = raw.components(separatedBy: .newlines)
        let identifier = StableHash.fnv1a64(raw)

        var cards: [Flashcard] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 3 else { continue }

            let front = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let topic = columns[2].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !front.isEmpty, !back.isEmpty, !topic.isEmpty else { continue }
            cards.append(Flashcard(front: front, back: back, topic: topic))
        }

        guard !cards.isEmpty else {
            throw NSError(
                domain: "TSVFlashcardParser",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No valid flashcards were found. Expected rows with front, back, and topic separated by tabs."]
            )
        }

        let title = cards.first?.topic == "Cloud Basics" ? "AWS Cloud Practitioner Deck" : "Imported Flashcard Deck"
        let subtitle = "Study \(cards.count) cards from a TSV deck."

        return FlashcardDeck(
            identifier: identifier,
            title: title,
            subtitle: subtitle,
            sourceLabel: sourceLabel,
            cards: cards
        )
    }
}
