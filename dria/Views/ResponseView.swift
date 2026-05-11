//
//  ResponseView.swift
//  dria
//

import SwiftUI

/// Hard cap on text shown in the chat bubble. Beyond this, we collapse and
/// let the user expand. Prevents SwiftUI layout spin on huge responses.
private let displayCharCap = 4000

struct ResponseView: View {
    @Environment(AppState.self) private var appState
    let text: String
    let isStreaming: Bool

    @State private var expanded = false

    private var displayText: String {
        if expanded || text.count <= displayCharCap { return text }
        return String(text.prefix(displayCharCap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStreaming && text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            } else if !text.isEmpty {
                Text(displayText)
                    .textSelection(.enabled)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                if text.count > displayCharCap {
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded
                             ? "Show less"
                             : "Show all (\(text.count - displayCharCap) more chars)")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                }

                HStack {
                    Spacer()
                    Button(action: {
                        appState.clipboard.skipNextChange = true
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
