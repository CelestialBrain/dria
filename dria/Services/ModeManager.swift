//
//  ModeManager.swift
//  dria
//

import AppKit
import Foundation
import PDFKit

final class ModeManager {
    private let fileImporter = FileImporter()

    private var appSupportURL: URL {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/dria")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var configURL: URL { appSupportURL.appendingPathComponent("config.json") }

    private func modesDir(for mode: StudyMode) -> URL {
        let url = appSupportURL.appendingPathComponent("modes").appendingPathComponent(mode.directoryName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func filesDir(for mode: StudyMode) -> URL {
        let url = modesDir(for: mode).appendingPathComponent("files")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func chunksURL(for mode: StudyMode) -> URL {
        modesDir(for: mode).appendingPathComponent("chunks.json")
    }

    // MARK: - Load / Save Modes

    func loadModes() -> [StudyMode] {
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let modes = try? JSONDecoder().decode([StudyMode].self, from: data),
           !modes.isEmpty {

            // Check if LLAW mode needs seeding (has 0 files but should have bundled ones)
            if let llawIdx = modes.firstIndex(where: { $0.isBuiltIn && $0.name.contains("LLAW") }),
               modes[llawIdx].files.isEmpty {
                var updated = modes
                seedLLAWFiles(into: &updated[llawIdx])
                saveModes(updated)
                return updated
            }

            return modes
        }

        // First launch — seed synchronously so knowledge base is ready immediately
        let general = StudyMode.general
        var llaw = StudyMode.llawBuiltIn()
        seedLLAWFiles(into: &llaw)
        let defaults = [general, llaw]
        saveModes(defaults)
        return defaults
    }

    func saveModes(_ modes: [StudyMode]) {
        guard let data = try? JSONEncoder().encode(modes) else { return }
        try? data.write(to: configURL)
    }

    // MARK: - CRUD

    func createMode(name: String, iconName: String = "book.closed", colorHex: String = "5E5CE6",
                    keywords: [String] = []) -> StudyMode {
        let mode = StudyMode(
            id: UUID(),
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            systemPrompt: nil,
            keywords: keywords,
            isBuiltIn: false,
            createdAt: Date(),
            files: []
        )
        _ = modesDir(for: mode) // create directory
        return mode
    }

    func deleteMode(_ mode: StudyMode) {
        guard !mode.isBuiltIn else { return }
        try? FileManager.default.removeItem(at: modesDir(for: mode))
    }

    // MARK: - File Management

    func addFile(to mode: StudyMode, from sourceURL: URL) async -> (file: ModeFile, chunks: [KnowledgeChunk])? {
        let ext = sourceURL.pathExtension.lowercased()

        // Extract text directly from source (no copy needed)
        let imageExts = ["jpg", "jpeg", "png", "heic", "tiff"]
        let result: (text: String, error: String?)
        if imageExts.contains(ext) {
            result = await fileImporter.extractTextFromImage(url: sourceURL)
        } else {
            result = await fileImporter.extractText(from: sourceURL)
        }
        guard !result.text.isEmpty else { return nil }

        // Chunk
        let chunks = fileImporter.chunk(
            text: result.text,
            modeId: mode.id,
            sourceFileName: sourceURL.lastPathComponent
        )

        let file = ModeFile(
            id: UUID(),
            originalFileName: sourceURL.lastPathComponent,
            fileExtension: ext,
            addedAt: Date(),
            chunkCount: chunks.count
        )

        // Save chunks
        var existingChunks = loadChunks(for: mode)
        existingChunks.append(contentsOf: chunks)
        saveChunks(existingChunks, for: mode)

        return (file, chunks)
    }

    func removeFile(_ file: ModeFile, from mode: StudyMode) {
        // Delete the copied file
        let filePath = filesDir(for: mode).appendingPathComponent("\(file.id.uuidString).\(file.fileExtension)")
        try? FileManager.default.removeItem(at: filePath)

        // Remove chunks for this file
        var chunks = loadChunks(for: mode)
        chunks.removeAll { $0.sourceFileName == file.originalFileName }
        saveChunks(chunks, for: mode)
    }

    // MARK: - Chunks

    func loadChunks(for mode: StudyMode) -> [KnowledgeChunk] {
        let url = chunksURL(for: mode)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let chunks = try? JSONDecoder().decode([KnowledgeChunk].self, from: data) else {
            return []
        }
        return chunks
    }

    private func saveChunks(_ chunks: [KnowledgeChunk], for mode: StudyMode) {
        guard let data = try? JSONEncoder().encode(chunks) else { return }
        try? data.write(to: chunksURL(for: mode))
    }

    // MARK: - Seed Defaults

    private func seedDefaults() -> [StudyMode] {
        var llaw = StudyMode.llawBuiltIn()

        // Copy bundled case files into LLAW mode
        seedLLAWFiles(into: &llaw)

        return [.general, llaw]
    }

    private func seedLLAWFiles(into mode: inout StudyMode) {
        // Xcode flattens Resources subdirectories — all files are in bundle root
        guard let resourceURL = Bundle.main.resourceURL else { return }

        let supportedExts = ["md", "txt", "pdf", "docx"]
        var allChunks: [KnowledgeChunk] = []
        var files: [ModeFile] = []

        let allResources = (try? FileManager.default.contentsOfDirectory(
            at: resourceURL, includingPropertiesForKeys: nil
        )) ?? []

        // Filter to LLAW-related files (case_*, LLAW_*)
        let llawFiles = allResources.filter { url in
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            guard supportedExts.contains(ext) else { return false }
            return name.hasPrefix("case_") || name.hasPrefix("LLAW_") || name.hasPrefix("law_")
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

        for fileURL in llawFiles {
            let ext = fileURL.pathExtension.lowercased()
            let text = extractTextSync(from: fileURL)
            guard !text.isEmpty else { continue }

            let fileId = UUID()
            let destURL = filesDir(for: mode).appendingPathComponent("\(fileId.uuidString).\(ext)")
            try? FileManager.default.copyItem(at: fileURL, to: destURL)

            let chunks = fileImporter.chunk(text: text, modeId: mode.id, sourceFileName: fileURL.lastPathComponent)
            allChunks.append(contentsOf: chunks)

            files.append(ModeFile(
                id: fileId,
                originalFileName: fileURL.lastPathComponent,
                fileExtension: "md",
                addedAt: Date(),
                chunkCount: chunks.count
            ))
        }

        mode.files = files
        saveChunks(allChunks, for: mode)
    }

    /// Synchronous text extraction for seeding (runs at first launch)
    private func extractTextSync(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "txt":
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return "" }
            return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
        case "docx", "doc":
            if let attrStr = try? NSAttributedString(url: url, options: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML
            ], documentAttributes: nil) {
                return attrStr.string
            }
            return ""
        case "html", "htm":
            guard let data = try? Data(contentsOf: url),
                  let attrStr = try? NSAttributedString(data: data, options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ], documentAttributes: nil) else { return "" }
            return attrStr.string
        case "rtf", "rtfd":
            guard let data = try? Data(contentsOf: url),
                  let attrStr = try? NSAttributedString(data: data, options: [
                      .documentType: NSAttributedString.DocumentType.rtf,
                  ], documentAttributes: nil) else { return "" }
            return attrStr.string
        default:
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }
}
