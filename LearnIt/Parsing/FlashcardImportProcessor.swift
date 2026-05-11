import Foundation
import UniformTypeIdentifiers

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ImportedSourceDocument: Identifiable, Hashable {
    let id: UUID
    let sourceFilename: String
    let sourceFormat: ImportedDeckFormat
    let rawText: String

    init(sourceFilename: String, sourceFormat: ImportedDeckFormat, rawText: String) {
        self.id = UUID()
        self.sourceFilename = sourceFilename
        self.sourceFormat = sourceFormat
        self.rawText = rawText
    }

    var suggestedDeckTitle: String {
        let baseName = (sourceFilename as NSString).deletingPathExtension
        let normalized = baseName.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Imported Deck" : normalized.capitalized
    }
}

struct ProcessedImportedDeck {
    let deck: FlashcardDeck
    let usedAppleIntelligence: Bool
}

struct GeneratedDeckPayload: Decodable {
    let title: String
    let subtitle: String
    let cards: [GeneratedCardPayload]
}

struct GeneratedCardPayload: Decodable {
    let front: String
    let back: String
    let topic: String
    let mnemonic: String?
}

struct FlashcardImportProcessorDependencies {
    let inferFormat: (URL) -> ImportedDeckFormat
    let readRawText: (URL, ImportedDeckFormat) throws -> String
    let parseCards: (ImportedSourceDocument, Bool) throws -> [Flashcard]
    let processWithOpenAI: (ImportedSourceDocument, Bool) async throws -> FlashcardDeck
    let processWithAppleIntelligence: (ImportedSourceDocument, Bool) async throws -> FlashcardDeck

    static let live = FlashcardImportProcessorDependencies(
        inferFormat: FlashcardImportProcessor.inferFormat(for:),
        readRawText: FlashcardImportProcessor.readRawText(from:format:),
        parseCards: FlashcardImportProcessor.parseCards(from:generateMnemonics:),
        processWithOpenAI: { document, generateMnemonics in
            try await OpenAIFlashcardClient.generateDeck(
                from: document,
                generateMnemonics: generateMnemonics
            )
        },
        processWithAppleIntelligence: { document, generateMnemonics in
            try await FlashcardImportProcessor.processWithAppleIntelligenceIfAvailable(
                document,
                generateMnemonics: generateMnemonics
            )
        }
    )
}

enum ImportProcessingMode: String, CaseIterable, Identifiable {
    case appleIntelligence = "Apple Intelligence"
    case openAI = "OpenAI"
    case local = "Local Process"

    var id: String { rawValue }
}

extension UTType {
    static let markdown: Self = .init(filenameExtension: "md")!
    static let markdownLiteral: Self = .init(filenameExtension: "markdown")!
}

enum FlashcardImportProcessor {
    private static let errorDomain = "FlashcardImportProcessor"

    static let supportedContentTypes: [UTType] = [
        .tabSeparatedText,
        .commaSeparatedText,
        .json,
        .plainText,
        .text,
        .pdf,
        .markdown,
        .markdownLiteral
    ]

    static func prepareDocument(from url: URL) throws -> ImportedSourceDocument {
        try prepareDocument(from: url, using: .live)
    }

    static func prepareDocument(
        from url: URL,
        using dependencies: FlashcardImportProcessorDependencies
    ) throws -> ImportedSourceDocument {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let format = dependencies.inferFormat(url)
        let rawText = try dependencies.readRawText(url, format)

        return ImportedSourceDocument(
            sourceFilename: url.lastPathComponent,
            sourceFormat: format,
            rawText: rawText
        )
    }

    static func process(
        _ document: ImportedSourceDocument,
        generateMnemonics: Bool,
        mode: ImportProcessingMode
    ) async throws -> ProcessedImportedDeck {
        try await process(
            document,
            generateMnemonics: generateMnemonics,
            mode: mode,
            using: .live
        )
    }

    static func process(
        _ document: ImportedSourceDocument,
        generateMnemonics: Bool,
        mode: ImportProcessingMode,
        using dependencies: FlashcardImportProcessorDependencies
    ) async throws -> ProcessedImportedDeck {
        switch mode {
        case .appleIntelligence:
            let deck = try await dependencies.processWithAppleIntelligence(document, generateMnemonics)
            return ProcessedImportedDeck(deck: deck, usedAppleIntelligence: true)

        case .openAI:
            let deck = try await dependencies.processWithOpenAI(document, generateMnemonics)
            return ProcessedImportedDeck(deck: deck, usedAppleIntelligence: false)

        case .local:
            let deck = try processLocally(document, generateMnemonics: generateMnemonics, using: dependencies)
            return ProcessedImportedDeck(deck: deck, usedAppleIntelligence: false)
        }
    }

    static func appleIntelligenceStatusDescription() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return "Available on this device."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to use on-device processing."
            case .unavailable(.deviceNotEligible):
                return "This device does not support Apple Intelligence."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading or preparing."
            case .unavailable:
                return "Apple Intelligence is currently unavailable."
            }
        }
        #endif

        return "Apple Intelligence is unavailable in this build, so import falls back to local parsing."
    }

    static func processingModeDescription(for mode: ImportProcessingMode) -> String {
        switch mode {
        case .appleIntelligence:
            return appleIntelligenceStatusDescription()
        case .openAI:
            return "Send the source text to the OpenAI Responses API and return a structured flashcard deck."
        case .local:
            return "Parse the imported text on-device with deterministic local rules."
        }
    }

    static func processLocally(_ document: ImportedSourceDocument, generateMnemonics: Bool) throws -> FlashcardDeck {
        try processLocally(document, generateMnemonics: generateMnemonics, using: .live)
    }

    static func processLocally(
        _ document: ImportedSourceDocument,
        generateMnemonics: Bool,
        using dependencies: FlashcardImportProcessorDependencies
    ) throws -> FlashcardDeck {
        let parsedCards = try dependencies.parseCards(document, generateMnemonics)

        guard !parsedCards.isEmpty else {
            throw processingError(code: 2, message: "No flashcards could be extracted from this file.")
        }

        return FlashcardDeck(
            identifier: StableHash.fnv1a64(document.rawText + "::" + document.sourceFilename),
            title: document.suggestedDeckTitle,
            subtitle: "Study \(parsedCards.count) cards imported from a \(document.sourceFormat.displayName) file.",
            sourceLabel: document.sourceFilename,
            cards: parsedCards
        )
    }
}

extension FlashcardImportProcessor {
    static func processingError(code: Int, message: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private extension FlashcardImportProcessor {
    static func processWithAppleIntelligenceIfAvailable(
        _ document: ImportedSourceDocument,
        generateMnemonics: Bool
    ) async throws -> FlashcardDeck {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return try await processWithAppleIntelligence(document, generateMnemonics: generateMnemonics, model: model)
            }
        }
        #endif

        throw processingError(code: 10, message: appleIntelligenceStatusDescription())
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension FlashcardImportProcessor {
    static func processWithAppleIntelligence(
        _ document: ImportedSourceDocument,
        generateMnemonics: Bool,
        model: SystemLanguageModel
    ) async throws -> FlashcardDeck {
        let instructions = """
        You convert imported study material into a clean flashcard deck.
        Extract factual cards only.
        Preserve meaning from the source.
        Keep questions and answers concise but complete.
        Create a useful topic for each card.
        \(generateMnemonics ? "Generate a short helpful mnemonic for each card when possible." : "Leave mnemonic fields empty.")
        Respond with valid JSON only.
        """

        let prompt = """
        Convert this \(document.sourceFormat.displayName) study material into flashcards.
        Source filename: \(document.sourceFilename)
        Suggested title: \(document.suggestedDeckTitle)

        Return JSON with this exact shape:
        {
          "title": "Deck title",
          "subtitle": "Short subtitle",
          "cards": [
            {
              "front": "Question",
              "back": "Answer",
              "topic": "Topic",
              "mnemonic": "Mnemonic or empty string"
            }
          ]
        }

        Source content:
        \(document.rawText)
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(to: prompt)
        let payloadData = Data(response.content.utf8)
        let payload = try JSONDecoder().decode(GeneratedDeckPayload.self, from: payloadData)

        let cards = payload.cards.compactMap { card -> Flashcard? in
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            let topic = card.topic.trimmingCharacters(in: .whitespacesAndNewlines)
            let mnemonic = card.mnemonic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !front.isEmpty, !back.isEmpty, !topic.isEmpty else { return nil }
            return Flashcard(
                front: front,
                back: back,
                topic: topic,
                mnemonic: mnemonic.isEmpty ? nil : mnemonic
            )
        }

        guard !cards.isEmpty else {
            throw NSError(
                domain: "FlashcardImportProcessor",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence did not return any usable flashcards."]
            )
        }

        return FlashcardDeck(
            identifier: StableHash.fnv1a64(document.rawText + "::" + document.sourceFilename + "::ai"),
            title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(document.suggestedDeckTitle),
            subtitle: payload.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("Study \(cards.count) cards imported from \(document.sourceFilename)."),
            sourceLabel: document.sourceFilename,
            cards: cards
        )
    }
}
#endif

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
