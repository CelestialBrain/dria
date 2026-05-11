//
//  ChatPDFExporter.swift
//  dria
//
//  Exports a chat history as a PDF file to the temp directory.
//

import AppKit
import Foundation

@MainActor
final class ChatPDFExporter {
    func export(history: [ChatMessage], modeName: String) -> URL? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dria-chat-\(modeName).pdf")

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50

        guard let context = CGContext(tempURL as CFURL, mediaBox: nil, nil) else { return nil }

        let textWidth = pageWidth - margin * 2
        var yPosition: CGFloat = pageHeight - margin
        let lineHeight: CGFloat = 16

        func newPage() {
            context.endPage()
            context.beginPage(mediaBox: nil)
            yPosition = pageHeight - margin
        }

        context.beginPage(mediaBox: nil)

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16)
        ]
        let title = "dria Chat Export — \(modeName)" as NSString
        title.draw(at: CGPoint(x: margin, y: yPosition - 20), withAttributes: titleAttr)
        yPosition -= 40

        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let roleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11)
        ]

        for msg in history {
            let role = msg.role == .user ? "You" : "dria"
            let roleText = "\(role):" as NSString
            let bodyText = msg.content as NSString

            let estimatedLines = Int(ceil(CGFloat(msg.content.count) / (textWidth / 6.5)))
            let blockHeight = CGFloat(estimatedLines + 1) * lineHeight + 10

            if yPosition - blockHeight < margin { newPage() }

            roleText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: roleAttr)
            yPosition -= lineHeight

            let rect = CGRect(x: margin, y: yPosition - blockHeight + lineHeight, width: textWidth, height: blockHeight)
            bodyText.draw(in: rect, withAttributes: bodyAttr)
            yPosition -= blockHeight + 5
        }

        context.endPage()
        context.closePDF()

        return tempURL
    }
}
