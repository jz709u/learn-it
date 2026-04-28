//
//  DeckDetailScreen.swift
//  AWSFlashcards
//
//  Created by Jay Zisch on 2026/04/20.
//
import SwiftUI

struct DeckDetailScreen: View {
    let item: DeckLibraryItem
    @ObservedObject var deckStore: FlashcardDeckStore
    let onStartStudying: (String, StudyMode) -> Void

    @State var showResetProgressAlert: Bool = false
    @State private var selectedTopic = "All Topics"

    private var topics: [String] {
        if deckStore.isSelected(item) {
            return ["All Topics"] + deckStore.deck.topics
        }
        return ["All Topics"]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(item.badgeLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(badgeBackground, in: Capsule())

                        if deckStore.isSelected(item) {
                            Text("Current Deck")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }

                    Text(item.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text(item.sourceLabel)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About This Deck")
                            .font(.headline)
                        Text(detailDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    DeckMetaPillView(label: "Cards", value: "\(deckStore.cardCount(for: item))")
                    DeckMetaPillView(label: "Due", value: "\(deckStore.dueCount(for: item))")
                    DeckMetaPillView(label: "New", value: "\(deckStore.newCount(for: item))")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Study Settings")
                        .font(.headline)

                    Picker("Mode", selection: $deckStore.studyMode) {
                        ForEach(StudyMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Topic", selection: $selectedTopic) {
                        ForEach(topics, id: \.self) { topic in
                            Text(topic).tag(topic)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(queueSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Start Studying") {
                        onStartStudying(selectedTopic, deckStore.studyMode)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink {
                        CardListScreen(item: item, deckStore: deckStore)
                    } label: {
                        Text("Browse Cards")
                    }
                    .buttonStyle(.bordered)

                    Button("Reset Progress", role: .destructive) {
                        showResetProgressAlert = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .alert("Are you sure you want to reset the progress?",
               isPresented: $showResetProgressAlert,
               actions: {
            Button("Yes", role: .destructive) {
                deckStore.selectDeck(withID: item.id)
                deckStore.resetProgress()
            }
        })
        .navigationTitle("Deck Detail")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 1.0),
                    Color(red: 0.90, green: 0.94, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            deckStore.selectDeck(withID: item.id)
            if !topics.contains(selectedTopic) {
                selectedTopic = "All Topics"
            }
        }
    }

    private var badgeBackground: Color {
        switch item.kind {
        case .bundled:
            return Color.blue.opacity(0.15)
        case .imported:
            return Color.orange.opacity(0.16)
        }
    }

    private var detailDescription: String {
        switch item.kind {
        case .bundled:
            return "This deck ships with the app, so it is always available even before you import your own TSV files."
        case .imported:
            return "This deck was imported from a TSV file and stored in your deck library for quick access."
        }
    }

    private var queueSummary: String {
        switch deckStore.studyMode {
        case .due:
            return "\(deckStore.dueCount(for: selectedTopic)) due now, \(deckStore.newCount(for: selectedTopic)) unseen cards in this scope."
        case .all:
            return "Browsing all cards in this deck. Grading in study still updates the spaced repetition schedule."
        }
    }
}
