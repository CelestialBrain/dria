# DRIA

A stealth macOS menu bar app for AI-assisted studying. Capture your screen, copy exam questions, or type directly — DRIA answers using your uploaded study materials as context.

## Features

- **Menu bar AI** — answers scroll discreetly in your menu bar via marquee text
- **Global hotkeys** — capture, send, chat, and cancel without switching apps
- **Study modes** — create modes per subject (LLAW 113, Math, Filipino, etc.) with custom knowledge bases
- **RAG knowledge base** — import PDF, DOCX, PPTX, XLSX, HTML, RTF, Markdown, images. DRIA chunks and indexes them for context-aware answers
- **Smart clipboard detection** — auto-detects Multiple Choice, True/False, Identification, and Essay questions when you copy text
- **Auto-answer on copy** — optionally sends detected questions to AI immediately
- **Stealth controls** — adjustable text opacity (Ghost mode), lock chat window, icon color status indicators
- **Multi-provider AI** — Vertex AI (service account), Google AI (API key), or Claude API
- **Conversation memory** — chat history persists across restarts
- **Screen capture** — silent full-screen capture with cursor position marking
- **Canvas/LMS detection** — auto-detects exam platforms (Canvas, Google Forms, etc.)

## Hotkeys

All hotkeys use `⌘⌥` (Command+Option) as modifier. Configurable in Settings.

| Default | Action |
|---------|--------|
| `⌘⌥1` | Capture screen silently |
| `⌘⌥2` | Send captured screen / clipboard to AI |
| `⌘⌥3` | Open inline chat bar |
| `⌘⌥0` | Cycle study mode |
| `⌘⌥←` | Cancel current AI request |

## Setup

### Requirements

- macOS 14.0+
- Xcode 16+ (to build from source)
- A Gemini API key (free) or Google Cloud service account

### Build

```bash
git clone https://github.com/AntGravity-AI/dria.git
cd dria
xcodebuild -project dria.xcodeproj -scheme dria -configuration Release build
```

Or open `dria.xcodeproj` in Xcode and press `⌘R`.

### AI Provider Setup

**Google AI (free, easiest):**
1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Create a free API key
3. In DRIA Settings → AI Model → select "Google AI (API Key)" → paste key

**Vertex AI (recommended for heavy use):**
1. Create a Google Cloud project with Vertex AI API enabled
2. Create a service account with Vertex AI User role
3. Download the JSON key file
4. Copy it to `~/Library/Application Support/dria/sa-key.json`
5. In DRIA Settings → AI Model → select "Vertex AI (Service Account)"

**Claude (Anthropic):**
1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. In DRIA Settings → AI Model → select "Claude" → paste key

### Permissions

On first launch, macOS will ask for **Screen Recording** permission. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording.

If you get repeated permission prompts on each build, create a self-signed code signing certificate:

```bash
# Create cert
openssl req -x509 -newkey rsa:2048 -keyout /tmp/dria-key.pem -out /tmp/dria-cert.pem -days 3650 -nodes -subj "/CN=DRIA Dev"

# Import and trust
security import /tmp/dria-cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import /tmp/dria-key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/dria-cert.pem
```

Then set the signing identity to "DRIA Dev" in the Xcode project.

## Usage

### Study Modes

Create a mode for each subject in Settings → Modes:
1. Click "+" to create a new mode
2. Name it, set keywords for auto-detection (e.g., "canvas", "llaw", "oblicon")
3. Add files — PDF reviewers, DOCX notes, PPTX lectures, etc.
4. DRIA chunks and indexes the text for RAG

### During an Exam

1. **⌘⌥1** — silently captures your screen (icon turns yellow)
2. **⌘⌥2** — sends to AI (icon turns blue → green when answer arrives)
3. Answer scrolls in menu bar — click to copy
4. **⌘⌥3** — open inline chat to ask follow-up questions

### Auto-Answer (Clipboard Mode)

Enable in Settings → General → Smart Detection:
1. Turn on "Monitor clipboard for questions"
2. Turn on "Auto-answer on copy"
3. Copy any exam question — DRIA detects the type and answers automatically

### Stealth

Adjust in Settings → Stealth:
- **Ghost mode** — text at 10% opacity, nearly invisible
- **Lock chat window** — prevents accidental popover opens
- Icon color indicates status without any text

## Supported File Types

| Format | Extensions |
|--------|-----------|
| Markdown | `.md` |
| Plain text | `.txt` |
| PDF | `.pdf` |
| Word | `.docx`, `.doc` |
| PowerPoint | `.pptx`, `.ppt` |
| Excel | `.xlsx`, `.xls` |
| HTML | `.html`, `.htm` |
| RTF | `.rtf`, `.rtfd` |
| Images (OCR) | `.jpg`, `.png`, `.heic`, `.tiff` |

## Architecture

```
dria/
├── driaApp.swift          # App entry, menu bar, marquee, inline chat
├── AppState.swift         # Main state, hotkeys, AI calls, modes
├── Models/
│   ├── ChatMessage.swift  # Chat + AttachmentCache
│   ├── StudyMode.swift    # Mode definitions
│   ├── ModeFile.swift     # File metadata
│   ├── KnowledgeChunk.swift
│   └── AnalysisResult.swift
├── Services/
│   ├── GeminiService.swift      # Vertex AI, Google AI, Claude providers
│   ├── ModeManager.swift        # Mode CRUD, file import, chunk storage
│   ├── FileImporter.swift       # Text extraction + chunking
│   ├── KnowledgeBaseService.swift # RAG context building
│   ├── ScreenCaptureService.swift # Silent screen capture
│   ├── ClipboardService.swift   # Clipboard monitoring + question detection
│   ├── QuestionDetector.swift   # MC/TF/ID/Essay classification
│   ├── FocusDetector.swift      # Window title + exam platform detection
│   ├── HotkeyService.swift      # Global hotkey registration
│   ├── OCRService.swift         # Apple Vision text recognition
│   ├── KeychainService.swift    # API key storage
│   └── UpdateChecker.swift      # Version checking
├── Views/
│   ├── PopoverView.swift        # Chat window
│   ├── SettingsView.swift       # 4-tab settings
│   ├── InputView.swift          # Chat input bar
│   └── ResponseView.swift       # Message display
└── Resources/
    └── CaseDigests/             # Bundled LLAW 113 case files
```

## Built With

- Swift / SwiftUI / AppKit
- Google Generative AI Swift SDK
- Apple Vision Framework (OCR)
- PDFKit
- Carbon (global hotkeys)

## License

MIT
