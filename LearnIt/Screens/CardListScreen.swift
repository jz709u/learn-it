//
//  CardListScreen.swift
//  LearnIt
//
//  Created by Jay Zisch on 2026/04/28.
//

import SwiftUI
import UIKit

struct CardListScreen: View {
    @ObservedObject var session: DeckSessionViewModel

    @State private var searchText = ""
    @State private var sortOrder: CardSortOrder = .unordered

    init(session: DeckSessionViewModel) {
        self.session = session
        let searchTextField = UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self])
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Search question, answer, or topic",
            attributes: [
                .foregroundColor: UIColor.label.withAlphaComponent(0.75)
            ]
        )
    }

    private var filteredCards: [Flashcard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseCards = query.isEmpty
            ? session.deck.cards
            : session.deck.cards.filter {
                $0.front.localizedCaseInsensitiveContains(query)
                || $0.back.localizedCaseInsensitiveContains(query)
                || $0.topic.localizedCaseInsensitiveContains(query)
                || ($0.mnemonic?.localizedCaseInsensitiveContains(query) ?? false)
            }

        switch sortOrder {
        case .unordered:
            return baseCards
        case .hardToEasy:
            return baseCards.sorted { hardnessScore(for: $0) > hardnessScore(for: $1) }
        case .easyToHard:
            return baseCards.sorted { hardnessScore(for: $0) < hardnessScore(for: $1) }
        }
    }

    var body: some View {
        List(filteredCards) { card in
            NavigationLink {
                CardStatsDetailScreen(card: card, reviewState: session.reviewState(for: card))
            } label: {
                CardRowView(card: card, reviewState: session.reviewState(for: card))
            }
            .listRowBackground(Color(.systemBackground))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 1.0),
                    Color(red: 0.88, green: 0.93, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer,
            prompt: "Search question, answer, or topic"
        )
        .safeAreaInset(edge: .top) {
            sortBar
        }
        .overlay {
            if filteredCards.isEmpty {
                ContentUnavailableView(
                    "No Matching Cards",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search or sort order.")
                )
            }
        }
    }

    private var sortBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(filteredCards.count) cards")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Picker("Sort", selection: $sortOrder) {
                ForEach(CardSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.orange))
    }

    private func hardnessScore(for card: Flashcard) -> Double {
        let state = session.reviewState(for: card)
        let dueBias = state.isDue(at: .now) ? 0.35 : 0
        let newBias = state.lastReviewedAt == nil ? 0.2 : 0
        return Double(state.lapses) * 3.0
            + Double(state.repetitions) * 0.25
            + Double(max(0, 3.0 - state.easeFactor)) * 4.0
            + dueBias
            + newBias
    }
}

private enum CardSortOrder: String, CaseIterable, Identifiable {
    case unordered
    case hardToEasy
    case easyToHard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unordered:
            return "Unordered"
        case .hardToEasy:
            return "Hard-Easy"
        case .easyToHard:
            return "Easy-Hard"
        }
    }
}

private struct CardRowView: View {
    let card: Flashcard
    let reviewState: ReviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.front)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(card.back)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Text(card.topic)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.34, blue: 0.60))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                StatChip(label: "State", value: reviewStateSummary)
                StatChip(label: "Reps", value: "\(reviewState.repetitions)")
                StatChip(label: "Int", value: reviewState.intervalDays == 0 ? "New" : "\(reviewState.intervalDays)d")
                StatChip(label: "Due", value: dueLabel)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reviewStateSummary: String {
        if reviewState.lastReviewedAt == nil {
            return "New"
        }
        return reviewState.isDue(at: .now) ? "Due" : "Learning"
    }

    private var dueLabel: String {
        if reviewState.lastReviewedAt == nil || reviewState.isDue(at: .now) {
            return "Now"
        }
        return reviewState.dueDate.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct CardStatsDetailScreen: View {
    let card: Flashcard
    let reviewState: ReviewState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailCard(title: "Question", text: card.front)
                detailCard(title: "Answer", text: card.back)
                if let mnemonic = card.mnemonic, !mnemonic.isEmpty {
                    detailCard(title: "Mnemonic", text: mnemonic)
                }

                HStack(spacing: 12) {
                    StatChip(label: "Topic", value: card.topic)
                    StatChip(label: "State", value: stateLabel)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Spaced Repetition Stats")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        detailStat(label: "Repetitions", value: "\(reviewState.repetitions)")
                        detailStat(label: "Interval", value: reviewState.intervalDays == 0 ? "New" : "\(reviewState.intervalDays) days")
                        detailStat(label: "Ease Factor", value: String(format: "%.2f", reviewState.easeFactor))
                        detailStat(label: "Lapses", value: "\(reviewState.lapses)")
                        detailStat(label: "Due Date", value: dueDateLabel)
                        detailStat(label: "Last Reviewed", value: lastReviewedLabel)
                    }
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 1.0),
                    Color(red: 0.88, green: 0.93, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Card Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stateLabel: String {
        if reviewState.lastReviewedAt == nil {
            return "New"
        }
        return reviewState.isDue(at: .now) ? "Due" : "Scheduled"
    }

    private var dueDateLabel: String {
        if reviewState.lastReviewedAt == nil {
            return "Now"
        }
        return reviewState.dueDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var lastReviewedLabel: String {
        guard let lastReviewedAt = reviewState.lastReviewedAt else {
            return "Never"
        }
        return lastReviewedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func detailCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
