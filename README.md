# dria

A stealth AI study assistant for **macOS** and **Windows**. Capture your screen, speak your questions, or copy exam text — dria answers using your uploaded study materials as context.

## Download

| Platform | Download | Notes |
|----------|----------|-------|
| **macOS** | [dria-v1.7.5.dmg](https://github.com/CelestialBrain/dria/releases/latest) | Drag to Applications. First launch: right-click → Open |
| **Windows** | [dria-v1.0.0-setup.exe](https://github.com/CelestialBrain/dria/releases/tag/desktop-v1.0.0) | Run the installer. No build tools needed |
| **Windows (.msi)** | [dria-v1.0.0.msi](https://github.com/CelestialBrain/dria/releases/tag/desktop-v1.0.0) | Alternative MSI installer |

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
- **Semantic RAG** — on-device sentence embeddings (Apple `NLEmbedding`) with cosine similarity ranking; falls back to keyword TF-IDF when unavailable. No API key or network required.
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
- **Crash & hang logging** — uncaught exceptions, fatal signals, and main-thread hangs are written to `~/Library/Logs/dria/`. Hangs longer than 20 s force-crash to generate a real diagnostic report (Slack/Discord-style watchdog).
- **Excel add-in** — `=CHATGPT("prompt")`, `=DRIA_CLASSIFY(...)`, `=DRIA_EXTRACT(...)` and an **Ask dria** ribbon button, served by a local HTTPS bridge (127.0.0.1:7842, bearer-token auth). See [`excel-addin/README.md`](excel-addin/README.md).
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
1. Download [dria-v1.7.5.dmg](https://github.com/CelestialBrain/dria/releases/latest)
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
├── dria/                          ← macOS (Swift/SwiftUI)
│   ├── driaApp.swift              AppDelegate, menu bar, marquee, hotkeys
│   ├── AppState.swift             Central @Observable state hub
│   ├── Models/                    ChatMessage, StudyMode, KnowledgeChunk, …
│   ├── Services/
│   │   ├── AIProviderFactory.swift     Builds GeminiService for the active provider
│   │   ├── ChatPersistence.swift       Per-mode chat history in UserDefaults
│   │   ├── ChatPDFExporter.swift       Export chat as PDF
│   │   ├── CrashReporter.swift         NSException + signal handlers → log files
│   │   ├── HangWatchdog.swift          Main-thread responsiveness monitor
│   │   ├── EmbeddingService.swift      Local NLEmbedding sentence vectors
│   │   ├── EmbeddingsCache.swift       Persistent on-disk cache
│   │   ├── KnowledgeBaseService.swift  Semantic + keyword retrieval
│   │   ├── LLMBridgeServer.swift       Localhost HTTP for Excel add-in
│   │   ├── GeminiService.swift         Multi-provider AI client
│   │   ├── ScreenCaptureService.swift  CLI screencapture, cursor marking
│   │   ├── ClipboardService.swift      Smart question detection
│   │   ├── VoiceInputService.swift     Speech recognition + waveform
│   │   ├── ModeManager.swift, OCRService.swift, …
│   ├── Views/
│   │   ├── PopoverView.swift, InputView.swift, ResponseView.swift
│   │   └── Settings/              ← One file per tab (ModesTab, AISettingsTab, CustomizationTab, GeneralSettingsTab)
│   └── Resources/CaseDigests/
├── dria.xcodeproj
├── desktop/                       ← Windows/cross-platform (Tauri)
│   ├── src/
│   │   ├── index.html
│   │   ├── css/app.css
│   │   └── js/{app,modes,tools}.js
│   └── src-tauri/
│       ├── src/lib.rs
│       ├── src/embeddings.rs      ← fastembed scaffold (feature-gated)
│       ├── Cargo.toml
│       └── tauri.conf.json
├── excel-addin/                   ← Office add-in (custom Excel functions)
│   ├── manifest.xml
│   ├── src/{functions,taskpane,commands}.{html,js,json}
│   └── README.md
├── appcast.xml                    ← Sparkle update feed (EdDSA signed)
├── README.md
└── LICENSE
```

## Logs & diagnostics

dria writes its own logs to `~/Library/Logs/dria/`. Files are timestamped and never rotated automatically — delete from Settings → General → **Recent Issues → Clear all** when full.

| File pattern | Source | Contents |
|---|---|---|
| `crash-<ts>.log` | `CrashReporter` | Uncaught `NSException` (handler) or fatal POSIX signal (SIGSEGV/ABRT/BUS/ILL/FPE/TRAP). Includes app version, OS, name+reason, Swift stack symbols. macOS chains to its own `.ips` after we write. |
| `hang-<ts>.log` | `HangWatchdog` | Main-thread unresponsive ≥5 s. Warns; abort-crashes at ≥60 s with no active long-operation. Includes hang duration, active named long-operations (e.g. `prepareEmbeddings (500 chunks)`), watchdog-thread backtrace. |
| `hang-sample-<ts>.log` | `/usr/bin/sample` subprocess | Full symbolicated backtrace of the hung main thread, paired with each `hang-` log. Same data as running `sample <pid>` manually. |
| `excel-<ts>.log` | `handleAskExcelCell` (v1.7.12+) | One entry per ⌘⌥E invocation: prompt (truncated), raw AI response, post-preamble-stripper output. Diagnose "nothing happened in Excel" without guessing. |

Plus macOS's own `~/Library/Logs/DiagnosticReports/dria-*.ips` files when the app aborts.

### How to access

- **In-app** — Settings → General → **Recent Issues** lists crash + hang logs with View / Reveal-in-Finder / Clear-all. Excel traces aren't in this UI (they're not "issues" — they're operational traces).
- **Finder** — `⌘⇧G` → paste `~/Library/Logs/dria/`.
- **Terminal** —
  ```bash
  ls -lat ~/Library/Logs/dria/                # newest first
  tail -100 ~/Library/Logs/dria/excel-*.log    # latest Excel round-trips
  cat ~/Library/Logs/dria/crash-*.log          # all crash reports
  ```

### Bug reports

1. Settings → General → **Recent Issues** → view any crash or hang logs.
2. Settings → General → **Export Debug Logs** → bundled report.
3. Settings → General → **Report Bug** → opens GitHub Issues.
4. Attach the debug log and any relevant `~/Library/Logs/dria/` files.

**Live hang capture** — if the app is currently stuck at high CPU, grab a real stack before killing it:
```bash
sample $(pgrep dria) 3 -mayDie > ~/dria-hang.txt
```
Include `dria-hang.txt` in the issue.

## Built With

**macOS:** Swift, SwiftUI, AppKit, Sparkle 2.9, Apple Speech, ScreenCaptureKit, Vision, NaturalLanguage (`NLEmbedding`), Network.framework, PDFKit, Carbon

**Windows:** Tauri 2.x, Rust, HTML/CSS/JS, Web Speech API, screenshots crate, arboard

## License

MIT
