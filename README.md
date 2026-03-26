# dria

A stealth AI study assistant for **macOS** and **Windows**. Capture your screen, speak your questions, or copy exam text — dria answers using your uploaded study materials as context.

## Download

**macOS:** [dria-v1.7.1.dmg](https://github.com/CelestialBrain/dria/releases/latest) — drag to Applications, right-click → Open

**Windows / Cross-platform:** Build from source (see below)

## Platforms

| | macOS (`dria/`) | Windows (`desktop/`) |
|---|---|---|
| Framework | Swift / SwiftUI / AppKit | Tauri 2.x / Rust / HTML/CSS/JS |
| Install | DMG download | Build from source |
| System tray | NSStatusItem + marquee | Tray icon + answer overlay |
| Voice | Apple Speech (on-device) | Web Speech API |
| Desktop audio | ScreenCaptureKit | getDisplayMedia |
| Area capture | screencapture -i | Snipping Tool |
| Auto-update | Sparkle (EdDSA signed) | Tauri built-in |
| Features | 40/40 | 40/40 |

## Features (both platforms)

- **8 AI providers** — Google AI (free), Vertex AI, Claude, OpenAI, Groq, Mistral, Ollama (local), OpenRouter/xAI
- **Study modes** — per-subject modes with custom knowledge bases and separate chat history
- **RAG knowledge base** — import PDF, DOCX, PPTX, XLSX, HTML, RTF, Markdown, images
- **Voice input** — real-time transcription with waveform display (10 languages)
- **Desktop audio capture** — transcribe lectures/videos (Mic / Desktop / Both)
- **Area selection capture** — select just the question (like ⌘⇧4 / Snipping Tool)
- **Smart clipboard detection** — auto-detects MC, T/F, ID, Essay (3 sensitivity modes)
- **Auto-answer on copy** — detected questions sent to AI immediately
- **Two-tier answers** — short answer in overlay/marquee, full explanation in chat
- **Practice mode** — AI generates exam questions from your materials
- **Flashcard generator** — tap-to-flip study cards from knowledge base
- **Export chat** — save conversations as PDF (macOS) or text (Windows)
- **Drag & drop files** — drop documents to import into knowledge base
- **Stealth / Ghost mode** — adjustable text opacity, lock chat window
- **Configurable hotkeys** — all shortcuts customizable in Settings
- **Canvas/LMS detection** — auto-detects Canvas, Google Forms, Quizizz, Kahoot, Blackboard, Moodle, Schoology
- **Configurable copy mode** — short answer, full explanation, or marquee text
- **Launch at login** — toggle in Settings
- **Auto-update** — one-click updates (macOS: Sparkle, Windows: Tauri updater)
- **Local-only analytics** — opt-in usage stats, nothing leaves your device
- **Debug log export + bug report** — one-click troubleshooting

## Hotkeys

| macOS | Windows | Action |
|-------|---------|--------|
| `⌘⌥1` | `Ctrl+Alt+1` | Capture screen / select area |
| `⌘⌥2` | `Ctrl+Alt+2` | Send to AI |
| `⌘⌥3` | `Ctrl+Alt+3` | Toggle chat window |
| `⌘⌥0` | Configurable | Cycle study mode |
| `⌘⌥←` | — | Cancel AI request |

All hotkeys configurable in Settings.

## Setup

### macOS

**Install from DMG:**
1. Download [dria-v1.7.1.dmg](https://github.com/CelestialBrain/dria/releases/latest)
2. Drag `dria.app` to Applications
3. First launch: right-click → Open (bypasses Gatekeeper)
4. Settings → AI Model → paste your API key

**Build from source:**
```bash
git clone https://github.com/CelestialBrain/dria.git
cd dria
xcodebuild -project dria.xcodeproj -scheme dria -configuration Release build
```

**Requirements:** macOS 14.0+, Xcode 16+ (build only)

### Windows / Cross-platform

```bash
git clone https://github.com/CelestialBrain/dria.git
cd dria/desktop
npm install
npx tauri dev        # development
npx tauri build      # production (.exe / .msi)
```

**Requirements:** Node.js 18+, Rust 1.77+, [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)

### AI Provider Setup

| Provider | Key from | Cost |
|----------|----------|------|
| **Google AI** | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | Free (500 req/day) |
| **Vertex AI** | Google Cloud Console (service account JSON) | Pay-per-use |
| **Claude** | [console.anthropic.com](https://console.anthropic.com) | Pay-per-use |
| **OpenAI** | [platform.openai.com](https://platform.openai.com) | Pay-per-use |
| **Groq** | [console.groq.com](https://console.groq.com) | Free tier |
| **Mistral** | [console.mistral.ai](https://console.mistral.ai) | Free tier |
| **Ollama** | [ollama.com](https://ollama.com) — `ollama pull llama3.2` | Free (local) |
| **OpenRouter** | [openrouter.ai](https://openrouter.ai) | Pay-per-use (200+ models) |

## Usage

### Study Modes
1. Settings → Modes → "+" to create
2. Name it, set keywords for auto-detection
3. Add files (PDF, DOCX, PPTX, images, etc.)
4. dria chunks and indexes for RAG context

### During an Exam
1. Capture screen or select area → icon turns yellow
2. Send to AI → icon turns blue → green when answer arrives
3. Short answer appears in overlay — click to copy
4. Open chat for full explanation + follow-ups

### Voice Input
1. Click mic icon → speak → text appears in real-time
2. Right-click mic for audio source (Mic / Desktop / Both)
3. Pause between sentences — previous text preserved
4. Click mic to stop → hit Enter to send

### Auto-Answer
1. Click "Watching" in the toolbar
2. Copy any exam question → dria detects type and answers automatically

## Architecture

```
dria/
├── dria/                    ← macOS (Swift/SwiftUI)
│   ├── driaApp.swift
│   ├── AppState.swift
│   ├── Models/
│   ├── Services/
│   ├── Views/
│   └── Resources/CaseDigests/
├── dria.xcodeproj
├── desktop/                 ← Windows/cross-platform (Tauri)
│   ├── src/
│   │   ├── index.html
│   │   ├── css/app.css
│   │   └── js/{app,modes,tools}.js
│   └── src-tauri/
│       ├── src/lib.rs
│       ├── Cargo.toml
│       └── tauri.conf.json
├── appcast.xml              ← Sparkle update feed
├── README.md
└── LICENSE
```

## Bug Reports

1. Settings → General → **Export Debug Logs**
2. Settings → General → **Report Bug** → opens GitHub Issues
3. Paste debug log into the issue

## Built With

**macOS:** Swift, SwiftUI, AppKit, Sparkle 2.9, Apple Speech, ScreenCaptureKit, Vision, PDFKit, Carbon

**Windows:** Tauri 2.x, Rust, HTML/CSS/JS, Web Speech API, screenshots crate, arboard

## License

MIT
