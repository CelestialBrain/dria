---
name: Bug Report
about: Report a crash or unexpected behavior
title: "Bug: "
labels: bug
---

**What happened?**
Describe what you were doing when the bug occurred.

**Steps to reproduce**
1.
2.
3.

**Expected behavior**
What should have happened?

**Debug log**
Paste the contents of your debug log here (Settings → General → Export Debug Logs):

```
(paste debug log here)
```

**Crash / hang logs**
Settings → General → **Recent Issues** lists any crash or hang logs (also at `~/Library/Logs/dria/`). Attach the most recent one if present.

If the app is *currently* hung (high CPU, unresponsive), grab a live stack first:
```bash
sample $(pgrep dria) 3 -mayDie > ~/dria-hang.txt
```
Attach `dria-hang.txt`.

**Screenshots**
If applicable, add screenshots.

**Environment**
- dria version:
- macOS version:
- AI provider:
