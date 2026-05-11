import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var deckStore: FlashcardDeckStore
    @EnvironmentObject private var creditStore: ImportCreditStore

    @State private var showingImporter = false
    @State private var pendingImportDocument: ImportedSourceDocument?
    @State private var selectedLibraryItem: DeckLibraryItem?
    @State private var activeStudySession: StudySessionRoute?
    @State private var selectedDeckID: String?
    @State private var showingCreditsStore = false

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
                    Button("Import") {
                        showingImporter = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: FlashcardImportProcessor.supportedContentTypes,
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .sheet(item: $pendingImportDocument) { document in
                ImportDeckProcessingSheet(document: document, deckStore: deckStore) { importedItem in
                    selectedDeckID = importedItem.id
                }
            }
            .sheet(isPresented: $showingCreditsStore) {
                CreditStoreSheet()
            }
            .alert("Import Error", isPresented: importErrorBinding, presenting: deckStore.importError) { _ in
                Button("OK") { deckStore.dismissImportError() }
            } message: { error in
                Text(error)
            }
            .alert("Credit Store", isPresented: creditStoreErrorBinding, presenting: creditStore.errorMessage) { _ in
                Button("OK") { creditStore.dismissError() }
            } message: { error in
                Text(error)
            }
            .navigationDestination(item: $selectedLibraryItem) { item in
                DeckDetailScreen(
                    item: item,
                    deckStore: deckStore,
                    onStartStudying: { selectedTopic, studyMode, dueAmount in
                        startStudying(item, selectedTopic: selectedTopic, studyMode: studyMode, dueAmount: dueAmount)
                    },
                    onDeleteDeck: { deck in
                        deleteDeck(deck)
                    }
                )
            }
            .navigationDestination(item: $activeStudySession) { route in
                StudySessionScreen(
                    item: route.item,
                    deckStore: deckStore,
                    selectedTopic: route.selectedTopic,
                    studyMode: route.studyMode,
                    dueAmount: route.dueAmount
                )
            }
        }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Deck Library")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.11, green: 0.20, blue: 0.35))

            Button {
                showingCreditsStore = true
            } label: {
                HStack(spacing: 10) {
                    Text("AI Credits")
                        .font(.headline)
                    Text("\(creditStore.balance)")
                        .font(.headline.weight(.bold))
                    Text("OpenAI imports use 1 credit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.78), in: Capsule())
            }
            .buttonStyle(.plain)
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
                    isSelected: selectedDeckID == item.id,
                    cardCount: deckStore.cardCount(for: item),
                    dueCount: deckStore.dueCount(for: item),
                    newCount: deckStore.newCount(for: item),
                    badgeBackground: deckBadgeBackground(for: item),
                    onOpenDetail: {
                        selectedDeckID = item.id
                        selectedLibraryItem = item
                    },
                    onStartStudying: {
                        selectedDeckID = item.id
                        startStudying(item, selectedTopic: "All Topics", studyMode: .due, dueAmount: 20)
                    }
                )
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                pendingImportDocument = try FlashcardImportProcessor.prepareDocument(from: url)
            } catch {
                deckStore.presentImportError(error.localizedDescription)
            }
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

    private func startStudying(_ item: DeckLibraryItem, selectedTopic: String, studyMode: StudyMode, dueAmount: Int) {
        activeStudySession = StudySessionRoute(item: item, selectedTopic: selectedTopic, studyMode: studyMode, dueAmount: dueAmount)
    }

    private func deleteDeck(_ item: DeckLibraryItem) {
        do {
            try deckStore.deleteDeck(item)
            if selectedDeckID == item.id {
                selectedDeckID = nil
            }
            if selectedLibraryItem?.id == item.id {
                selectedLibraryItem = nil
            }
            if activeStudySession?.item.id == item.id {
                activeStudySession = nil
            }
        } catch {
            deckStore.presentImportError(error.localizedDescription)
        }
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

    var creditStoreErrorBinding: Binding<Bool> {
        Binding(
            get: { creditStore.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    creditStore.dismissError()
                }
            }
        )
    }
}

private struct StudySessionRoute: Identifiable, Hashable {
    let item: DeckLibraryItem
    let selectedTopic: String
    let studyMode: StudyMode
    let dueAmount: Int

    var id: String {
        "\(item.id)::\(selectedTopic)::\(studyMode.rawValue)::\(dueAmount)"
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
