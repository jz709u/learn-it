import Foundation

enum OpenAIFlashcardClient {
    static func generateDeck(
        from document: ImportedSourceDocument,
        generateMnemonics: Bool
    ) async throws -> FlashcardDeck {
        _ = document
        _ = generateMnemonics

        throw NSError(
            domain: "OpenAIFlashcardClient",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "OpenAI imports will be available after app-managed AI processing is connected."]
        )
    }
}
