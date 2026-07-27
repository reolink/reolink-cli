# Agent Setup — reolink-cli

Read this when an AI agent first encounters the plugin. By the time you see this file, the user has already extracted the release tarball and run `install.sh`, so the binaries and the plugin tree are already on disk. Your job is to confirm the install, then operate cameras via the skill.

**What you (the AI) should do, in order:**

1. **Part 1** — Verify the install (binaries on PATH, gateway reachable).
2. **Part 2** — Confirm the skill is loaded for your agent surface.
3. **Part 3–4** — Start the gateway and (first time only) add a camera.
4. **Part 5** — Echo installed versions back to the user.

If any step fails, do not silently continue — see **Part 6 — Troubleshooting** and surface the remedy.

---

## Part 1 — Verify CLI install

The user ran `./install.sh` from the release tarball; both binaries should now be at `~/.local/bin/` (or `%USERPROFILE%\.local\bin\` on Windows).

```sh
reolink-cli --version
command -v reolink-gateway
```

If `command not found`, the install prefix isn't on PATH:

```sh
# Unix
export PATH="$HOME/.local/bin:$PATH"
```

```powershell
# Windows PowerShell
$env:PATH += ";$HOME\.local\bin"
```

To **upgrade** the binaries, the user gets a fresh release tarball from their vendor, extracts it over the old one, and re-runs `./install.sh`. Re-running is idempotent — it overwrites `~/.local/bin/reolink-cli` and `reolink-gateway` in place.

If `~/.local/bin` is on PATH but the version is older than the skill expects (see Part 5), point the user at the new tarball — there is no in-place network upgrade in the trial release.

---

## Part 2 — Confirm the skill is loaded

The plugin tree (`SKILL.md`, slash commands, skill references) is already on disk after the install. How your agent surface sees it depends on the agent:

| Agent | Skill path |
|---|---|
| **Claude Code** | `~/.claude/plugins/cache/reolink-cli/reolink-cli/<version>/` (auto-loaded by `/plugin install`) |
| **Codex** | Symlinked into `~/.agents/skills/reolink-cli` by setup-codex on first install |
| **Gemini CLI** | `GEMINI.md` next to this file is treated as agent context |
| **Cursor / Windsurf** | `.cursor-plugin/` next to this file is auto-detected on workspace open |
| **Other** | Read `skills/reolink-cli/SKILL.md` next to this file as a system rule |

The canonical skill reference is the local file `skills/reolink-cli/SKILL.md` inside this plugin tree. When the user upgrades by re-extracting a new tarball, that file is replaced.

If the cached skill in your agent looks older than the local tarball plugin tree, ask the user to re-run their agent's plugin-refresh command (e.g. in Claude Code: `/plugin update reolink-cli`).

---

## Part 3 — Start the gateway

The gateway is mandatory for almost every control command. Start it once per session:

```sh
reolink-cli gateway start --addr 127.0.0.1:9000 &
```

Windows PowerShell:

```powershell
Start-Process -NoNewWindow reolink-cli -ArgumentList "gateway start --addr 127.0.0.1:9000"
```

If you see `gateway connect failed: Connection refused`, the gateway is not running — run the line above. The CLI's error message includes the exact start command for you, so you can paste it directly.

---

## Part 4 — First-time setup

### Initialize config

```sh
reolink-cli init
```

Creates `~/.config/reolink-cli/config.toml` and `aliases.toml` with secure permissions (0600). Skip if already done.

### Add a camera

Ask the user for the camera's IP address and admin username, then run:

```sh
reolink-cli device add front-door --host <camera-ip> --user <username>
# password is prompted interactively — never pass --password PLAIN
```

### Verify

```sh
reolink-cli --camera front-door ping
reolink-cli --camera front-door info
```

---

## Fixed-action entry points (per agent)

Each agent surface has a different way to trigger "known fixed actions" without going through AI intent mapping. The underlying shell command is always `reolink-cli ...` — the question is just how the user spells the shortcut.

| Agent | Fixed-action mechanism | Example |
|---|---|---|
| **Claude Code** | **Plugin-defined slash commands** (the seven listed below) — type `/` for autocomplete | `/reolink-cli:status` |
| **Codex** | No plugin-defined slash commands. Call the binary directly, or use natural language routed through the skill. | `!reolink-cli status` or "check current status" |
| **Cursor** | No plugin slash commands. Same as Codex — call the CLI or ask via the `.cursor/rules/` skill. | `reolink-cli status` in terminal |
| **GitHub Copilot** | No extensible slash commands (`/explain` `/fix` `/tests` are platform built-ins, not pluggable). Call the CLI, or ask naturally via `.github/copilot-instructions.md`. | Natural language OR shell |
| **Gemini CLI** | No plugin slash commands. Skill loaded from `GEMINI.md`; speak naturally. | Natural language |
| **Any terminal** | Always the fastest (no LLM latency). | `reolink-cli status` |

### The seven slash commands (Claude Code only)

Once the plugin is installed in **Claude Code**, these seven deterministic commands are available in the chat — no natural-language phrasing needed. Type `/` to get autocomplete:

| Slash | Does |
|---|---|
| `/reolink-cli:status` | observability dashboard (fleet / gateway / monitor / cache / recent events) |
| `/reolink-cli:features` | what the CLI can do + example prompt phrasebook |
| `/reolink-cli:scan` | UDP-broadcast discover on local subnet |
| `/reolink-cli:devices` | list registered aliases |
| `/reolink-cli:cache-clean` | preview-then-delete artifacts in `~/.cache/reolink-cli/` (dry-run first; asks before `--apply`) |
| `/reolink-cli:update` | `reolink-cli self-update` — checks GitHub, replaces both binaries in place, no-op if current |
| `/reolink-cli:uninstall` | remove binaries (pass `purge` to also wipe user data) |

Slash commands run a single deterministic shell command — **no LLM intent mapping, no latency from AI thinking**. Use them when the intent is fixed ("show status", "scan the network"). For compound / fuzzy intents ("detect a person and play a voice alert"), keep talking to the skill in natural language — the AI maps that to the right chain of CLI commands.

**Why these seven aren't ported to Codex / Cursor / Copilot / Gemini:** those agents don't expose a plugin-defined slash command registry — only the host platform vendor can add slash commands (e.g., GitHub Copilot's `/explain`). Users on those agents have two equally-good paths: (a) type the CLI command directly (fastest, 0 AI latency), or (b) speak natural language routed through the skill. `reolink-cli features` prints a phrasebook of example prompts so non-Claude-Code users still see the exact intents the AI will understand.

## Uninstall

The release tarball ships its own `uninstall.sh` / `uninstall.ps1` scripts:

```sh
# macOS / Linux — from inside the extracted tarball directory
./uninstall.sh
```

```powershell
# Windows — from inside the extracted tarball directory
.\uninstall.ps1
```

By default the scripts are non-destructive — they remove the installed binaries from `~/.local/bin/` but keep config, aliases, cache, and rules. To **fully purge** user data, pass `--purge` on both platforms — `./uninstall.sh --purge` / `.\uninstall.ps1 --purge`. (There is no `REOLINK_PURGE` environment variable; the wrappers only forward arguments.)

Both scripts stop running `reolink-gateway` / `reolink-cli` processes whose binary lives under the install prefix before removing. Foreign processes (elsewhere on disk) are listed with PID but not killed — decide case by case.

**Agent-side plugin registration is NOT removed by the scripts** — it lives in the host agent's config and must be done there:

| Agent | Command |
|---|---|
| Claude Code | `/plugin uninstall reolink-cli` then `/plugin marketplace remove reolink-cli` |
| Codex | `codex marketplace remove reolink-cli` |
| Copilot | Delete `.github/copilot-instructions.md` in each workspace that registered the skill |
| Cursor / Gemini | Disable / remove in the host IDE's plugin settings |

## Part 5 — Report installed versions

After Parts 1–4 complete, run this block and echo the output back to the user so they can see exactly what's on their machine:

```sh
echo "--- reolink versions ---"
reolink-cli --version  || echo "reolink-cli: NOT ON PATH"
command -v reolink-gateway >/dev/null && echo "reolink-gateway: $(command -v reolink-gateway)" \
  || echo "reolink-gateway: NOT ON PATH"

echo "--- installed capabilities (machine-readable) ---"
# reolink-cli >= 0.2.8 ships a self-describing manifest. Parse this to gate
# command dispatch — don't invoke subcommands that aren't in .data.commands.
reolink-cli features --output json 2>/dev/null \
  || echo "(older binary — no 'features' command; check reolink-cli --help instead)"

echo "--- skill location (Claude Code) ---"
ls -d ~/.claude/plugins/cache/reolink-cli/reolink-cli/*/ 2>/dev/null \
  || echo "(not installed as Claude Code plugin)"

echo "--- cache usage (disposable artifacts) ---"
reolink-cli cache status --output json 2>/dev/null \
  || echo "(older binary — no 'cache' command)"
```

**Read `.data.commands`** from the `features` output before dispatching any subcommand. If a command in SKILL.md is missing from that list, the installed binary is older than the skill and the right response is to tell the user to upgrade by re-extracting their newest release tarball over the old one.

If the binary version on disk and the version named in `SKILL.md` (`version:` frontmatter, see the local skill file) disagree, tell the user — the skill might be describing capabilities the binary doesn't have yet (or vice versa). Both should match the version printed by `reolink-cli --version`.

---

## Part 6 — Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `command not found: reolink-cli` | Install succeeded but `~/.local/bin` is not on `PATH` | `export PATH="$HOME/.local/bin:$PATH"` and add the line to `~/.zshrc` / `~/.bashrc` |
| `error: no prebuilt binary for <os>-<arch>` (during install.sh) | Release tarball does not include this platform's binary | Ask the vendor for a build for your platform, or build from source |
| `gateway connect failed: Connection refused` | Gateway process not running | The CLI's error message prints the exact start command — paste and run it |
| Skill referenced commands that don't exist in `reolink-cli --help` | Agent loaded a stale cached skill (older than the binary) | Have the user run their agent's plugin-refresh command (Claude Code: `/plugin update reolink-cli`) |
| `reolink-cli --version` prints an older number than expected | Stale binary — no upgrade fired | Ask the vendor for the newest release tarball and re-run `./install.sh` from it |
| Windows: install.ps1 errors "file is in use" / `Copy-Item` locked | Running `reolink-cli.exe` / `reolink-gateway.exe` process holds the binary | install.ps1 auto-stops processes under `%USERPROFILE%\.local\bin`. Foreign processes (e.g., `C:\tools\reolink-cli.exe`) are listed with PID but not killed automatically — `Stop-Process -Id <pid> -Force` and re-run |
| `preview play` fails with `ffplay not found` | `ffmpeg` not installed | See the ffplay table below; all other commands still work |

When reporting any failure back to the user, include the exact error output — do **not** rewrite it into a vaguer summary.

---

## Optional dependency — ffplay

Only needed for `preview play` (live view). All other commands work without it.

| Platform | Install |
|----------|---------|
| macOS | `brew install ffmpeg` |
| Linux (Debian/Ubuntu) | `sudo apt-get install -y ffmpeg` |
| Linux (RHEL/Fedora) | `sudo dnf install -y ffmpeg` |
| Windows | `winget install ffmpeg` |

---

## Local file map

When the AI needs to read documentation deeper than this file, look at these local paths inside the plugin tree (no network calls required):

| Resource | Path (relative to this AGENTS.md) |
|----------|-----------------------------------|
| Canonical skill reference | `skills/reolink-cli/SKILL.md` |
| Per-topic recipe files | `skills/reolink-cli/references/` |
| Slash command definitions | `commands/` |
| Gemini-specific context | `GEMINI.md` |
