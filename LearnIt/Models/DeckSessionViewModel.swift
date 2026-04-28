import Foundation

final class DeckSessionViewModel: ObservableObject {
    let item: DeckLibraryItem

    @Published private(set) var deck: FlashcardDeck = .empty
    @Published private(set) var reviewStates: [String: ReviewState] = [:]
    @Published private(set) var loadError: String?

    private let deckStore: FlashcardDeckStore

    init(item: DeckLibraryItem, deckStore: FlashcardDeckStore) {
        self.item = item
        self.deckStore = deckStore
        reload()
    }

    func reload() {
        do {
            deck = try deckStore.loadDeck(for: item)
            reviewStates = deckStore.loadReviewStates(for: item.id)
            loadError = nil
        } catch {
            deck = .empty
            reviewStates = [:]
            loadError = error.localizedDescription
        }
    }

    func reviewState(for card: Flashcard) -> ReviewState {
        reviewStates[card.id] ?? .new(now: .now)
    }

    func dueCount(for topic: String) -> Int {
        scopedCards(for: topic).filter { reviewState(for: $0).isDue(at: .now) }.count
    }

    func newCount(for topic: String) -> Int {
        scopedCards(for: topic).filter { reviewStates[$0.id] == nil }.count
    }

    func cards(for topic: String, studyMode: StudyMode, dueAmount: Int) -> [Flashcard] {
        let cards = scopedCards(for: topic)

        switch studyMode {
        case .all:
            return cards
        case .due:
            return dueCards(in: cards)
        case .dueAmount:
            return Array(dueCards(in: cards).prefix(dueAmount))
        }
    }

    func schedule(_ rating: ReviewRating, for card: Flashcard) {
        reviewStates[card.id] = ReviewScheduler.nextState(from: reviewStates[card.id], rating: rating)
        deckStore.persistReviewStates(reviewStates, for: item.id)
    }

    func resetProgress() {
        reviewStates = [:]
        deckStore.clearReviewStates(for: item.id)
    }

    private func scopedCards(for topic: String) -> [Flashcard] {
        topic == "All Topics" ? deck.cards : deck.cards.filter { $0.topic == topic }
    }

    private func dueCards(in cards: [Flashcard]) -> [Flashcard] {
        cards
            .filter { reviewState(for: $0).isDue(at: .now) }
            .sorted { lhs, rhs in
                reviewState(for: lhs).dueDate < reviewState(for: rhs).dueDate
            }
    }
}
