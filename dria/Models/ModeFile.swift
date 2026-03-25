//
//  ModeFile.swift
//  dria
//

import Foundation

struct ModeFile: Identifiable, Codable, Hashable {
    let id: UUID
    let originalFileName: String
    let fileExtension: String       // "md", "txt", "pdf", "docx", "xlsx", "pptx", "jpg", "png"
    let addedAt: Date
    var chunkCount: Int

    var displayName: String {
        originalFileName
    }

    var iconName: String {
        switch fileExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "xlsx", "xls": return "tablecells"
        case "pptx", "ppt": return "rectangle.split.3x1"
        case "md", "txt": return "doc.plaintext"
        case "jpg", "jpeg", "png", "heic": return "photo"
        default: return "doc"
        }
    }
}
