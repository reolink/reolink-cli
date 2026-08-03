# Agent Setup — reolink-cli

Read this when an AI agent first encounters the plugin. Your job is to confirm the install, then operate cameras via the skill.

If the binaries are not on disk yet, the one-line installer fetches them and verifies the download against the checksum committed to this repository:

```sh
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh | sh
```

**What you (the AI) should do, in order:**

1. **Part 1** — Verify the install (binaries on PATH, gateway reachable).
2. **Part 2** — Confirm the skill is loaded for your agent surface.
3. **Part 3–4** — Start the gateway and (first time only) add a camera.
4. **Part 5** — Echo installed versions back to the user.

If any step fails, do not silently continue — see **Part 6 — Troubleshooting** and surface the remedy.

---

## Part 1 — Verify CLI install

Both binaries should be at `~/.local/bin/` (or `%USERPROFILE%\.local\bin\` on Windows).

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

To **upgrade**, run `reolink-cli self-update` (macOS and Linux). It checks the
latest release, replaces both binaries in place, and is a no-op when already
current. On Windows it exits with the download link instead: the archive is a
`.zip` and a running `.exe` cannot be replaced in place, so upgrade there by
extracting the new archive and running `install.ps1`.

Re-running the one-line installer is an equivalent upgrade path on any platform,
and is idempotent — it overwrites both binaries in place.

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

The canonical skill reference is the local file `skills/reolink-cli/SKILL.md` inside this plugin tree. Upgrading replaces that file.

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

**Read `.data.commands`** from the `features` output before dispatching any subcommand. If a command in SKILL.md is missing from that list, the installed binary is older than the skill and the right response is to tell the user to run `reolink-cli self-update`.

The skill carries no version of its own — it is distributed with the release archive, so its version is that release. Compare `reolink-cli --version` against the latest release instead.

---

## Part 6 — Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `command not found: reolink-cli` | Install succeeded but `~/.local/bin` is not on `PATH` | `export PATH="$HOME/.local/bin:$PATH"` and add the line to `~/.zshrc` / `~/.bashrc` |
| `error: unsupported OS '<os>'` / `error: unsupported arch '<arch>'` (during install.sh) | No release archive is published for this platform — see [Platform support](README.md#platform-support) | Build from source, or open an issue asking for the target |
| `Error relocating …: __res_init: symbol not found`, or `not found` running a binary that plainly exists | A glibc archive on a musl system (Alpine, Home Assistant OS) | Re-run `install.sh`; it detects musl and fetches the `-musl` archive. Downloading an archive by hand skips that detection. `file "$(command -v reolink-cli)"` says which one you have — "statically linked" is the musl build |
| `checksum mismatch for …` during install or `self-update` | Usually a truncated or proxy-mangled download | Retry once. If it fails again, **stop** and report it at the repository's security advisories page. Do not point `REOLINK_REPO` elsewhere or fetch the archive by hand — both skip the check that just fired |
| `no committed checksum file for <tag>` | A release published before its checksums were synced | Not something the user can fix; report it. The installers fail closed by design, so there is no flag to skip verification |
| Windows: `'iwr' is not recognized as an internal or external command` | The one-liner was pasted into the Command Prompt; `iwr`/`iex` are PowerShell aliases | Use the shell-agnostic form: `powershell -NoProfile -Command "iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 \| iex"` |
| `gateway connect failed: Connection refused` | Gateway process not running | The CLI's error message prints the exact start command — paste and run it |
| Skill referenced commands that don't exist in `reolink-cli --help` | Agent loaded a stale cached skill (older than the binary) | Have the user run their agent's plugin-refresh command (Claude Code: `/plugin update reolink-cli`) |
| `reolink-cli --version` prints an older number than expected | Stale binary — no upgrade fired | `reolink-cli self-update` (macOS/Linux), or re-run the one-line installer |
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
