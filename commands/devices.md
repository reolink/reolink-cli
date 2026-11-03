---
description: List registered Reolink aliases (from ~/.config/reolink-cli/aliases.toml)
---

Container mode: use the installed Docker-backed CLI entry on PATH. Otherwise, when `REOLINK_CONTAINER` is set, run the CLI commands below through the packaged `scripts/run-cli.sh` (`run-cli.cmd` on Windows), preserving their arguments. This operates on the selected container, not a native installation.

Run `reolink-cli device list --output json` and print each alias on one line as:

```
<alias>  <host|uid>  tags=[<tags>]  <description>
```

Omit the password/hasPassword column (the CLI already masks it; don't repeat what's sensitive). If the alias list is empty, tell the user to register one with `reolink-cli device add <alias> --host <ip> --user admin`.
