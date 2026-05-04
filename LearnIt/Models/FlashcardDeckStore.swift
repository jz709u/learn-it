import Foundation

final class FlashcardDeckStore: ObservableObject {
    @Published private(set) var importError: String?
    @Published private(set) var libraryItems: [DeckLibraryItem] = []

    private let defaults = UserDefaults.standard
    private let bundledDeckID = "bundled.aws-cloud-practitioner"

    init() {
        loadLibrary()
    }

    func saveImportedDeck(_ deck: FlashcardDeck, sourceLabel: String, format: ImportedDeckFormat) throws {
        let filename = "\(deck.identifier).json"
        let fileURL = try decksDirectoryURL()
            .appending(path: filename, directoryHint: .notDirectory)
        let data = try JSONEncoder().encode(deck)
        try data.write(to: fileURL, options: .atomic)

        let item = DeckLibraryItem(
            id: deck.identifier,
            title: deck.title,
            subtitle: deck.subtitle,
            sourceLabel: sourceLabel,
            kind: .imported,
            storedDeckFilename: filename,
            importedFormat: format,
            bookmarkData: nil
        )
        upsertLibraryItem(item)
    }

    func loadDeck(for item: DeckLibraryItem) throws -> FlashcardDeck {
        switch item.kind {
        case .bundled:
            return try loadBundledDeck()
        case .imported:
            return try loadImportedDeck(for: item)
        }
    }

    func loadReviewStates(for deckID: String) -> [String: ReviewState] {
        guard let data = defaults.data(forKey: persistenceKey(for: deckID)),
              let decoded = try? JSONDecoder().decode([String: ReviewState].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func persistReviewStates(_ reviewStates: [String: ReviewState], for deckID: String) {
        do {
            let data = try JSONEncoder().encode(reviewStates)
            defaults.set(data, forKey: persistenceKey(for: deckID))
        } catch {
            presentImportError("Could not save spaced repetition progress.")
        }
    }

    func clearReviewStates(for deckID: String) {
        defaults.removeObject(forKey: persistenceKey(for: deckID))
    }

    func deleteDeck(_ item: DeckLibraryItem) throws {
        guard item.kind == .imported else {
            throw NSError(
                domain: "FlashcardDeckStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Bundled decks cannot be deleted."]
            )
        }

        if let storedDeckFilename = item.storedDeckFilename {
            let fileURL = try decksDirectoryURL()
                .appending(path: storedDeckFilename, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: fileURL.path()) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }

        libraryItems.removeAll { $0.id == item.id }
        clearReviewStates(for: item.id)
        persistLibrary()
    }

    func cardCount(for item: DeckLibraryItem) -> Int {
        (try? loadDeck(for: item).cards.count) ?? 0
    }

    func dueCount(for item: DeckLibraryItem) -> Int {
        guard let deck = try? loadDeck(for: item) else { return 0 }
        let reviewStates = loadReviewStates(for: item.id)
        return deck.cards.filter { reviewStates[$0.id]?.isDue(at: .now) ?? true }.count
    }

    func newCount(for item: DeckLibraryItem) -> Int {
        guard let deck = try? loadDeck(for: item) else { return 0 }
        let reviewStates = loadReviewStates(for: item.id)
        return deck.cards.filter { reviewStates[$0.id] == nil }.count
    }

    func presentImportError(_ message: String) {
        importError = message
    }

    func dismissImportError() {
        importError = nil
    }

    private func loadLibrary() {
        let savedItems: [DeckLibraryItem]

        if let data = defaults.data(forKey: libraryPersistenceKey),
           let decoded = try? JSONDecoder().decode([DeckLibraryItem].self, from: data) {
            savedItems = decoded
        } else {
            savedItems = []
        }

        let bundled = DeckLibraryItem(
            id: bundledDeckID,
            title: "AWS Cloud Practitioner Deck",
            subtitle: "Study 167 cards from a TSV deck.",
            sourceLabel: "Bundled",
            kind: .bundled,
            storedDeckFilename: nil,
            importedFormat: .tsv,
            bookmarkData: nil
        )

        let imported = savedItems.filter { $0.kind == .imported }
        libraryItems = [bundled] + imported.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func upsertLibraryItem(_ item: DeckLibraryItem) {
        if let index = libraryItems.firstIndex(where: { $0.id == item.id }) {
            libraryItems[index] = item
        } else {
            libraryItems.append(item)
        }

        libraryItems.sort { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .bundled
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        persistLibrary()
    }

    private func persistLibrary() {
        do {
            let imported = libraryItems.filter { $0.kind == .imported }
            let data = try JSONEncoder().encode(imported)
            defaults.set(data, forKey: libraryPersistenceKey)
        } catch {
            presentImportError("Could not save the deck library.")
        }
    }

    private func loadBundledDeck() throws -> FlashcardDeck {
        guard let url = Bundle.main.url(forResource: "aws-cloud-practitioner-flashcards", withExtension: "tsv") else {
            throw NSError(
                domain: "FlashcardDeckStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The bundled sample deck could not be found."]
            )
        }
        return try TSVFlashcardParser.parse(contentsOf: url, sourceLabel: "Bundled")
    }

    private func loadImportedDeck(for item: DeckLibraryItem) throws -> FlashcardDeck {
        if let storedDeckFilename = item.storedDeckFilename {
            let fileURL = try decksDirectoryURL()
                .appending(path: storedDeckFilename, directoryHint: .notDirectory)
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(FlashcardDeck.self, from: data)
        }

        guard let bookmarkData = item.bookmarkData else {
            throw NSError(
                domain: "FlashcardDeckStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This imported deck is missing its file bookmark."]
            )
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let deck = try TSVFlashcardParser.parse(contentsOf: url, sourceLabel: item.sourceLabel)

        if isStale {
            let refreshed = DeckLibraryItem(
                id: deck.identifier,
                title: deck.title,
                subtitle: deck.subtitle,
                sourceLabel: item.sourceLabel,
                kind: .imported,
                storedDeckFilename: nil,
                importedFormat: .tsv,
                bookmarkData: try url.bookmarkData()
            )
            upsertLibraryItem(refreshed)
        }

        return deck
    }

    private var libraryPersistenceKey: String {
        "deck-library.items"
    }

    private func decksDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = baseURL
            .appending(path: "LearnIt", directoryHint: .isDirectory)
            .appending(path: "Decks", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func persistenceKey(for identifier: String) -> String {
        "review-state.\(identifier)"
    }
}
