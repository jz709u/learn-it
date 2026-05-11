import SwiftUI

struct ImportDeckProcessingSheet: View {
    let document: ImportedSourceDocument
    @ObservedObject var deckStore: FlashcardDeckStore
    let onImported: (DeckLibraryItem) -> Void
    @EnvironmentObject private var creditStore: ImportCreditStore

    @Environment(\.dismiss) private var dismiss

    @State private var generateMnemonics = false
    @State private var isProcessing = false
    @State private var processingMode: ImportProcessingMode = .local
    @State private var showingCreditStore = false
    @State private var processingSummary = "The imported file will be converted into a local deck and added to your library."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    processingModeCard
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
            .sheet(isPresented: $showingCreditStore) {
                CreditStoreSheet()
            }
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
        .onChange(of: processingMode) { _, newMode in
            processingSummary = summaryText(for: newMode)
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var processingModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Processing Mode")
                .font(.headline)
                .foregroundStyle(Color.black)

            Picker("Processing Mode", selection: $processingMode) {
                ForEach(ImportProcessingMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(FlashcardImportProcessor.processingModeDescription(for: processingMode))
                .font(.subheadline)
                .foregroundStyle(Color.black.opacity(0.72))

            if processingMode == .openAI {
                HStack {
                    Text("Credits Available")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(creditStore.balance)")
                        .font(.subheadline.weight(.bold))
                }

                Button("Buy Credits") {
                    showingCreditStore = true
                }
                .buttonStyle(.bordered)
            }

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
        if processingMode == .openAI, !creditStore.canAffordOpenAIImport() {
            processingSummary = "OpenAI imports use 1 credit. Buy credits to continue."
            showingCreditStore = true
            return
        }

        isProcessing = true

        Task {
            do {
                let result = try await FlashcardImportProcessor.process(
                    document,
                    generateMnemonics: generateMnemonics,
                    mode: processingMode
                )
                try deckStore.saveImportedDeck(result.deck, sourceLabel: document.sourceFilename, format: document.sourceFormat)
                if processingMode == .openAI {
                    try creditStore.consumeCredit(reason: document.sourceFilename)
                }

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

    private func summaryText(for mode: ImportProcessingMode) -> String {
        switch mode {
        case .appleIntelligence:
            return "On-device processing keeps the import local when supported by this device."
        case .openAI:
            return "Cloud processing uses 1 credit only after the deck is created and saved successfully."
        case .local:
            return "The imported file will be converted into a local deck and added to your library."
        }
    }
}
