//
//  ModesTab.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

struct ModesTab: View {
    @Environment(AppState.self) private var appState
    @State private var selectedModeId: UUID?
    @State private var showingNewMode = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(appState.modes, selection: $selectedModeId) { mode in
                    Label { Text(mode.name) } icon: { ModeIcon(iconName: mode.iconName) }
                        .tag(mode.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: { showingNewMode = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)

                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedModeId == StudyMode.general.id || selectedModeId == nil)

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 160, maxWidth: 200)

            if let mode = selectedMode {
                ModeEditorView(modeId: mode.id)
                    .id(mode.id)
                    .environment(appState)
            } else {
                VStack {
                    Text("Select a mode")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingNewMode) {
            NewModeSheet(onAdd: { name, icon, color, keywords in
                appState.addMode(name: name, iconName: icon, colorHex: color, keywords: keywords)
            })
        }
        .onAppear {
            if selectedModeId == nil { selectedModeId = appState.activeModeId }
        }
    }

    private var selectedMode: StudyMode? {
        appState.modes.first(where: { $0.id == selectedModeId })
    }

    private func deleteSelected() {
        guard let mode = selectedMode else { return }
        appState.deleteMode(mode)
        selectedModeId = appState.modes.first?.id
    }
}

private struct NewModeSheet: View {
    var onAdd: (String, String, String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var iconName = "book.closed"
    @State private var colorHex = "5E5CE6"
    @State private var keywordsText = ""

    private let icons = ["book.closed", "leaf", "atom", "function", "globe.americas",
                         "heart.text.clipboard", "building.columns", "cpu", "music.note",
                         "paintpalette", "camera", "hammer", "chart.bar", "person.3"]

    var body: some View {
        VStack(spacing: 16) {
            Text("New Study Mode").font(.headline)

            TextField("Mode name (e.g., ENVI SCI)", text: $name)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 7), spacing: 8) {
                Image(nsImage: {
                    let img = NSImage(named: "MenuBarIcon") ?? NSImage()
                    img.isTemplate = true
                    return img
                }())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 32)
                    .background(iconName == "sparkles" ? Color.accentColor.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { iconName = "sparkles" }

                ForEach(icons, id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .background(iconName == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { iconName = icon }
                }
            }

            TextField("Auto-detect keywords (comma-separated)", text: $keywordsText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    let keywords = keywordsText.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased() }
                    onAdd(name, iconName, colorHex, keywords)
                    dismiss()
                }
                .disabled(name.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

struct ModeEditorView: View {
    let modeId: UUID
    @Environment(AppState.self) private var appState

    private var mode: StudyMode {
        appState.modes.first(where: { $0.id == modeId }) ?? .general
    }
    @State private var editedName: String = ""
    @State private var editedPrompt: String = ""
    @State private var editedKeywords: String = ""
    @State private var isImporting = false
    @State private var importProgress: String?

    var body: some View {
        Form {
            Section("Mode") {
                TextField("Name", text: $editedName)
                    .onChange(of: editedName) { _, val in
                        var m = mode; m.name = val; appState.updateMode(m)
                    }

                TextField("Keywords (comma-separated)", text: $editedKeywords)
                    .onChange(of: editedKeywords) { _, val in
                        var m = mode
                        m.keywords = val.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased() }
                        appState.updateMode(m)
                    }
            }

            Section("Custom AI Prompt (optional)") {
                TextEditor(text: $editedPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 80)
                    .onChange(of: editedPrompt) { _, val in
                        var m = mode; m.systemPrompt = val.isEmpty ? nil : val; appState.updateMode(m)
                    }
            }

            Section("Knowledge Base Files (\(mode.files.count))") {
                if mode.files.isEmpty {
                    Text("No files added. Click + to upload documents.")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                } else {
                    ForEach(mode.files) { file in
                        HStack {
                            Image(systemName: file.iconName)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(file.displayName)
                                    .font(.caption)
                                Text("\(file.chunkCount) chunks")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !mode.isBuiltIn {
                                Button(role: .destructive) {
                                    appState.removeFile(file, from: mode)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let progress = importProgress {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: openFilePicker) {
                    Label("Add Files", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            editedName = mode.name
            editedPrompt = mode.systemPrompt ?? ""
            editedKeywords = mode.keywords.joined(separator: ", ")
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .pdf, .plainText, .html, .rtf, .rtfd,
            .init(filenameExtension: "md")!, .init(filenameExtension: "docx")!,
            .init(filenameExtension: "doc")!, .init(filenameExtension: "pptx")!,
            .init(filenameExtension: "ppt")!, .init(filenameExtension: "xlsx")!,
            .init(filenameExtension: "xls")!,
            .jpeg, .png, .tiff, .heic,
        ]
        panel.allowsOtherFileTypes = true
        panel.message = "Select files to add to \(mode.name) knowledge base"

        guard panel.runModal() == .OK else { return }

        Task {
            for url in panel.urls {
                importProgress = "Importing \(url.lastPathComponent)..."
                let success = await appState.addFile(to: mode, from: url)
                if !success {
                    importProgress = "Failed: \(url.lastPathComponent)"
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
            }
            importProgress = nil
        }
    }
}
