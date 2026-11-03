---
description: Reolink observability dashboard (fleet + gateway + monitor + cache + recent events)
---

Container mode: use the installed Docker-backed CLI entry on PATH. Otherwise, when `REOLINK_CONTAINER` is set, run the CLI commands below through the packaged `scripts/run-cli.sh` (`run-cli.cmd` on Windows), preserving their arguments. This operates on the selected container, not a native installation.

Run `reolink-cli status --output text` and **copy the full stdout into your reply as a fenced code block** so the user can read it without having to expand a collapsed tool-output panel. Do not reinterpret, summarize, or add commentary above the dashboard — it's already formatted for human reading.

If the user passed an alias as `$ARGUMENTS`, run `reolink-cli --alias $ARGUMENTS status --output text` instead so recent events get included.
