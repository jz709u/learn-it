import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var deckStore: FlashcardDeckStore

    @State private var showingImporter = false
    @State private var selectedLibraryItem: DeckLibraryItem?
    @State private var activeStudySession: StudySessionRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    libraryHeader
                    deckLibrarySection
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
            .navigationTitle("Learn It")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import TSV") {
                        showingImporter = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.tabSeparatedText, .plainText],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .alert("Import Error", isPresented: importErrorBinding, presenting: deckStore.importError) { _ in
                Button("OK") { deckStore.dismissImportError() }
            } message: { error in
                Text(error)
            }
            .navigationDestination(item: $selectedLibraryItem) { item in
                DeckDetailScreen(
                    item: item,
                    deckStore: deckStore,
                    onStartStudying: { selectedTopic, studyMode in
                        startStudying(item, selectedTopic: selectedTopic, studyMode: studyMode)
                    }
                )
            }
            .navigationDestination(item: $activeStudySession) { route in
                StudySessionScreen(
                    item: route.item,
                    deckStore: deckStore,
                    selectedTopic: route.selectedTopic
                )
            }
        }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Deck Library")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.11, green: 0.20, blue: 0.35))
        }
    }

    private var deckLibrarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Decks")
                    .font(.headline)
                Spacer()
                Text("\(deckStore.libraryItems.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(deckStore.libraryItems) { item in
                DeckLibraryRow(
                    item: item,
                    isSelected: deckStore.isSelected(item),
                    cardCount: deckStore.cardCount(for: item),
                    dueCount: deckStore.dueCount(for: item),
                    newCount: deckStore.newCount(for: item),
                    badgeBackground: deckBadgeBackground(for: item),
                    onOpenDetail: {
                        selectedLibraryItem = item
                    },
                    onStartStudying: {
                        startStudying(item, selectedTopic: "All Topics", studyMode: deckStore.studyMode)
                    }
                )
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            deckStore.importDeck(from: url)
        case .failure(let error):
            deckStore.presentImportError(error.localizedDescription)
        }
    }

    private func deckBadgeBackground(for item: DeckLibraryItem) -> Color {
        switch item.kind {
        case .bundled:
            return Color.blue.opacity(0.15)
        case .imported:
            return Color.orange.opacity(0.16)
        }
    }

    private func startStudying(_ item: DeckLibraryItem, selectedTopic: String, studyMode: StudyMode) {
        deckStore.setStudyMode(studyMode)
        deckStore.selectDeck(withID: item.id)
        activeStudySession = StudySessionRoute(item: item, selectedTopic: selectedTopic)
    }
}

private extension ContentView {
    var importErrorBinding: Binding<Bool> {
        Binding(
            get: { deckStore.importError != nil },
            set: { newValue in
                if !newValue {
                    deckStore.dismissImportError()
                }
            }
        )
    }
}

private struct StudySessionRoute: Identifiable, Hashable {
    let item: DeckLibraryItem
    let selectedTopic: String

    var id: String {
        "\(item.id)::\(selectedTopic)"
    }
}

private struct DeckLibraryRow: View {
    let item: DeckLibraryItem
    let isSelected: Bool
    let cardCount: Int
    let dueCount: Int
    let newCount: Int
    let badgeBackground: Color
    let onOpenDetail: () -> Void
    let onStartStudying: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(item.sourceLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text(item.badgeLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(badgeBackground, in: Capsule())
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }

            HStack(spacing: 10) {
                DeckMetaPillView(label: "Cards", value: "\(cardCount)")
                DeckMetaPillView(label: "Due", value: "\(dueCount)")
                DeckMetaPillView(label: "New", value: "\(newCount)")
                Spacer()
                Button("Start Studying", action: onStartStudying)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1.5)
        }
        .onTapGesture {
            onOpenDetail()
        }
    }
}
