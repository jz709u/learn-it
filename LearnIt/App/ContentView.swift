import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var deckStore: FlashcardDeckStore

    @State private var showingImporter = false
    @State private var pendingImportDocument: ImportedSourceDocument?
    @State private var selectedLibraryItem: DeckLibraryItem?
    @State private var activeStudySession: StudySessionRoute?
    @State private var selectedDeckID: String?

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
            .alert("Import Error", isPresented: importErrorBinding, presenting: deckStore.importError) { _ in
                Button("OK") { deckStore.dismissImportError() }
            } message: { error in
                Text(error)
            }
            .navigationDestination(item: $selectedLibraryItem) { item in
                DeckDetailScreen(
                    item: item,
                    deckStore: deckStore,
                    onStartStudying: { selectedTopic, studyMode, dueAmount in
                        startStudying(item, selectedTopic: selectedTopic, studyMode: studyMode, dueAmount: dueAmount)
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
}

private struct ImportDeckProcessingSheet: View {
    let document: ImportedSourceDocument
    @ObservedObject var deckStore: FlashcardDeckStore
    let onImported: (DeckLibraryItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var generateMnemonics = false
    @State private var isProcessing = false
    @State private var processingSummary = "The imported file will be converted into a local deck and added to your library."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    appleIntelligenceCard
                    fileSummaryCard
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.95, blue: 0.88),
                        Color(red: 1.0, green: 0.98, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Process Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isProcessing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isProcessing ? "Processing..." : "Generate") {
                        processImport()
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(document.suggestedDeckTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)

            Text(document.sourceFilename)
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.7))

            Text(processingSummary)
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.7))
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var appleIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Process With Apple Intelligence")
                .font(.headline)
                .foregroundStyle(Color.black)

            Text(FlashcardImportProcessor.appleIntelligenceStatusDescription())
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.72))

            Toggle("Generate mnemonics", isOn: $generateMnemonics)
                .toggleStyle(.switch)
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var fileSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Imported File")
                .font(.headline)
                .foregroundStyle(Color.black)

            HStack(spacing: 12) {
                DeckMetaPillView(label: "Format", value: document.sourceFormat.displayName)
                DeckMetaPillView(label: "Chars", value: "\(document.rawText.count)")
            }

            Text(document.rawText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.footnote.monospaced())
                .foregroundStyle(Color.black.opacity(0.72))
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func processImport() {
        isProcessing = true

        Task {
            do {
                let result = try await FlashcardImportProcessor.process(document, generateMnemonics: generateMnemonics)
                try deckStore.saveImportedDeck(result.deck, sourceLabel: document.sourceFilename, format: document.sourceFormat)

                await MainActor.run {
                    if let importedItem = deckStore.libraryItems.first(where: { $0.id == result.deck.identifier }) {
                        onImported(importedItem)
                    }
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    processingSummary = error.localizedDescription
                    deckStore.presentImportError(error.localizedDescription)
                }
            }

            await MainActor.run {
                isProcessing = false
            }
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
