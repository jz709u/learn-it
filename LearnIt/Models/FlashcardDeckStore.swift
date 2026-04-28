import Foundation

final class FlashcardDeckStore: ObservableObject {
    @Published var deck: FlashcardDeck = .empty
    @Published var importError: String?
    @Published var studyMode: StudyMode = .due
    @Published private(set) var libraryItems: [DeckLibraryItem] = []
    @Published private(set) var selectedDeckID: String?
    @Published private(set) var reviewStates: [String: ReviewState] = [:]

    private let defaults = UserDefaults.standard
    private let bundledDeckID = "bundled.aws-cloud-practitioner"

    init() {
        loadLibrary()
        if let bundled = libraryItems.first(where: { $0.kind == .bundled }) {
            selectDeck(withID: bundled.id)
        }
    }

    func loadBundledDeck() {
        selectDeck(withID: bundledDeckID)
    }

    func importDeck(from url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let importedDeck = try TSVFlashcardParser.parse(contentsOf: url, sourceLabel: url.lastPathComponent)
            let bookmarkData = try url.bookmarkData()
            let item = DeckLibraryItem(
                id: importedDeck.identifier,
                title: importedDeck.title,
                subtitle: importedDeck.subtitle,
                sourceLabel: importedDeck.sourceLabel,
                kind: .imported,
                bookmarkData: bookmarkData
            )
            upsertLibraryItem(item)
            deck = importedDeck
            selectedDeckID = item.id
            loadReviewStates()
        } catch {
            importError = error.localizedDescription
        }
    }

    func shuffle() {
        deck.cards.shuffle()
    }

    func cards(for topic: String) -> [Flashcard] {
        let scopedCards = topic == "All Topics" ? deck.cards : deck.cards.filter { $0.topic == topic }

        switch studyMode {
        case .all:
            return scopedCards
        case .due:
            return scopedCards
                .filter { reviewState(for: $0).isDue(at: .now) }
                .sorted { lhs, rhs in
                    reviewState(for: lhs).dueDate < reviewState(for: rhs).dueDate
                }
        }
    }

    func reviewState(for card: Flashcard) -> ReviewState {
        reviewStates[card.id] ?? .new(now: .now)
    }

    func dueCount(for topic: String) -> Int {
        let allCards = topic == "All Topics" ? deck.cards : deck.cards.filter { $0.topic == topic }
        return allCards.filter { reviewState(for: $0).isDue(at: .now) }.count
    }

    func newCount(for topic: String) -> Int {
        let allCards = topic == "All Topics" ? deck.cards : deck.cards.filter { $0.topic == topic }
        return allCards.filter { reviewStates[$0.id] == nil }.count
    }

    func schedule(_ rating: ReviewRating, for card: Flashcard) {
        let next = ReviewScheduler.nextState(from: reviewStates[card.id], rating: rating)
        reviewStates[card.id] = next
        persistReviewStates()
    }

    func resetProgress() {
        reviewStates = [:]
        persistReviewStates()
    }

    func selectDeck(withID id: String) {
        guard let item = libraryItems.first(where: { $0.id == id }) else { return }

        switch item.kind {
        case .bundled:
            loadBundledDeckFromBundle()
        case .imported:
            loadImportedDeck(for: item)
        }
    }

    func isSelected(_ item: DeckLibraryItem) -> Bool {
        selectedDeckID == item.id
    }

    func cardCount(for item: DeckLibraryItem) -> Int {
        if isSelected(item) {
            return deck.cards.count
        }

        switch item.kind {
        case .bundled:
            return 167
        case .imported:
            return nil
                ?? 0
        }
    }

    func dueCount(for item: DeckLibraryItem) -> Int {
        if isSelected(item) {
            return dueCount(for: "All Topics")
        }

        if let count = storedCardIDs(for: item)?.filter({ reviewStatesForItem(item)[$0]?.isDue(at: .now) ?? true }).count {
            return count
        }

        return 0
    }

    func newCount(for item: DeckLibraryItem) -> Int {
        if isSelected(item) {
            return newCount(for: "All Topics")
        }

        if let ids = storedCardIDs(for: item) {
            let states = reviewStatesForItem(item)
            return ids.filter { states[$0] == nil }.count
        }

        return 0
    }

    private func loadReviewStates() {
        guard deck.identifier != "empty" else {
            reviewStates = [:]
            return
        }

        guard let data = defaults.data(forKey: persistenceKey) else {
            reviewStates = [:]
            return
        }

        do {
            reviewStates = try JSONDecoder().decode([String: ReviewState].self, from: data)
        } catch {
            reviewStates = [:]
        }
    }

    private func persistReviewStates() {
        guard deck.identifier != "empty" else { return }

        do {
            let data = try JSONEncoder().encode(reviewStates)
            defaults.set(data, forKey: persistenceKey)
        } catch {
            importError = "Could not save spaced repetition progress."
        }
    }

    private var persistenceKey: String {
        "review-state.\(deck.identifier)"
    }

    private func persistenceKey(for identifier: String) -> String {
        "review-state.\(identifier)"
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
            bookmarkData: nil
        )

        let imported = savedItems.filter { $0.kind == .imported }
        libraryItems = [bundled] + imported.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func persistLibrary() {
        do {
            let imported = libraryItems.filter { $0.kind == .imported }
            let data = try JSONEncoder().encode(imported)
            defaults.set(data, forKey: libraryPersistenceKey)
        } catch {
            importError = "Could not save the deck library."
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

    private func loadBundledDeckFromBundle() {
        guard let url = Bundle.main.url(forResource: "aws-cloud-practitioner-flashcards", withExtension: "tsv") else {
            importError = "The bundled sample deck could not be found."
            return
        }

        do {
            deck = try TSVFlashcardParser.parse(contentsOf: url, sourceLabel: "Bundled")
            selectedDeckID = bundledDeckID
            loadReviewStates()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func loadImportedDeck(for item: DeckLibraryItem) {
        guard let bookmarkData = item.bookmarkData else {
            importError = "This imported deck is missing its file bookmark."
            return
        }

        do {
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

            deck = try TSVFlashcardParser.parse(contentsOf: url, sourceLabel: item.sourceLabel)
            selectedDeckID = item.id
            loadReviewStates()

            if isStale {
                let refreshed = DeckLibraryItem(
                    id: deck.identifier,
                    title: deck.title,
                    subtitle: deck.subtitle,
                    sourceLabel: item.sourceLabel,
                    kind: .imported,
                    bookmarkData: try url.bookmarkData()
                )
                upsertLibraryItem(refreshed)
            }
        } catch {
            importError = "Could not open imported deck `\(item.title)`: \(error.localizedDescription)"
        }
    }

    private var libraryPersistenceKey: String {
        "deck-library.items"
    }

    private func reviewStatesForItem(_ item: DeckLibraryItem) -> [String: ReviewState] {
        guard let data = defaults.data(forKey: persistenceKey(for: item.id)),
              let decoded = try? JSONDecoder().decode([String: ReviewState].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func storedCardIDs(for item: DeckLibraryItem) -> [String]? {
        switch item.kind {
        case .bundled:
            guard let url = Bundle.main.url(forResource: "aws-cloud-practitioner-flashcards", withExtension: "tsv"),
                  let parsed = try? TSVFlashcardParser.parse(contentsOf: url, sourceLabel: "Bundled") else {
                return nil
            }
            return parsed.cards.map(\.id)
        case .imported:
            guard let bookmarkData = item.bookmarkData else { return nil }
            do {
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
                let parsed = try TSVFlashcardParser.parse(contentsOf: url, sourceLabel: item.sourceLabel)
                return parsed.cards.map(\.id)
            } catch {
                return nil
            }
        }
    }
}
