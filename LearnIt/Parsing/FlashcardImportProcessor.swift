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

enum FlashcardImportProcessor {
    static let supportedContentTypes: [UTType] = [
        .tabSeparatedText,
        .commaSeparatedText,
        .json,
        .plainText,
        .text,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText
    ]

    static func prepareDocument(from url: URL) throws -> ImportedSourceDocument {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let rawText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw NSError(
                domain: "FlashcardImportProcessor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This file could not be read as text."]
            )
        }

        return ImportedSourceDocument(
            sourceFilename: url.lastPathComponent,
            sourceFormat: inferFormat(for: url),
            rawText: rawText
        )
    }

    static func process(_ document: ImportedSourceDocument, generateMnemonics: Bool) async throws -> ProcessedImportedDeck {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let model = SystemLanguageModel.default
                if model.isAvailable {
                    let deck = try await processWithAppleIntelligence(document, generateMnemonics: generateMnemonics, model: model)
                    return ProcessedImportedDeck(deck: deck, usedAppleIntelligence: true)
                }
            } catch {
                // Fall back to deterministic parsing below if the model fails or is unavailable.
            }
        }
        #endif

        let deck = try processLocally(document, generateMnemonics: generateMnemonics)
        return ProcessedImportedDeck(deck: deck, usedAppleIntelligence: false)
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

    static func processLocally(_ document: ImportedSourceDocument, generateMnemonics: Bool) throws -> FlashcardDeck {
        let parsedCards: [Flashcard]
        switch document.sourceFormat {
        case .json:
            parsedCards = try parseJSON(document.rawText, generateMnemonics: generateMnemonics)
        case .csv:
            parsedCards = try parseDelimited(document.rawText, separator: ",", generateMnemonics: generateMnemonics)
        case .tsv:
            parsedCards = try parseDelimited(document.rawText, separator: "\t", generateMnemonics: generateMnemonics)
        case .markdown:
            parsedCards = try parseMarkdown(document.rawText, generateMnemonics: generateMnemonics)
        case .plainText:
            parsedCards = try parsePlainText(document.rawText, generateMnemonics: generateMnemonics)
        }

        guard !parsedCards.isEmpty else {
            throw NSError(
                domain: "FlashcardImportProcessor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No flashcards could be extracted from this file."]
            )
        }

        let title = document.suggestedDeckTitle
        let subtitle = "Study \(parsedCards.count) cards imported from a \(document.sourceFormat.displayName) file."

        return FlashcardDeck(
            identifier: StableHash.fnv1a64(document.rawText + "::" + document.sourceFilename),
            title: title,
            subtitle: subtitle,
            sourceLabel: document.sourceFilename,
            cards: parsedCards
        )
    }

    private static func inferFormat(for url: URL) -> ImportedDeckFormat {
        switch url.pathExtension.lowercased() {
        case "tsv":
            return .tsv
        case "csv":
            return .csv
        case "json":
            return .json
        case "md", "markdown":
            return .markdown
        default:
            return .plainText
        }
    }

    private static func parseDelimited(_ rawText: String, separator: Character, generateMnemonics: Bool) throws -> [Flashcard] {
        let lines = rawText.components(separatedBy: .newlines)
        var cards: [Flashcard] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if separator == "|" && (trimmed.hasPrefix("|---") || trimmed.replacingOccurrences(of: "|", with: "").trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy({ $0 == "-" || $0 == ":" })) {
                continue
            }

            let columns = splitDelimitedLine(trimmed, separator: separator)
            guard columns.count >= 3 else { continue }

            let first = columns[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let second = columns[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if first.contains("question") || first.contains("front") || second.contains("answer") || second.contains("back") {
                continue
            }

            let front = cleanDelimitedCell(columns[0])
            let back = cleanDelimitedCell(columns[1])
            let topic = cleanDelimitedCell(columns[2])
            let mnemonic = columns.count > 3 ? cleanDelimitedCell(columns[3]) : nil

            guard !front.isEmpty, !back.isEmpty, !topic.isEmpty else { continue }
            cards.append(
                Flashcard(
                    front: front,
                    back: back,
                    topic: topic,
                    mnemonic: generateMnemonics ? fallbackMnemonic(front: front, back: back, explicitMnemonic: mnemonic) : mnemonic
                )
            )
        }

        guard !cards.isEmpty else {
            throw NSError(
                domain: "FlashcardImportProcessor",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The delimited file did not contain rows with question, answer, and topic columns."]
            )
        }

        return cards
    }

    private static func parseJSON(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        let data = Data(rawText.utf8)
        let object = try JSONSerialization.jsonObject(with: data)

        if let root = object as? [String: Any], let cards = parseCardObjects(root["cards"], generateMnemonics: generateMnemonics) {
            return cards
        }

        if let cards = parseCardObjects(object, generateMnemonics: generateMnemonics) {
            return cards
        }

        throw NSError(
            domain: "FlashcardImportProcessor",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "The JSON file did not contain a supported flashcard structure."]
        )
    }

    private static func parseCardObjects(_ value: Any?, generateMnemonics: Bool) -> [Flashcard]? {
        guard let objects = value as? [[String: Any]] else { return nil }

        let cards = objects.compactMap { object -> Flashcard? in
            let front = firstString(in: object, keys: ["front", "question", "prompt"])
            let back = firstString(in: object, keys: ["back", "answer", "response"])
            let topic = firstString(in: object, keys: ["topic", "category", "section"]) ?? "Imported"
            let mnemonic = firstString(in: object, keys: ["mnemonic", "memoryAid", "memory_aid"])

            guard let front, let back else { return nil }
            return Flashcard(
                front: front,
                back: back,
                topic: topic,
                mnemonic: generateMnemonics ? fallbackMnemonic(front: front, back: back, explicitMnemonic: mnemonic) : mnemonic
            )
        }

        return cards.isEmpty ? nil : cards
    }

    private static func parseMarkdown(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        if let cards = try? parseDelimited(rawText, separator: "|", generateMnemonics: generateMnemonics), !cards.isEmpty {
            return cards
        }
        return try parseStructuredBlocks(rawText, generateMnemonics: generateMnemonics)
    }

    private static func parsePlainText(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        if rawText.contains("\t") {
            return try parseDelimited(rawText, separator: "\t", generateMnemonics: generateMnemonics)
        }
        if rawText.contains(",") {
            if let cards = try? parseDelimited(rawText, separator: ",", generateMnemonics: generateMnemonics), !cards.isEmpty {
                return cards
            }
        }
        return try parseStructuredBlocks(rawText, generateMnemonics: generateMnemonics)
    }

    private static func parseStructuredBlocks(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        let blocks = rawText.components(separatedBy: "\n\n")
        let cards = blocks.compactMap { block -> Flashcard? in
            let lines = block.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }

            guard !lines.isEmpty else { return nil }

            let front = firstPrefixedValue(in: lines, prefixes: ["Question:", "Q:", "Front:"])
            let back = firstPrefixedValue(in: lines, prefixes: ["Answer:", "A:", "Back:"])
            let topic = firstPrefixedValue(in: lines, prefixes: ["Topic:", "Category:", "Section:"]) ?? "Imported"
            let mnemonic = firstPrefixedValue(in: lines, prefixes: ["Mnemonic:", "Memory:", "Hint:"])

            guard let front, let back else { return nil }

            return Flashcard(
                front: front,
                back: back,
                topic: topic,
                mnemonic: generateMnemonics ? fallbackMnemonic(front: front, back: back, explicitMnemonic: mnemonic) : mnemonic
            )
        }

        guard !cards.isEmpty else {
            throw NSError(
                domain: "FlashcardImportProcessor",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Use rows or blocks that include question, answer, and topic values."]
            )
        }

        return cards
    }

    private static func splitDelimitedLine(_ line: String, separator: Character) -> [String] {
        guard separator == "," else {
            return line.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        }

        var values: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in line {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }

            if character == separator && !isInsideQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        values.append(current)
        return values
    }

    private static func cleanDelimitedCell(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " |\"\t").union(.whitespacesAndNewlines))
    }

    private static func firstPrefixedValue(in lines: [String], prefixes: [String]) -> String? {
        for line in lines {
            for prefix in prefixes where line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func fallbackMnemonic(front: String, back: String, explicitMnemonic: String?) -> String? {
        if let explicitMnemonic {
            let trimmed = explicitMnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let answerWords = back
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.count > 2 }
            .prefix(3)

        guard !answerWords.isEmpty else { return nil }
        return "Think: \(front.prefix(20)) -> \(answerWords.joined(separator: ", "))"
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension FlashcardImportProcessor {
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
