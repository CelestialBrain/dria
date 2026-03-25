//
//  KnowledgeChunk.swift
//  dria
//

import Foundation

struct KnowledgeChunk: Identifiable, Codable {
    let id: UUID
    let modeId: UUID
    let sourceFileName: String
    let chunkIndex: Int
    let content: String
    let keywords: [String]          // pre-extracted lowercase tokens
}
