//
//  PopoverView.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

/// Shows custom DRIA icon for "sparkles", SF Symbol for everything else
struct ModeIcon: View {
    let iconName: String
    var size: CGFloat = 14

    var body: some View {
        if iconName == "sparkles" {
            Image(nsImage: {
                let img = NSImage(named: "MenuBarIcon") ?? NSImage()
                img.isTemplate = true
                return img
            }())
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
        } else {
            Image(systemName: iconName)
                .frame(width: size, height: size)
        }
    }
}

struct PopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                // Mode picker
                Menu {
                    ForEach(appState.modes) { mode in
                        Button(action: { appState.switchMode(to: mode) }) {
                            Label { Text(mode.name) } icon: { ModeIcon(iconName: mode.iconName) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        ModeIcon(iconName: appState.activeMode.iconName, size: 12)
                            .foregroundStyle(.tint)
                        Text(appState.activeMode.name)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .menuStyle(.borderlessButton)

                if let kb = appState.modes.first(where: { $0.id == appState.activeModeId }) {
                    Text("\(kb.files.count) files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: { appState.clearChat() }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(appState.chatHistory.isEmpty)

                SettingsLink {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: 32)

            // Update banner
            if appState.updateChecker.updateAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("v\(appState.updateChecker.latestVersion) available")
                        .font(.caption)
                    Spacer()
                    Button("Update") {
                        appState.updateChecker.downloadUpdate()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
            }

            Divider()

            // Chat area
            if appState.chatHistory.isEmpty && !appState.isStreaming {
                EmptyStateView(modeName: appState.activeMode.name)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            let messages = appState.chatHistory.suffix(30)
                            ForEach(Array(messages), id: \.id) { message in
                                MessageBubble(message: message)
                            }

                            if appState.isStreaming {
                                ResponseView(text: appState.currentResponse, isStreaming: true)
                                    .id("streaming")
                            }

                            if let error = appState.errorMessage {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text(error)
                                }
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(.horizontal)
                            }

                            // Invisible anchor at bottom
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                    }
                    .onAppear {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    .onChange(of: appState.chatHistory.count) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            InputView()
                .environment(appState)
        }
        .background(.ultraThinMaterial)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        let mode = appState.activeMode
                        let success = await appState.addFile(to: mode, from: url)
                        if success {
                            appState.onMarqueeUpdate?("📄 Imported \(url.lastPathComponent)")
                        }
                    }
                }
            }
            return true
        }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let modeName: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("DRIA — \(modeName)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("⌘⌥1 to capture screen\n⌘⌥2 to send to AI\n⌘⌥3 to switch modes")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .user {
                    VStack(alignment: .trailing, spacing: 6) {
                        // Screenshot thumbnail
                        if let imgData = AttachmentCache.shared.imageData(for: message.id),
                           let nsImage = NSImage(data: imgData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 200, maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        // Clipboard text preview
                        if let clip = AttachmentCache.shared.clipboardText(for: message.id), !clip.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.plaintext")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(clip.prefix(80)) + (clip.count > 80 ? "..." : ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(6)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        // Message text
                        if !message.content.isEmpty {
                            Text(message.content.count > 500 ? String(message.content.prefix(500)) + "..." : message.content)
                                .textSelection(.enabled)
                                .font(.body)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ResponseView(text: message.content, isStreaming: false)
                }

                if !message.referencedSources.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text("\(message.referencedSources.count) sources")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
