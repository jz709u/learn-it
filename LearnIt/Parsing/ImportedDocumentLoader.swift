import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

extension FlashcardImportProcessor {
    static func inferFormat(for url: URL) -> ImportedDeckFormat {
        switch url.pathExtension.lowercased() {
        case "tsv":
            return .tsv
        case "csv":
            return .csv
        case "json":
            return .json
        case "pdf":
            return .pdf
        case "md", "markdown":
            return .markdown
        default:
            return .plainText
        }
    }

    static func readRawText(from url: URL, format: ImportedDeckFormat) throws -> String {
        switch format {
        case .pdf:
            return try extractPDFText(from: url)
        case .tsv, .csv, .json, .markdown, .plainText:
            let data = try Data(contentsOf: url)
            guard let rawText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
                throw processingError(code: 1, message: "This file could not be read as text.")
            }
            return rawText
        }
    }

    static func extractPDFText(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw processingError(code: 7, message: "The PDF could not be opened.")
        }

        let rawText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawText.isEmpty else {
            throw processingError(code: 8, message: "The PDF did not contain extractable text.")
        }

        return rawText
        #else
        throw processingError(code: 9, message: "PDF import is unavailable in this build.")
        #endif
    }
}
