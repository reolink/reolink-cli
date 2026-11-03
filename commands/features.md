---
description: List what the installed reolink-cli can do + example prompts
---

Container mode: use the installed Docker-backed CLI entry on PATH. Otherwise, when `REOLINK_CONTAINER` is set, run the CLI commands below through the packaged `scripts/run-cli.sh` (`run-cli.cmd` on Windows), preserving their arguments. This operates on the selected container, not a native installation.

Run `reolink-cli features --output text` and **copy the full stdout into your reply as a fenced code block** (Claude Code auto-collapses long tool outputs, the user can't see the phrasebook unless it's inline in chat). Do not summarize or trim — the phrasebook is the whole point.
