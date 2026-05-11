# dria roadmap — post-v1.7.5 hardening

Derived from the audit in `docs/audit-2026-05-11.md` (Claude research report) and our own verification pass.

Ordering: value/effort, security-first.

---

## Sprint 1 — bridge security (target v1.7.6)

Three real bugs in the new `LLMBridgeServer`. ~7h total.

- [ ] **#1 Bind bridge to loopback only.** `NWParameters.acceptLocalOnly = true` constrains to the local *link*, not loopback. With VPN/Docker bridge interfaces present, the bridge can accept off-machine connections. Fix: `parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 7842)`; add separate `::1` listener; reject non-loopback remote endpoints in the accept handler. Verify with `lsof -iTCP:7842`. [`LLMBridgeServer.swift::start`]
- [ ] **#2 Replace wildcard CORS with allowlist.** `Access-Control-Allow-Origin: *` lets any visited site hit `127.0.0.1:7842` and read responses. Echo Origin only when matching: `https://localhost:3000`, `https://*.officeapps.live.com`, `https://outlook.office.com`, `https://outlook.office365.com`, `https://*.office.com`. Never reflect or accept the bridge token in a CORS-readable header. [`LLMBridgeServer.swift::corsHeaders`]
- [ ] **#3 Move bridge token to Keychain.** `~/Library/Application Support/dria/bridge-token` is Spotlight-indexed, Time-Machine-backed, and survives in iCloud drive backups. Store with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; delete on-disk token; mark App Support dir excluded from backup as defense in depth. [`LLMBridgeServer.swift::loadOrGenerateToken`, new `BridgeTokenStore.swift`]

## Sprint 2 — stability + quality (target v1.7.7)

~8h total. Two adoption swaps that pay back for years.

- [ ] **#4 Replace hand-rolled CrashReporter with KSCrash.** Hand-rolled `sigaction` handlers can't safely catch stack-overflow SIGSEGV (need `sigaltstack` setup) or `__abort()` (resets to SIG_DFL before raise). KSCrash uses Mach exception ports on a dedicated thread + has built-in main-thread deadlock monitoring → real backtraces for our HangWatchdog reports. ~500KB-1MB DMG growth. Keep local-only on-disk JSON; no hosted backend. [`CrashReporter.swift`, `HangWatchdog.swift`]
- [ ] **#5 Switch to `NLContextualEmbedding`.** `NLEmbedding.sentenceEmbedding` is already a 512-dim transformer (better than I thought), but `NLContextualEmbedding` (macOS 14+, our minimum) is the modern multi-script replacement. Drop-in API; same cosine path; zero DMG growth. Reindex on first launch. [`KnowledgeBaseService.swift::embed`, `AppState.swift::prepareEmbeddings`]

## Sprint 3 — backlog (target v1.8.0 or later)

Real but lower priority. ~14h total.

- [ ] **#6 HangWatchdog: raise to 60s + `beginLongOperation`/`endLongOperation`.** 20s falses on cold NLEmbedding init, 100-file KB reindex, Vertex token mint on flaky network, large PDF OCR. Wrap known-slow paths in named operations; only fatal when operation counter is zero AND main hasn't ack'd in 60s. [`HangWatchdog.swift::tick`]
- [ ] **#7 Harden HTTP parser (RFC 9112 compliance).** Reject CL+TE both, duplicate Content-Length, bare CR/LF in headers, whitespace before colon. Enforce 8KB header cap, 10s header-timeout, 30s body-timeout. `defer { connection.cancel() }` in every error path. Add ~20 targeted unit tests for negative cases. [`LLMBridgeServer.swift::parseRequest`]
- [ ] **#8 Prompt-injection mitigation for `/v1/classify` + `/v1/extract`.** Wrap user text in `<user_input nonce="…">…</user_input>` with per-request random nonce. Require JSON-schema-validated output; reject and re-prompt on failure. [`LLMBridgeServer.swift::handleClassify`, `::handleExtract`]
- [ ] **#9 AppState `@MainActor` + concurrency audit.** Background-task mutation of `@Observable` state is a Swift 6 data race. Annotate class `@MainActor`; move embed/OCR/KB compute into `Task.detached` returning Sendable summaries; store + cancel current RAG task on mode switch. Build clean under `-strict-concurrency=complete`. [`AppState.swift::prepareEmbeddings`, `::switchMode`]
- [ ] **#10 Tauri updater + minisign on parity with Sparkle.** One GitHub Action emits both `appcast.xml` (Sparkle, macOS) and `latest.json` (Tauri, Windows) from the same release. [`desktop/src-tauri/tauri.conf.json`, `.github/workflows/release.yml`]

## Verifications (results)

- [x] **V-2 Tauri `embeddings` feature compiles.** `cargo check --features embeddings` succeeded on the first try. fastembed v4.9.1 + ort 2.0.0-rc.9 + tokenizers 0.21.4 all build. The audit's concern about `tauri::generate_handler!` not accepting `#[cfg]` was wrong — duplicating the whole `invoke_handler` arm under two `#[cfg]` blocks works fine.
- [x] **V-3 Excel-for-Web documented as out of scope.** Added support matrix to `excel-addin/README.md` and a runtime banner in `taskpane.html` that shows an unsupported notice when `Office.context.platform === Office.PlatformType.OfficeOnline`.
- [ ] **V-1 Excel-for-Mac sideload — BLOCKED, not by our code.** Tested on **Excel for Mac 16.108.3 (build 16.108.26050324)**. Manifest validates clean (`npx office-addin-manifest validate` passes), HTTPS dev server serves all 6 assets with 200, dev certs trusted. Tried two sideload paths:
  1. **`~/Library/Containers/com.microsoft.Excel/Data/Documents/wef/manifest.xml` drop** — silently ignored. No dria group in the Home tab ribbon after full Excel quit + cache wipe + relaunch.
  2. **`npx office-addin-debugging start manifest.xml desktop --app excel`** — generated a temp `.xlsx` embedding the manifest reference. Excel opens it, shows **"Add-in Error: This add-in is no longer available"** dialog. The embedded reference fails to resolve back to the manifest.

  **Root cause** is Microsoft's tightening of Mac Excel local sideload in 16.83+. The `wef/` auto-discovery path is deprecated; `Insert → Upload My Add-in` is being phased out; Centralized Deployment requires an M365 tenant admin. This is consistent with OfficeDev/office-js issues #4823 and similar reports throughout 2025/2026. **Not a dria bug — a Microsoft platform restriction.**

  **Available paths forward**:
  - **AppSource publication** — 3–5 business days per submission, requires public privacy policy URL, public EULA URL, public support URL, Partner Center developer verification, Microsoft 365 schema-1.1+. Out of scope for v1.x.
  - **EDU tenant Centralized Deployment** — when a university customer asks; tenant admin pushes the manifest. Zero developer work.
  - **Excel for Windows** — `wef/`-equivalent (`%AppData%\Microsoft\Office\PRoamcache\PRoamingState_...\WEF`) + `Insert → Upload My Add-in` still work as of Excel 2024. Test there next.
  - **Wait for Microsoft to restore Mac sideload** — no public ETA.

  **Decision**: The Excel integration code is correct (manifest passes validation, server serves the assets, the bridge endpoints work). The blocker is at the platform layer. **Mark the Excel add-in as "Windows + Centralized Deployment supported; Mac sideload pending Microsoft fix" in `excel-addin/README.md`.** Move on to Sprint 2.

## Out of scope (audit flagged, deliberately skipped)

- **AppSource publication** — requires public privacy policy, EULA, support URL, partner-center verification. Pre-v2.x noise.
- **HNSW/IVF approximate-NN** — at 500 chunks × 512 dims, brute-force cosine is sub-5ms on M1. Pays back at 50K+ chunks, not now.
- **Bundling a 4B LLM in DMG** — 50MB DMG cap is firm. Opt-in download to App Support is OK later; Ollama-external is the right "offline mode" v1.

---

**Process note.** Each sprint ends with a Sparkle-signed release + version bump (1.7.5 rule from crash history: every fix needs a bump or Sparkle won't redownload). Start with Sprint 1 #1.
