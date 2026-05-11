# dria for Excel

Custom Excel functions that call dria's local bridge server.

## Functions

| Formula | Behavior |
| --- | --- |
| `=CHATGPT("prompt")` | Returns the answer into the cell |
| `=CHATGPT(A1, B1, "LLAW 113")` | Prompt = A1, extra context = B1, dria mode = LLAW 113 |
| `=DRIA_CLASSIFY(A1, "Spam,Personal,Work")` | Returns one label |
| `=DRIA_EXTRACT(A1, "the invoice total")` | Pulls a value out of text |
| Ribbon → **Ask dria** | Sends the selected cell to dria, writes the answer one row below |

## Supported Excel hosts

| Host | Loopback fetch | Local sideload | Status |
|---|---|---|---|
| **Excel for Windows** (16.x desktop) | ✅ WebView2 exempts loopback | ✅ `Insert → Upload My Add-in` works | **Primary supported target** |
| **Excel for Mac** (16.x desktop) | ✅ same Chromium rules | ⚠️ Local sideload broken on 16.83+ | **Tenant Centralized Deployment only** until Microsoft fixes sideload |
| **Excel for Web** (office.com) | ❌ public-to-local blocked by PNA + secure-context rules | n/a | **Not supported.** The taskpane runs in Microsoft's cloud; `fetch('http://127.0.0.1:7842')` is a public-to-local request blocked by Private Network Access + secure-context requirements. A tunnel (ngrok / Cloudflare Tunnel) would technically work but adds per-user setup and trusts a third party with your knowledge base content. |

At runtime the add-in detects `Office.context.platform` and shows an unsupported banner if loaded in Excel for Web.

### About Mac sideload

As of Excel for Mac 16.108 (2026), Microsoft has effectively disabled local manifest sideloading for developer testing: the `~/Library/Containers/com.microsoft.Excel/Data/Documents/wef/` auto-discovery path is silently ignored, and `office-addin-debugging start` generates a temp workbook that triggers "Add-in Error: This add-in is no longer available." This is a Microsoft platform restriction, not a manifest or code issue (the same manifest validates clean and is expected to load on Excel for Windows + via Centralized Deployment).

Available paths to ship on Mac: AppSource publication, EDU tenant Centralized Deployment, or wait for Microsoft to restore Mac sideload.

## One-time setup (Excel for Mac / Windows)

1. **Enable the bridge in dria**
   Open dria → Settings → General → Excel / External Integrations → toggle **Enable local bridge server** → **Copy** the auth token.

2. **Serve the add-in files locally over HTTPS** (Office requires HTTPS)
   ```bash
   cd excel-addin
   npx -y office-addin-dev-certs install   # one-time: trust local cert
   npx -y http-server src -S -C ~/.office-addin-dev-certs/localhost.crt \
                           -K ~/.office-addin-dev-certs/localhost.key \
                           -p 3443 --cors
   ```
   (Any HTTPS static server on `https://localhost:3443` works — Vite, lite-server, etc.)

3. **Sideload the manifest**
   - **Excel for Mac:** copy `manifest.xml` into
     `~/Library/Containers/com.microsoft.Excel/Data/Documents/wef/` (create the folder if missing). Restart Excel.
   - **Excel for Windows:** Insert → My Add-ins → Upload My Add-in → pick `manifest.xml`.

4. **Paste the token**
   Excel → Home tab → **dria Settings** → paste the bridge token → **Save** → **Test connection**.

5. **Try it**
   In any cell type `=CHATGPT("summarize the Civil Code rules on novation")` and press Enter.

## File layout

```
excel-addin/
├── manifest.xml         Add-in manifest (sideload this into Excel)
├── README.md
└── src/                 Static files served at https://localhost:3443/
    ├── functions.html   Loads functions.js into the custom-functions runtime
    ├── functions.js     CHATGPT / DRIA_CLASSIFY / DRIA_EXTRACT
    ├── functions.json   Metadata Excel reads to register the functions
    ├── taskpane.html    Settings UI (token, URL, test)
    └── commands.html    Ribbon button handler (Ask dria)
```

Icons (`icon-16.png`, `icon-32.png`, `icon-80.png`) are committed in `src/` — generated from dria's app icon.

## Security

- Bridge listens on `127.0.0.1:7842` only — never exposed off the machine.
- Every request requires `Authorization: Bearer <token>`.
- Token is generated once and stored at `~/Library/Application Support/dria/bridge-token` with `0600` perms.

## Troubleshooting

- **`#BUSY!` in cell, then `#VALUE!`** — bridge probably isn't running. Check dria → Settings → Excel.
- **`dria not configured`** — paste the token in the **dria Settings** task pane.
- **Test connection fails** — quit dria, relaunch, toggle the bridge off/on once. Confirm `curl http://127.0.0.1:7842/v1/ping` returns `{"ok":true}`.
- **CORS error in Excel for Web** — desktop Excel ignores CORS; web does not. The bridge sends `Access-Control-Allow-Origin: *`, which works for sideloaded add-ins.
