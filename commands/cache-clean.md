---
description: Preview + clean cached artifacts older than 7 days
argument-hint: [--older-than 30d]
---

Container mode: use the installed Docker-backed CLI entry on PATH. Otherwise, when `REOLINK_CONTAINER` is set, run the CLI commands below through the packaged `scripts/run-cli.sh` (`run-cli.cmd` on Windows), preserving their arguments. This operates on the selected container, not a native installation.

Clean old cache entries (snapshots, TTS PCM clips, etc.). The cache lives in the
platform cache directory — `~/.cache/reolink-cli/` on Linux,
`~/Library/Caches/reolink-cli/` on macOS, `%LOCALAPPDATA%\reolink-cli\cache\` on
Windows. Run `reolink-cli cache status` to see the resolved path rather than
assuming one.

**Step 1 — preview (dry-run, always first):**

Run `reolink-cli cache clean --output json` with any extra arguments in `$ARGUMENTS` (default retention is 7 d if none given). Show the candidate list with file count, total bytes, and the oldest file's age. Do NOT proceed to deletion yet.

**Step 2 — confirm:**

Ask the user to confirm deletion. Only if they explicitly say yes, proceed.

**Step 3 — apply:**

Re-run with `--apply` appended and show the deleted file count + freed bytes.

Never `--apply` without a confirmed dry-run output above it.
