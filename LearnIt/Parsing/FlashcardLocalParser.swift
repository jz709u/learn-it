import Foundation

extension FlashcardImportProcessor {
    static let supportedFrontKeys = ["front", "question", "prompt"]
    static let supportedBackKeys = ["back", "answer", "response"]
    static let supportedTopicKeys = ["topic", "category", "section"]
    static let supportedMnemonicKeys = ["mnemonic", "memoryAid", "memory_aid"]

    static let structuredFrontPrefixes = ["Question:", "Q:", "Front:"]
    static let structuredBackPrefixes = ["Answer:", "A:", "Back:"]
    static let structuredTopicPrefixes = ["Topic:", "Category:", "Section:"]
    static let structuredMnemonicPrefixes = ["Mnemonic:", "Memory:", "Hint:"]

    static func parseCards(
        from document: ImportedSourceDocument,
        generateMnemonics: Bool
    ) throws -> [Flashcard] {
        switch document.sourceFormat {
        case .json:
            return try parseJSON(document.rawText, generateMnemonics: generateMnemonics)
        case .csv:
            return try parseDelimited(document.rawText, separator: ",", generateMnemonics: generateMnemonics)
        case .tsv:
            return try parseDelimited(document.rawText, separator: "\t", generateMnemonics: generateMnemonics)
        case .markdown:
            return try parseMarkdown(document.rawText, generateMnemonics: generateMnemonics)
        case .pdf, .plainText:
            return try parsePlainText(document.rawText, generateMnemonics: generateMnemonics)
        }
    }

    static func parseDelimited(_ rawText: String, separator: Character, generateMnemonics: Bool) throws -> [Flashcard] {
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
            throw processingError(code: 3, message: "The delimited file did not contain rows with question, answer, and topic columns.")
        }

        return cards
    }

    static func parseJSON(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        let data = Data(rawText.utf8)
        let object = try JSONSerialization.jsonObject(with: data)

        if let root = object as? [String: Any], let cards = parseCardObjects(root["cards"], generateMnemonics: generateMnemonics) {
            return cards
        }

        if let cards = parseCardObjects(object, generateMnemonics: generateMnemonics) {
            return cards
        }

        throw processingError(code: 4, message: "The JSON file did not contain a supported flashcard structure.")
    }

    static func parseCardObjects(_ value: Any?, generateMnemonics: Bool) -> [Flashcard]? {
        guard let objects = value as? [[String: Any]] else { return nil }

        let cards = objects.compactMap { object -> Flashcard? in
            let front = firstString(in: object, keys: supportedFrontKeys)
            let back = firstString(in: object, keys: supportedBackKeys)
            let topic = firstString(in: object, keys: supportedTopicKeys) ?? "Imported"
            let mnemonic = firstString(in: object, keys: supportedMnemonicKeys)

            guard let front, let back else { return nil }
            return makeCard(front: front, back: back, topic: topic, explicitMnemonic: mnemonic, generateMnemonics: generateMnemonics)
        }

        return cards.isEmpty ? nil : cards
    }

    static func parseMarkdown(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        if let cards = try? parseDelimited(rawText, separator: "|", generateMnemonics: generateMnemonics), !cards.isEmpty {
            return cards
        }
        return try parseStructuredBlocks(rawText, generateMnemonics: generateMnemonics)
    }

    static func parsePlainText(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
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

    static func parseStructuredBlocks(_ rawText: String, generateMnemonics: Bool) throws -> [Flashcard] {
        let blocks = rawText.components(separatedBy: "\n\n")
        let cards = blocks.compactMap { block -> Flashcard? in
            let lines = block.components(separatedBy: .newlines).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }

            guard !lines.isEmpty else { return nil }

            let front = firstPrefixedValue(in: lines, prefixes: structuredFrontPrefixes)
            let back = firstPrefixedValue(in: lines, prefixes: structuredBackPrefixes)
            let topic = firstPrefixedValue(in: lines, prefixes: structuredTopicPrefixes) ?? "Imported"
            let mnemonic = firstPrefixedValue(in: lines, prefixes: structuredMnemonicPrefixes)

            guard let front, let back else { return nil }
            return makeCard(front: front, back: back, topic: topic, explicitMnemonic: mnemonic, generateMnemonics: generateMnemonics)
        }

        guard !cards.isEmpty else {
            throw processingError(code: 5, message: "Use rows or blocks that include question, answer, and topic values.")
        }

        return cards
    }

    static func splitDelimitedLine(_ line: String, separator: Character) -> [String] {
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

    static func cleanDelimitedCell(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " |\"\t").union(.whitespacesAndNewlines))
    }

    static func firstPrefixedValue(in lines: [String], prefixes: [String]) -> String? {
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

    static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
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

    static func makeCard(
        front: String,
        back: String,
        topic: String,
        explicitMnemonic: String?,
        generateMnemonics: Bool
    ) -> Flashcard {
        Flashcard(
            front: front,
            back: back,
            topic: topic,
            mnemonic: generateMnemonics ? fallbackMnemonic(front: front, back: back, explicitMnemonic: explicitMnemonic) : explicitMnemonic
        )
    }

    static func fallbackMnemonic(front: String, back: String, explicitMnemonic: String?) -> String? {
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
