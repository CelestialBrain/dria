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

## Verifications (ongoing — do before claiming "done" on related items)

- [ ] **V-1 Excel add-in actually loads on Mac Excel 16.x.** Sideload `manifest.xml` to `~/Library/Containers/com.microsoft.Excel/Data/Documents/wef/`, run `npx http-server src -S -p 3000`, confirm `=CHATGPT("hi")` returns. Without this we don't know if our `Authorization: Bearer` header trips JS-only-runtime non-simple-CORS.
- [ ] **V-2 Tauri `embeddings` feature compiles.** `cd desktop/src-tauri && cargo check --features embeddings`. Audit suspects conditional `tauri::generate_handler!` macro doesn't accept inline `#[cfg]` on idents.
- [ ] **V-3 Document Excel-for-Web as out of scope.** Public-host taskpane → `127.0.0.1` fetch fails PNA preflight + secure-context requirement. Tunneling is the only path and we won't ship it. Update `excel-addin/README.md`.

## Out of scope (audit flagged, deliberately skipped)

- **AppSource publication** — requires public privacy policy, EULA, support URL, partner-center verification. Pre-v2.x noise.
- **HNSW/IVF approximate-NN** — at 500 chunks × 512 dims, brute-force cosine is sub-5ms on M1. Pays back at 50K+ chunks, not now.
- **Bundling a 4B LLM in DMG** — 50MB DMG cap is firm. Opt-in download to App Support is OK later; Ollama-external is the right "offline mode" v1.

---

**Process note.** Each sprint ends with a Sparkle-signed release + version bump (1.7.5 rule from crash history: every fix needs a bump or Sparkle won't redownload). Start with Sprint 1 #1.
