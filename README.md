# dria

A stealth macOS menu bar app for AI-assisted studying. Capture your screen, copy exam questions, or type directly — dria answers using your uploaded study materials as context.

## Download

Get the latest release: [**dria-v1.3.0.dmg**](https://github.com/CelestialBrain/dria/releases/latest)

Drag `dria.app` to Applications. Done.

## Features

- **Menu bar AI** — answers scroll discreetly in your menu bar via marquee text
- **8 AI providers** — Google AI (free), Vertex AI, Claude, OpenAI, Groq, Mistral, Ollama (local), OpenRouter, xAI
- **Global hotkeys** — capture, send, chat, and cancel without switching apps
- **Study modes** — create modes per subject (LLAW 113, Math, Filipino, etc.) with custom knowledge bases
- **RAG knowledge base** — import PDF, DOCX, PPTX, XLSX, HTML, RTF, Markdown, images. dria chunks and indexes them for context-aware answers
- **Smart clipboard detection** — auto-detects Multiple Choice, True/False, Identification, and Essay questions when you copy text
- **Auto-answer on copy** — detected questions sent to AI immediately (3 sensitivity modes: Normal, Sensitive, Catch All)
- **Stealth controls** — adjustable text opacity (Ghost mode), lock chat window, icon color status indicators
- **Conversation memory** — chat history persists across restarts
- **Screen capture** — silent full-screen capture with cursor position marking
- **Canvas/LMS detection** — auto-detects exam platforms (Canvas, Google Forms, etc.)
- **Auto-update** — checks for new versions on launch, in-app download
- **Launch at login** — toggle in Settings
- **Local-only analytics** — opt-in usage stats, nothing leaves your device
- **Ice/Bartender compatible** — standard NSStatusItem API

## Hotkeys

All hotkeys use `⌘⌥` (Command+Option) as modifier. Configurable in Settings.

| Default | Action |
|---------|--------|
| `⌘⌥1` | Capture screen silently |
| `⌘⌥2` | Send captured screen / clipboard to AI |
| `⌘⌥3` | Open inline chat bar |
| `⌘⌥0` | Cycle study mode |
| `⌘⌥←` | Cancel current AI request |

## Icon Status Colors

| Color | Meaning |
|-------|---------|
| White | Idle |
| Yellow | Screenshot captured — press ⌘⌥2 |
| Blue | Sending to AI... |
| Green | Answer ready (scrolling in marquee) |
| Red | Error |
| Cyan | Mode switched / question detected |

## Setup

### Requirements

- macOS 14.0+
- Xcode 16+ (to build from source)

### Install from DMG

1. Download [dria-v1.3.0.dmg](https://github.com/CelestialBrain/dria/releases/latest)
2. Drag `dria.app` to Applications
3. Open dria — it appears in your menu bar
4. Go to Settings → AI Model → paste your API key

### Build from Source

```bash
git clone https://github.com/CelestialBrain/dria.git
cd dria
xcodebuild -project dria.xcodeproj -scheme dria -configuration Release build
```

Or open `dria.xcodeproj` in Xcode and press `⌘R`.

### AI Provider Setup

**Google AI (free, easiest):**
1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Create a free API key (no credit card)
3. In dria Settings → AI Model → select "Google AI (API Key)" → paste key

**Vertex AI (recommended for heavy use):**
1. Create a Google Cloud project with Vertex AI API enabled
2. Create a service account with Vertex AI User role
3. Download the JSON key file
4. Copy it to `~/Library/Application Support/dria/sa-key.json`
5. In dria Settings → AI Model → select "Vertex AI (Service Account)"

**Claude (Anthropic):**
1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. In dria Settings → AI Model → select "Claude" → paste key

**OpenAI / Groq / Mistral / xAI:**
1. Get an API key from the provider
2. In dria Settings → AI Model → select "OpenAI / Groq / ..." → pick preset → paste key

**Ollama (local, free):**
1. Install [Ollama](https://ollama.com) and pull a model (`ollama pull llama3.2`)
2. In dria Settings → AI Model → select "OpenAI / Groq / ..." → pick "Ollama (Local)"
3. No API key needed

**OpenRouter (200+ models):**
1. Get an API key from [openrouter.ai](https://openrouter.ai)
2. In dria Settings → AI Model → select "OpenAI / Groq / ..." → pick "OpenRouter" → paste key

### Permissions

On first launch, macOS will ask for **Screen Recording** permission. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording.

## Usage

### Study Modes

Create a mode for each subject in Settings → Modes:
1. Click "+" to create a new mode
2. Name it, set keywords for auto-detection (e.g., "canvas", "llaw", "oblicon")
3. Add files — PDF reviewers, DOCX notes, PPTX lectures, etc.
4. dria chunks and indexes the text for RAG

### During an Exam

1. **⌘⌥1** — silently captures your screen (icon turns yellow)
2. **⌘⌥2** — sends to AI (icon turns blue → green when answer arrives)
3. Answer scrolls in menu bar — click to copy
4. **⌘⌥3** — open inline chat to ask follow-up questions

### Auto-Answer (Clipboard Mode)

Enable in Settings → General → Smart Detection:
1. Turn on "Monitor clipboard for questions"
2. Turn on "Auto-answer on copy"
3. Set sensitivity (Normal / Sensitive / Catch All)
4. Copy any exam question — dria detects the type and answers automatically

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
├── driaApp.swift              # App entry, menu bar, marquee, inline chat
├── AppState.swift             # Main state, hotkeys, AI calls, modes
├── Models/
│   ├── ChatMessage.swift      # Chat + AttachmentCache
│   ├── StudyMode.swift        # Mode definitions
│   ├── ModeFile.swift         # File metadata
│   ├── KnowledgeChunk.swift
│   └── AnalysisResult.swift
├── Services/
│   ├── GeminiService.swift         # All AI providers (Vertex, Google, Claude, OpenAI-compatible)
│   ├── ModeManager.swift           # Mode CRUD, file import, chunk storage
│   ├── FileImporter.swift          # Text extraction + chunking
│   ├── KnowledgeBaseService.swift  # RAG context building
│   ├── ScreenCaptureService.swift  # Silent screen capture
│   ├── ClipboardService.swift      # Clipboard monitoring + question detection
│   ├── QuestionDetector.swift      # MC/TF/ID/Essay classification (3 sensitivity modes)
│   ├── FocusDetector.swift         # Window title + exam platform detection
│   ├── HotkeyService.swift         # Configurable global hotkeys
│   ├── AnalyticsService.swift      # Local-only opt-in analytics
│   ├── OCRService.swift            # Apple Vision text recognition
│   ├── KeychainService.swift       # API key storage
│   └── UpdateChecker.swift         # GitHub release auto-update checker
├── Views/
│   ├── PopoverView.swift           # Chat window + update banner
│   ├── SettingsView.swift          # 4-tab settings (Modes, AI, Stealth, General)
│   ├── InputView.swift             # Chat input bar
│   └── ResponseView.swift          # Message display
└── Resources/
    └── CaseDigests/                # Bundled LLAW 113 case files (34 cases)
```

## Built With

- Swift / SwiftUI / AppKit
- Google Generative AI Swift SDK
- Apple Vision Framework (OCR)
- PDFKit
- Carbon (global hotkeys)
- ServiceManagement (launch at login)

## License

MIT
