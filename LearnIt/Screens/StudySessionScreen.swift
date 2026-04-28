//
//  StudySessionScreen.swift
//  AWSFlashcards
//
//  Created by Jay Zisch on 2026/04/20.
//
import SwiftUI

struct StudySessionScreen: View {
    let item: DeckLibraryItem
    @ObservedObject var deckStore: FlashcardDeckStore
    let selectedTopic: String

    @State private var sessionCards: [Flashcard] = []
    @State private var studyPosition = 0 {
        didSet {
            print("test \(studyPosition)")
        }
    }
    @State private var isShowingAnswer = false

    private var currentCard: Flashcard? {
        guard sessionCards.indices.contains(studyPosition) else { return nil }
        return sessionCards[studyPosition]
    }
    
    private var navigationTitle: String {
        item.title + "\n" + sessionSubtitle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                cardSection
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.97, blue: 1.0),
                    Color(red: 0.86, green: 0.92, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            deckStore.selectDeck(withID: item.id)
            refreshSession(resetPosition: true)
        }
        .onChange(of: deckStore.deck.identifier) { _, _ in
            refreshSession(resetPosition: true)
        }
        .onChange(of: deckStore.studyMode) { _, _ in
            refreshSession(resetPosition: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sessionCards.isEmpty ? "No cards" : "Card \(studyPosition + 1) of \(sessionCards.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var cardSection: some View {
        Group {
            if let card = currentCard {
                VStack(alignment: .leading, spacing: 14) {
                    CardView(
                        prompt: card.front,
                        answer: card.back,
                        isShowingAnswer: $isShowingAnswer
                    )
                    .id(card.id)

                    if isShowingAnswer {
                        HStack(spacing: 10) {
                            ForEach(ReviewRating.allCases) { rating in
                                Button(rating.rawValue) {
                                    deckStore.schedule(rating, for: card)
                                    advanceAfterReview()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(buttonTint(for: rating))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    deckStore.studyMode == .due ? "No Due Cards" : "No Cards",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    private var sessionSubtitle: String {
        let topicLabel = selectedTopic == "All Topics" ? "All topics" : selectedTopic
        return "\(deckStore.studyMode.rawValue) queue • \(topicLabel)"
    }

    private var emptyStateDescription: String {
        switch deckStore.studyMode {
        case .due:
            return "Nothing is due in this topic right now. Go back to the deck detail to change the queue or topic."
        case .all:
            return "This scope does not contain any cards."
        }
    }

    private func resetStudyPosition() {
        studyPosition = 0
        isShowingAnswer = false
    }

    private func advanceAfterReview() {

        isShowingAnswer = false

        guard !sessionCards.isEmpty else {
            studyPosition = 0
            return
        }

        studyPosition += 1
    }

    private func refreshSession(resetPosition: Bool) {
        sessionCards = deckStore.cards(for: selectedTopic)

        if resetPosition || studyPosition >= sessionCards.count {
            resetStudyPosition()
        } else {
            isShowingAnswer = false
        }
    }

    private func reviewState(for card: Flashcard) -> ReviewState {
        deckStore.reviewState(for: card)
    }

    private func dueLabel(for state: ReviewState) -> String {
        if state.lastReviewedAt == nil {
            return "Now"
        }
        return state.isDue(at: .now) ? "Now" : state.dueDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func buttonTint(for rating: ReviewRating) -> Color {
        switch rating {
        case .again:
            return .red
        case .hard:
            return .orange
        case .good:
            return .blue
        case .easy:
            return .green
        }
    }
}
