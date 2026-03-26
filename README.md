# dria

A stealth macOS menu bar app for AI-assisted studying. Capture your screen, speak your questions, or copy exam text — dria answers using your uploaded study materials as context.

## Download

Get the latest release: [**dria-v1.7.0.dmg**](https://github.com/CelestialBrain/dria/releases/latest)

Drag `dria.app` to Applications. First launch: right-click → Open (or `xattr -cr /Applications/dria.app`).

## Features

- **Menu bar AI** — short answer scrolls in marquee, full explanation in chat window
- **8 AI providers** — Google AI (free), Vertex AI, Claude, OpenAI, Groq, Mistral, Ollama (local), OpenRouter/xAI
- **Voice input** — on-device speech transcription in 10 languages with real-time waveform display
- **Desktop audio capture** — transcribe lectures/videos via ScreenCaptureKit (Mic / Desktop / Both)
- **Area selection capture** — ⌘⇧4-style crosshair to select just the question
- **Study modes** — per-subject modes with custom knowledge bases and separate chat history
- **RAG knowledge base** — import PDF, DOCX, PPTX, XLSX, HTML, RTF, Markdown, images
- **Smart clipboard detection** — auto-detects MC, T/F, ID, Essay questions (3 sensitivity modes)
- **Auto-answer on copy** — detected questions sent to AI immediately
- **Practice mode** — AI generates exam questions from your materials
- **Flashcard generator** — tap-to-flip study cards from knowledge base
- **Export to PDF** — save conversations for study review
- **Drag & drop files** — drop documents onto the chat window to import
- **Stealth controls** — Ghost mode (10% opacity), lock chat window, configurable copy mode
- **Configurable hotkeys** — all shortcuts customizable in Settings
- **Auto-update** — Sparkle framework with EdDSA signed updates
- **Launch at login** — toggle in Settings
- **Per-mode chat history** — each subject has its own conversation
- **Canvas/LMS detection** — auto-detects exam platforms
- **Local-only analytics** — opt-in usage stats, nothing leaves your device
- **Ice/Bartender compatible**

## Hotkeys

All hotkeys use `⌘⌥` (Command+Option) as modifier. Configurable in Settings.

| Default | Action |
|---------|--------|
| `⌘⌥1` | Capture screen (full or area selection) |
| `⌘⌥2` | Send captured screen / clipboard to AI |
| `⌘⌥3` | Open/close chat popover |
| `⌘⌥0` | Cycle study mode |
| `⌘⌥←` | Cancel current AI request |

## Icon Status Colors

| Color | Meaning |
|-------|---------|
| White | Idle |
| Yellow | Screenshot captured — press ⌘⌥2 |
| Blue | Sending to AI... |
| Green | Answer ready (scrolling in marquee) |
| Red | Voice recording active |
| Cyan | Mode switched / question detected |

## Setup

### Requirements

- macOS 14.0+
- Xcode 16+ (to build from source)

### Install from DMG

1. Download [dria-v1.7.0.dmg](https://github.com/CelestialBrain/dria/releases/latest)
2. Drag `dria.app` to Applications
3. First launch: right-click → Open (bypasses Gatekeeper)
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
2. Create a free API key (no credit card needed)
3. In dria Settings → AI Model → select "Google AI (API Key)" → paste key

**Vertex AI (recommended for heavy use):**
1. Create a Google Cloud project with Vertex AI API enabled
2. Create a service account with Vertex AI User role
3. Download the JSON key file to `~/Library/Application Support/dria/sa-key.json`
4. In dria Settings → AI Model → select "Vertex AI (Service Account)"

**Claude (Anthropic):**
1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. In dria Settings → AI Model → select "Claude" → paste key

**OpenAI / Groq / Mistral / xAI:**
1. Get an API key from the provider
2. In dria Settings → AI Model → select provider preset → paste key

**Ollama (local, free, offline):**
1. Install [Ollama](https://ollama.com) and pull a model (`ollama pull llama3.2`)
2. In dria Settings → AI Model → select "Ollama (Local)"
3. No API key needed — runs entirely on your machine

**OpenRouter (200+ models):**
1. Get an API key from [openrouter.ai](https://openrouter.ai)
2. In dria Settings → AI Model → select "OpenRouter" → paste key

### Permissions

- **Screen Recording** — required for screen capture. Grant in System Settings → Privacy & Security → Screen & System Audio Recording
- **Microphone** — required for voice input. Prompted on first use
- **Speech Recognition** — required for voice transcription. Prompted on first use

If the app crashes on launch after denying a permission, run:
```bash
tccutil reset All com.dev.dria
```

## Usage

### Study Modes

Create a mode for each subject in Settings → Modes:
1. Click "+" to create a new mode
2. Name it, pick an icon, set keywords for auto-detection
3. Add files — PDF reviewers, DOCX notes, PPTX lectures, images
4. dria chunks and indexes the text for RAG context

### During an Exam

1. **⌘⌥1** — capture screen or select area (icon turns yellow)
2. **⌘⌥2** — send to AI (icon turns blue → green when answer arrives)
3. Short answer scrolls in menu bar — click to copy
4. Open popover for full explanation
5. **⌘⌥3** — open chat to ask follow-up questions

### Voice Input

1. Click the mic icon in the chat bar (or right-click to pick audio source)
2. Speak — text appears in real-time with waveform animation
3. Pause between sentences — previous text is preserved
4. Click mic again to stop — text stays in the field
5. Hit Enter to send

Audio sources: **Microphone** (your voice), **Desktop Audio** (lectures/videos), **Mic + Desktop** (both)

### Auto-Answer (Clipboard Mode)

1. Click "Watching" button in the chat bar
2. Copy any exam question from Canvas, Google Forms, etc.
3. dria detects the question type and answers automatically
4. Sensitivity: Normal / Sensitive / Catch All (in Settings → General)

### Tools Menu (wrench icon)

- **Practice Question** — AI generates an exam question from your materials
- **Flashcards** — tap-to-flip study cards
- **Export to PDF** — save chat history as PDF
- **Audio Source** — switch between Mic / Desktop / Both

### Stealth

Settings → Stealth:
- **Ghost mode** — marquee text at 10% opacity, nearly invisible
- **Lock chat window** — prevents accidental popover opens
- **Copy mode** — choose what's copied when clicking the icon (short answer / full / marquee)

## Supported File Types

| Format | Extensions |
|--------|-----------|
| Markdown | `.md` |
| Plain text | `.txt` |
| PDF | `.pdf` |
| Word | `.docx` |
| PowerPoint | `.pptx` |
| Excel | `.xlsx` |
| HTML | `.html`, `.htm` |
| RTF | `.rtf`, `.rtfd` |
| Images (OCR) | `.jpg`, `.png`, `.heic`, `.tiff` |

## Bug Reports

1. Go to Settings → General → Troubleshooting
2. Click **Export Debug Logs** — saves a `.txt` file with your settings and crash info
3. Click **Report Bug on GitHub** — opens an issue template
4. Paste the debug log into the issue

## Architecture

```
dria/
├── driaApp.swift              # App entry, menu bar, marquee, popover
├── AppState.swift             # Central state, hotkeys, AI, voice, modes
├── Models/
│   ├── ChatMessage.swift      # Chat messages (class, not struct)
│   ├── StudyMode.swift        # Mode definitions + built-in LLAW 113
│   ├── ModeFile.swift         # File metadata
│   ├── KnowledgeChunk.swift   # Indexed text chunks
│   └── AnalysisResult.swift   # Question analysis
├── Services/
│   ├── GeminiService.swift         # 8 AI providers (Vertex, Google, Claude, OpenAI-compat)
│   ├── VoiceInputService.swift     # Speech + ScreenCaptureKit audio
│   ├── ModeManager.swift           # Mode CRUD, file import, chunks
│   ├── FileImporter.swift          # Multi-format text extraction
│   ├── KnowledgeBaseService.swift  # RAG context building
│   ├── ScreenCaptureService.swift  # Silent + area capture (CGContext)
│   ├── ClipboardService.swift      # Clipboard monitoring + detection
│   ├── QuestionDetector.swift      # MC/TF/ID/Essay classification
│   ├── HotkeyService.swift         # Carbon global hotkeys
│   ├── AnswerCache.swift           # Cache repeated questions
│   ├── AnalyticsService.swift      # Local-only opt-in analytics
│   ├── OCRService.swift            # Apple Vision text recognition
│   ├── FocusDetector.swift         # Window title + LMS detection
│   ├── KeychainService.swift       # API key storage
│   └── UpdateChecker.swift         # Sparkle auto-updater
├── Views/
│   ├── PopoverView.swift           # Chat window + message bubbles
│   ├── SettingsView.swift          # 4-tab settings
│   ├── InputView.swift             # Chat input + voice wave + tools
│   └── ResponseView.swift          # AI response display
└── Resources/
    └── CaseDigests/                # Bundled LLAW 113 case files (34 cases)
```

## Built With

- Swift / SwiftUI / AppKit
- Google Generative AI Swift SDK
- Sparkle 2.9 (auto-updater)
- Apple Speech Framework (on-device transcription)
- ScreenCaptureKit (desktop audio)
- Apple Vision Framework (OCR)
- PDFKit
- Carbon (global hotkeys)
- ServiceManagement (launch at login)

## License

MIT
