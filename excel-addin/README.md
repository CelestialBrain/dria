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

## One-time setup (Excel for Mac / Windows / Web)

1. **Enable the bridge in dria**
   Open dria → Settings → General → Excel / External Integrations → toggle **Enable local bridge server** → **Copy** the auth token.

2. **Serve the add-in files locally over HTTPS** (Office requires HTTPS)
   ```bash
   cd excel-addin
   npx -y office-addin-dev-certs install   # one-time: trust local cert
   npx -y http-server src -S -C ~/.office-addin-dev-certs/localhost.crt \
                           -K ~/.office-addin-dev-certs/localhost.key \
                           -p 3000 --cors
   ```
   (Any HTTPS static server on `https://localhost:3000` works — Vite, lite-server, etc.)

3. **Sideload the manifest**
   - **Excel for Mac:** copy `manifest.xml` into
     `~/Library/Containers/com.microsoft.Excel/Data/Documents/wef/` (create the folder if missing). Restart Excel.
   - **Excel for Windows:** Insert → My Add-ins → Upload My Add-in → pick `manifest.xml`.
   - **Excel for Web:** Insert → Add-ins → Upload My Add-in → pick `manifest.xml`.

4. **Paste the token**
   Excel → Home tab → **dria Settings** → paste the bridge token → **Save** → **Test connection**.

5. **Try it**
   In any cell type `=CHATGPT("summarize the Civil Code rules on novation")` and press Enter.

## File layout

```
excel-addin/
├── manifest.xml         Add-in manifest (sideload this into Excel)
├── README.md
└── src/                 Static files served at https://localhost:3000/
    ├── functions.html   Loads functions.js into the custom-functions runtime
    ├── functions.js     CHATGPT / DRIA_CLASSIFY / DRIA_EXTRACT
    ├── functions.json   Metadata Excel reads to register the functions
    ├── taskpane.html    Settings UI (token, URL, test)
    └── commands.html    Ribbon button handler (Ask dria)
```

You also need three icon files in `src/`: `icon-16.png`, `icon-32.png`, `icon-80.png`. Any PNG works — use dria's menu bar icon.

## Security

- Bridge listens on `127.0.0.1:7842` only — never exposed off the machine.
- Every request requires `Authorization: Bearer <token>`.
- Token is generated once and stored at `~/Library/Application Support/dria/bridge-token` with `0600` perms.

## Troubleshooting

- **`#BUSY!` in cell, then `#VALUE!`** — bridge probably isn't running. Check dria → Settings → Excel.
- **`dria not configured`** — paste the token in the **dria Settings** task pane.
- **Test connection fails** — quit dria, relaunch, toggle the bridge off/on once. Confirm `curl http://127.0.0.1:7842/v1/ping` returns `{"ok":true}`.
- **CORS error in Excel for Web** — desktop Excel ignores CORS; web does not. The bridge sends `Access-Control-Allow-Origin: *`, which works for sideloaded add-ins.
