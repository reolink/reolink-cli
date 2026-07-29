---
description: Remove reolink-cli + reolink-gateway (keeps config by default; pass "purge" to wipe everything)
argument-hint: [purge]
---

Uninstall the reolink binaries. **Default behaviour is non-destructive** — keeps `~/.config/reolink-cli` (credentials, monitor rules), `~/.cache/reolink-cli` (snapshots), `~/.local/state/reolink-cli`. Full purge only if the user asks.

**If `$ARGUMENTS` contains "purge" or "--purge":** use the purge variant.
**Otherwise:** use the plain uninstall variant.

The release tarball ships its own `uninstall.sh` / `uninstall.ps1`. Run them from inside the extracted tarball directory:

**macOS / Linux — plain:**

```bash
./uninstall.sh
```

**macOS / Linux — purge:**

```bash
./uninstall.sh --purge
```

**Windows — plain:**

```powershell
.\uninstall.ps1
```

**Windows — purge:**

```powershell
.\uninstall.ps1 --purge
```

If the user no longer has the tarball on disk, falling back to manual removal works too:

```bash
# macOS / Linux — kill only the gateway from this install prefix,
# never gateways belonging to another installation
pkill -f "$HOME/.local/bin/reolink-gateway"
rm -f ~/.local/bin/reolink-cli ~/.local/bin/reolink-gateway
# (purge only)
rm -rf ~/.config/reolink-cli ~/.cache/reolink-cli ~/.local/state/reolink-cli
```

After the script runs, print the agent-side manual deregistration steps — they are mandatory because shell can't touch Claude Code / Codex / Copilot plugin state:

- Claude Code: `/plugin uninstall reolink-cli` then `/plugin marketplace remove reolink-cli`
- Codex: `codex marketplace remove reolink-cli`
- Copilot: delete `.github/copilot-instructions.md` in each workspace
- Cursor / Gemini: disable in the IDE's plugin settings
