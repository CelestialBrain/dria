//
//  FileImporter.swift
//  dria
//

import AppKit
import Foundation
import PDFKit
import Vision

struct FileImporter {
    private let ocr = OCRService()

    // MARK: - Text Extraction

    /// Extract text from any supported file. Runs heavy work off main thread.
    func extractText(from url: URL) async -> (text: String, error: String?) {
        let ext = url.pathExtension.lowercased()
        let fileURL = url

        // Run extraction on background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text: String
                    switch ext {
                    case "md", "txt":
                        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                    case "pdf":
                        text = self.extractFromPDF(url: fileURL)
                    case "docx", "doc":
                        text = try self.extractFromDOCX(url: fileURL)
                    case "xlsx", "xls":
                        text = try self.extractFromXLSX(url: fileURL)
                    case "pptx", "ppt":
                        text = try self.extractFromPPTX(url: fileURL)
                    case "html", "htm":
                        text = try self.extractFromHTML(url: fileURL)
                    case "rtf", "rtfd":
                        text = try self.extractFromRTF(url: fileURL)
                    default:
                        text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                    }

                    if text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count < 50 {
                        continuation.resume(returning: (text, "Low text content (\(text.count) chars)"))
                    } else {
                        continuation.resume(returning: (text, nil))
                    }
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription))
                }
            }
        }
    }

    /// Extract text from image (needs to stay async for Vision)
    func extractTextFromImage(url: URL) async -> (text: String, error: String?) {
        do {
            guard let image = NSImage(contentsOf: url) else { return ("", "Invalid image") }
            let text = try await ocr.recognizeText(from: image)
            return (text, text.count < 50 ? "Low text content" : nil)
        } catch {
            return ("", error.localizedDescription)
        }
    }

    // MARK: - PDF

    private func extractFromPDF(url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        return text
    }

    // MARK: - DOCX (use NSAttributedString — native macOS support)

    private func extractFromDOCX(url: URL) throws -> String {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.docFormat
        ]
        // Try DOCX first (officeOpenXML), fall back to doc format
        if let attrStr = try? NSAttributedString(url: url, options: [
            .documentType: NSAttributedString.DocumentType.officeOpenXML
        ], documentAttributes: nil) {
            return attrStr.string
        }
        if let attrStr = try? NSAttributedString(url: url, options: options, documentAttributes: nil) {
            return attrStr.string
        }
        // Last resort: unzip and parse XML manually
        return try extractFromDOCXManual(url: url)
    }

    private func extractFromDOCXManual(url: URL) throws -> String {
        let tempDir = NSTemporaryDirectory() + UUID().uuidString
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", tempDir]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let xmlPath = tempDir + "/word/document.xml"
        guard FileManager.default.fileExists(atPath: xmlPath) else { return "" }

        let xmlData = try Data(contentsOf: URL(fileURLWithPath: xmlPath))
        let parser = XMLTextExtractor()
        return parser.extractText(from: xmlData, textTag: "w:t")
    }

    // MARK: - XLSX (unzip + parse shared strings + sheets)

    private func extractFromXLSX(url: URL) throws -> String {
        let tempDir = NSTemporaryDirectory() + UUID().uuidString
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", tempDir]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        var text = ""

        // Parse shared strings
        let sharedStringsPath = tempDir + "/xl/sharedStrings.xml"
        if FileManager.default.fileExists(atPath: sharedStringsPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: sharedStringsPath)) {
            let parser = XMLTextExtractor()
            text += parser.extractText(from: data, textTag: "t")
        }

        // Parse sheets
        let sheetsDir = tempDir + "/xl/worksheets"
        if let sheetFiles = try? FileManager.default.contentsOfDirectory(atPath: sheetsDir) {
            for sheet in sheetFiles.sorted() where sheet.hasSuffix(".xml") {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: sheetsDir + "/" + sheet)) {
                    let parser = XMLTextExtractor()
                    text += "\n" + parser.extractText(from: data, textTag: "v")
                }
            }
        }

        return text
    }

    // MARK: - PPTX (unzip + parse slides)

    private func extractFromPPTX(url: URL) throws -> String {
        let tempDir = NSTemporaryDirectory() + UUID().uuidString
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", tempDir]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        var text = ""
        let slidesDir = tempDir + "/ppt/slides"
        if let slideFiles = try? FileManager.default.contentsOfDirectory(atPath: slidesDir) {
            for slide in slideFiles.sorted() where slide.hasSuffix(".xml") {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: slidesDir + "/" + slide)) {
                    let parser = XMLTextExtractor()
                    text += parser.extractText(from: data, textTag: "a:t") + "\n\n"
                }
            }
        }

        return text
    }

    // MARK: - HTML

    private func extractFromHTML(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let attrStr = try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ], documentAttributes: nil) {
            return attrStr.string
        }
        // Fallback: strip tags manually
        let html = String(data: data, encoding: .utf8) ?? ""
        return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: - RTF

    private func extractFromRTF(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let attrStr = try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.rtf,
        ], documentAttributes: nil) {
            return attrStr.string
        }
        return ""
    }

    // MARK: - Image OCR

    private func extractFromImage(url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url) else { return "" }
        return try await ocr.recognizeText(from: image)
    }

    // MARK: - Chunking

    /// Split text into non-overlapping chunks (simple, fast, low memory)
    func chunk(text: String, modeId: UUID, sourceFileName: String,
               chunkSize: Int = 3000, overlap: Int = 0) -> [KnowledgeChunk] {

        let cleanText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return [] }

        // Simple: split by paragraphs, group into chunks
        let paragraphs = cleanText.components(separatedBy: "\n\n")
        var chunks: [KnowledgeChunk] = []
        var currentChunk = ""
        var index = 0

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if currentChunk.count + trimmed.count > chunkSize && !currentChunk.isEmpty {
                // Save current chunk
                chunks.append(KnowledgeChunk(
                    id: UUID(),
                    modeId: modeId,
                    sourceFileName: sourceFileName,
                    chunkIndex: index,
                    content: currentChunk,
                    keywords: fastKeywords(currentChunk)
                ))
                currentChunk = ""
                index += 1
            }
            if !currentChunk.isEmpty { currentChunk += "\n\n" }
            currentChunk += trimmed
        }

        // Last chunk
        if !currentChunk.isEmpty {
            chunks.append(KnowledgeChunk(
                id: UUID(),
                modeId: modeId,
                sourceFileName: sourceFileName,
                chunkIndex: index,
                content: currentChunk,
                keywords: fastKeywords(currentChunk)
            ))
        }

        return chunks
    }

    /// Fast keyword extraction — only keep unique words > 3 chars, capped at 50 keywords per chunk
    private func fastKeywords(_ text: String) -> [String] {
        var words = Set<String>()
        let stopWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can",
            "had", "her", "was", "one", "our", "has", "his", "how", "its",
            "may", "who", "did", "get", "let", "say", "she", "too", "use",
            "what", "this", "that", "with", "from", "have", "they", "been",
            "said", "each", "which", "their", "will", "other", "about",
            "does", "under", "into", "also", "than", "them", "then",
            "some", "could", "would", "make", "like", "just", "there"
        ]

        // Use enumerateSubstrings to avoid creating massive intermediate arrays
        text.lowercased().enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, stop in
            guard let word else { return }
            if word.count > 3 && !stopWords.contains(word) {
                words.insert(word)
            }
            if words.count >= 50 { stop = true }
        }

        return Array(words)
    }
}

// MARK: - XML Text Extractor Helper

private class XMLTextExtractor: NSObject, XMLParserDelegate {
    private var targetTag: String = ""
    private var texts: [String] = []
    private var currentText = ""
    private var isInsideTarget = false

    func extractText(from data: Data, textTag: String) -> String {
        targetTag = textTag
        texts = []
        currentText = ""
        isInsideTarget = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        return texts.joined(separator: " ")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == targetTag {
            isInsideTarget = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideTarget {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == targetTag {
            isInsideTarget = false
            let trimmed = currentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                texts.append(trimmed)
            }
        }
    }
}
