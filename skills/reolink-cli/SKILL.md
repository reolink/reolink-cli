---
name: reolink-cli
description: "Provides the only correct mechanism for operating Reolink network cameras locally — the installed `reolink-cli` binary plus its gateway. **You MUST consult this skill whenever the user wants to do anything with an IP / network / surveillance / doorbell camera on their LAN, even if they never say \"Reolink\"** — e.g. \"front-door cam\", \"garage camera\", \"IP camera at 192.168.x.x\", \"make it brighter\", \"stream URL\", \"too dark\", \"upside down\", \"upgrade firmware\", \"flash firmware\". Covers discovery, login, snapshots, live preview, PTZ, IR/spotlight/LEDs, image tuning, OSD, motion + AI detection (person/vehicle/pet/package), recording + SD-card status, VOD search/download, alarm events, user accounts, reboot, firmware upgrade, and RTSP/RTMP/FLV stream URLs (Frigate / Home Assistant / go2rtc / VLC). Do NOT trigger when the user names a competing brand (Nest, Ring, Wyze, Eufy, Amcrest, Hikvision, Arlo) or asks a generic networking / Frigate-config question not tied to operating a specific camera."
metadata:
  openclaw:
    requires:
      bins: ["reolink-cli", "reolink-gateway"]
    emoji: "📷"
    always: false
---

# Reolink Camera Operator

## Overview

Primary surface: `reolink-cli` (JSON stdout by default). Don't start the MCP server unless asked. When the user needs non-CLI access (browser, curl, other languages), point them at the gateway's `POST /api`.

**Slash commands (Claude Code only)** — prefer these for fixed/single-action intents; skip the intent-mapping overhead:

| Slash | Equivalent | When to use |
|---|---|---|
| `/reolink-cli:status` | `reolink-cli status` | user asks about current state / dashboard / "how are things" |
| `/reolink-cli:features` | `reolink-cli features` | user asks what the plugin can do / "what can it do" |
| `/reolink-cli:scan` | `reolink-cli discover` | scan local network / "scan" |
| `/reolink-cli:devices` | `reolink-cli device list` | list registered cameras |
| `/reolink-cli:cache-clean` | `reolink-cli cache clean` dry-run→apply | clear old snapshots / "clear cache" |
| `/reolink-cli:update` | `reolink-cli self-update` | upgrade to the latest release (checks GitHub, no-op if current) |
| `/reolink-cli:uninstall` | `reolink-cli setup --uninstall --purge` | complete uninstall |

**Claude Code runtime:** **Must** use the slash command when the user's intent matches one of these seven exactly — faster (no LLM latency), deterministic, and discoverable via `/` autocompletion.

**Other agents (Codex / Cursor / Copilot / Gemini):** these surfaces don't support plugin-defined slash commands, so the "slash-first" rule doesn't apply — skip straight to running the equivalent `reolink-cli …` CLI command directly. Skill-driven intent mapping handles everything else.

**All agents:** **Fall back to skill-driven CLI chaining** for compound / fuzzy intents ("announce when a person is detected", "make it brighter") that aren't covered by the slash list / seven fixed actions above.

**The gateway is mandatory for almost every control command.** The CLI routes through `127.0.0.1:9000` by default (set in `config.toml` under the platform config dir — `~/.config/reolink-cli/config.toml` on Linux, `~/Library/Application Support/reolink-cli/config.toml` on macOS, `%APPDATA%\reolink-cli\config.toml` on Windows — as `gateway-addr`). If you see `gateway connect failed: Connection refused`, the gateway isn't running — start it once:

```bash
reolink-cli gateway start --addr 127.0.0.1:9000 &
```

Works **without** the gateway: `device add|list|update|remove|resolve|show`, `config init`, `discover`, `features`, `doctor`, `cache status|clean` — everything that reads local config or talks to the network directly. (Verified by running each with no gateway listening.) Everything else (`ping`, `login`, `info`, `config get/set`, `image`, `osd`, `ptz`, `detect`, `light`, `audio`, `preview`, `snapshot`, `vod`, `events`, `users`, `system reboot`, `system upgrade`) needs the gateway up.

**Envelopes** — parse `.ok` on CLI, `.status` on gateway:

| Surface | Success | Error |
|---|---|---|
| CLI | `{ok:true, command, protocol, data}` | `{ok:false, error:{code, message, retryable}}` (stderr) |
| CLI batch | `{command, summary, results:[{camera, host, ok, data, error}]}` | per-target `ok` |
| Gateway `/api` | `{status:"success", data}` | `{status:"error", code, message}` (HTTP status == code) |

`references/` has topic-scoped recipe files. **Must** load only the one matching your task — `references/index.md` is the router. `references/troubleshooting.md` has diagnosis decision trees for failures.

## Ground Truth (Binding)

**Forbidden** stating or implying as factual: device reachability, login state, configuration values, capabilities, detection/AI types, event counts, VOD file existence, user accounts, or any observable camera state — **except** when derived from the JSON output of an **executed** `reolink-cli` command or gateway `POST /api` response within the current task.

**Forbidden**: demo-style lists, guessed layouts, synthetic values, fake success after errors/timeouts, prose/JSON mimicking CLI output without a real response, or "the device has X" when no `get`/`info`/`inventory`/`capabilities` has run.

**Must** when data is missing: state what's missing and the cause (no camera registered, gateway down, auth failed, device offline), then take one concrete recovery step (from Error Recovery table) or ask a single clarifying question. **Forbidden** padding with plausible-sounding defaults.

## Intent Interpretation

Resolve ambiguity before picking a command. If still unclear, **ask with options**.

| User says | Command | Why / caveat |
|---|---|---|
| add a user | `users add` | Device account, NOT a CLI camera entry |
| add a camera | `device add` | CLI camera entry (`~/.config/reolink-cli/aliases.toml`), NOT a device account |
| change password | `users passwd` (default) OR `device update` (CLI creds) | Ask which |
| blinking light | `light statusled` | Body LED |
| night vision | `light ir` | Invisible IR LED |
| spotlight | `light spotlight` (manual) OR `light whiteled` (alarm-triggered) | Same bulb, different wiring |
| too dark | `image tune --bright` first, check `light ir get` if night | Image tuning, not spotlight |
| upside down | `image flip set --flip` | Vertical |
| mirrored | `image flip set --mirror` | Horizontal |
| mask | `privacy mask` | Read current regions first |
| rename | `osd set --name` (on-screen) OR `config set device-name` (app) | Ask which |
| restart / reboot | `system reboot` | 30–60s offline |
| upgrade / flash firmware / OTA | `system upgrade <file.pak>` | ⚠️ bricking risk. Match model+hw_ver via `info`; GATEWAY reads the LOCAL file; auto windowed/stop-and-wait. Detail in `references/admin.md` |
| factory reset | — standalone; `system upgrade --factory-reset` resets *during* a flash | Standalone reset not in CLI; ask user to use Reolink app |
| kick off | `users remove` (permanent) OR `users passwd` + `system reboot` (evict session) | Active sessions survive `users remove` until reboot |
| snapshot | `snapshot [--file PATH]` | JPEG. **Parent directories are auto-created** by the binary (since v0.5.0) — do NOT pre-`mkdir -p` the destination. Same for `vod download` and `preview capture --file`. |
| **slow / how long / time taken / performance / latency / benchmark** | **`benchmark [--iterations N] [--phases ...] [--reuse-session]`** | Per-phase p50/p95/p99: connect, login, info, snapshot. `--reuse-session` for warm-path. Detail in `references/index.md`. |
| **cpu / memory / device load / is the camera overloaded / stuttering** | **`config get performance`** | Live reading from the device: `cpuUsedPercent`, `codeRate`, `netDataRate`. Read-only and instantaneous — two calls a second apart legitimately differ. Not every model implements it; those answer a device-level rejection. Distinct from `benchmark`, which times the **client** round trip, not the camera. |
| **rtsp / rtmp / flv address / stream URL / HA / Frigate / go2rtc / VLC** | **`stream url [--kind rtsp,rtmp,flv] [--stream main,sub,ext] [--with-auth]`** | Default `--kind rtsp --stream main`. `--with-auth` only when user explicitly wants one-shot pasteable URL. NVR: `device expand` then `--tag <nvr>`. Detail in `references/media.md`. |
| nvr with 8 channels / RLN sub-cameras / channel N | `device expand <nvr-name> [--yes \| --names A,B,C]` | **NVR only**. Registers one entry per channel, tagged with parent name. After: `--tag <nvr-name>` fans out. |
| **preview / take a look / watch N minutes / watch live** | **`preview play`** (opens ffplay window) | **DEFAULT to `play`, not `capture`.** User wants a live window, not a file. |
| record N seconds / save a clip / save it | `preview capture --packets ≈N×25` | Only when user explicitly says save / record / export. Packet count, not seconds; ~25 fps main, ~10 fps sub |
| 60-second preview (ambiguous!) | If user says "preview for N seconds/minutes" → `preview play --packets N×fps`. If user says "record N seconds" → `preview capture`. Ask if truly unclear. | Default to `play` when the verb is "preview/watch", `capture` only when the verb is "record/save/export" |
| volume | `audio volume set` (master) | Ask if they mean mute: `audio mute` |
| mute alarm | `audio mute` | Alarm audio only, not preview |
| person detection | `detect ai --type person` | Check `device inventory --capabilities` first |
| vehicle | `detect ai --type vehicle` | Not all models |
| turn on recording | `record schedule set --enable` | |
| record config / recording params / pre-record seconds / clip size | `record config get` | Read-only; cycle / pre/post record / package time |
| SD card / storage card / capacity / free space | `storage status` | Read-only; totalGB / remainGB / formatted / mounted |
| manual record / record now / start recording | — | **Not supported** on Reolink IPCs; fall back to `record schedule set --enable/--disable` |
| download yesterday / download recording | `vod search --since 24h` → `vod download NAME` | |
| any alarms / any alarms today | `events query --since 24h` | Requires gateway |
| voice alert / voice announcement / announce when someone arrives / play voice when a person is detected | `audio talk` (see `references/voice-alert.md`) | PCM16 LE mono only; needs `capabilities.audioTalk=1` |
| detect X do Y / automation / event trigger / detect-then-do | **Must** `events monitor init/check/run` with TOML rule. **Forbidden** ad-hoc bash `while + events query` loops — see `references/event-monitor.md`. |
| is the monitor running / has a rule fired / monitor status / what fired recently | `events monitor status` (pid + cursor + lastFires) or `events monitor history --last N` (JSONL tail) | Inspect the running daemon without restarting. `history` answers "has rule X fired today?" cheaply. |
| apply edited rules / reload rules | `events monitor reload` (Unix SIGHUP) | Re-reads TOML without dropping cursor. Invalid TOML keeps old rules + logs warn. On Windows, stop + run again — SIGHUP is Unix-only. |
| what can it do / what features / what's supported / `what can this CLI do` / what's new | `reolink-cli features` (add `--output text` for human view) | Lists installed commands + highlights since v0.2.8 + XDG paths. **Must** run this first to gate which subcommands exist on the user's binary |
| how much disk used / cache size / cache usage | `reolink-cli cache status` | Inspect `~/.cache/reolink-cli/` by category (snapshots/audio/captures/downloads/logs) |
| current status / how are things / system health / overview / dashboard | `reolink-cli status` | Fleet + gateway + events-monitor + cache. `--camera X` to include recent events. |
| is the gateway running / gateway status | `reolink-cli gateway status` | 500ms TCP probe; on `[DOWN]` prints exact `gateway start` to run. |
| check / diagnose / doctor / what's wrong / sanity check | `reolink-cli doctor` | 9 offline checks (binary, dirs, config, registry, perms, gateway TCP). Use FIRST when user says "broken". |
| tab completion / shell completion | `reolink-cli completions {bash\|zsh\|fish\|powershell\|elvish} > <path>` | Re-run after `self-update`. |
| **first-time setup / configure camera / set up reolink / how to use after install / how to get started** | **`reolink-cli config init`** then **`device add`** | `config init` writes default gateway addr; `device add <alias> --host <ip> --user admin` registers the first camera (password via prompt or `--password-stdin`). Then `--alias <name> login` to verify. |
| **uninstall / delete / remove reolink / clean up reolink** | **`reolink-cli setup --uninstall --purge`** | Removes binaries + config/cache/state + cross-agent skill dirs + Claude Code plugin registry. Drop `--purge` to keep config/cache/state (alias list preserved) — there is no `--keep-config` flag. The agent skill dirs are global (`~/.claude/skills/…`, `~/.agents/skills/…`): they are removed regardless of `REOLINK_PREFIX`, so uninstalling one copy of a side-by-side install unlinks the skill for both. If the customer still has the extracted tarball, `./uninstall.sh` in there is the symmetric alternative (it forwards straight to this same command; the uninstall flow only honours `--purge`, `--no-interactive` and `--prefix`). (Note: `npx skills remove reolink-cli` is rarely needed — `reolink-cli setup --uninstall` already wipes the agent skill dirs.) |
| skill stale / plugin cache stale / refresh skill | `reolink-cli plugin refresh` | Auto-detects agent (Claude Code / Codex / Cursor / Copilot / Gemini). Run when `features` reports `cache_state != in_sync`. |
| clean up / clear cache / delete old snapshots / clean cache | `cache clean [--older-than 7d] [--category X] [--apply]` | Dry-run by default — always preview first, run `--apply` only after the user sees the list |

## Workflow

**Default: just run the command.** The gateway daemon caches auth across CLI invocations, so the agent doesn't pay ping+login per command. Most user intents map to **one** CLI call (`info`, `get`, `apply`, `snapshot`, `stream url`, …).

**Forbidden** pre-fetching `<subcmd> --help` to "check what flags exist." The *Intent Interpretation* and *Command Reference* sections below, plus `references/<topic>.md`, already list every subcommand and its key flags; `reolink-cli features` enumerates the installed surface at runtime. **Must** dispatch the operative command directly. Only read `--help` if the command actually errored with an unknown-flag clap message. Each unnecessary `--help` round adds one full agent turn (~2–3 s of perceived user latency) for zero information gain — the user feels it, the CLI doesn't.

**Must** batch a single user intent into a single shell invocation when it needs multiple CLI commands. For sequences like "PTZ full sweep" (right→down→left→up→stop), "snapshot before/after a move", "info + capabilities + storage status", **or "health check + benchmark" / "doctor + benchmark" pairs**, chain them with `&&` (or `;` if you want continue-on-error) inside one Bash call — do **not** spawn N separate tool calls. Each extra tool call adds one full agent turn (~2–3 s). N=5 commands as one Bash = ~3 s perceived; N=5 commands as five tool calls = ~12 s perceived. The rule applies even when the commands are semantically distinct (e.g. `doctor` is local, `benchmark` hits the device) — the user asked for "both", so dispatch both in one shell line: `reolink-cli doctor && reolink-cli --camera X benchmark --iterations 3`. Independent prep checks for *unrelated* devices can still be parallel tool calls; the rule is about *one intent → one invocation*.

**MCP server is the fastest path for repeated calls.** `reolink-cli mcp-server` speaks JSON-RPC 2.0 over stdio (MCP protocol 2025-11-25, ~39 tools): identity (`camera_{ping,login,info,capabilities,discover}`), PTZ (`camera_ptz_{move,stop,presets,preset_goto,preset_set,preset_delete}`), light (`camera_light_{ir,statusled}_{get,set}`, `camera_light_spotlight_set`), audio (`camera_audio_{volume_get,volume_set,mute}`), detection (`camera_detect_{motion,ai}_{get,set}`), recording/storage (`camera_record_config_get`, `camera_storage_status`, `camera_vod_search`), events (`camera_events_query`), image/OSD (`camera_image_{flip,tune}_get`, `camera_image_flip_set`, `camera_osd_{get,set}`), users (`camera_users_list`), system (`camera_system_reboot`), plus `camera_config_{get,set}`, `camera_preview_capture`, `camera_snapshot` (JPEG to a file), and `camera_raw`. Benchmarked locally: 5 sequential `camera_info` calls take 52 ms via MCP vs 108 ms via 5 Bash spawns — ~52% faster, saving ~11 ms per call by avoiding process startup. **When to suggest MCP wire-up**: the user is going to do >3 ops in one conversation, or runs the agent in a tight loop. **How to wire it in Claude Code** (claude.json or settings):
```json
"mcpServers": {
  "reolink-cli": {
    "command": "reolink-cli",
    "args": ["mcp-server"],
    "env": { "REOLINK_GATEWAY_ADDR": "127.0.0.1:9000" }
  }
}
```
Pass `alias`, `host`, or `uid` per tool call to target a specific camera; the server validates input schemas and returns `{structuredContent, isError}` payloads. **Caveat**: the gateway must be running separately (MCP routes through it the same way the CLI does).

**`apply` recipes are one-shot.** For "set X to Y" intents, the `*** apply` subcommand does get → compare → (skip if idempotent) → set → verify internally and returns `{before, after, changed, verified}`. **Forbidden** running `get → set → get` manually, and **forbidden** running a separate `get` after an `apply` — the verify is already inside.

| Recipe | Replaces |
|---|---|
| `light ir apply --state auto\|on\|off` | manual ir get/set/get |
| `image flip apply [--flip\|--no-flip] [--mirror\|--no-mirror]` | manual flip get/set/get |
| `osd apply [--name] [--datetime] [--name-overlay]` | manual osd get/set/get |
| `detect motion apply [--enable] [--sensitivity N]` | manual motion get/set/get |
| `detect ai apply --type T [--sensitivity N]` | manual ai get/set/get |

**`ping` and `login` are NOT pre-steps. They are diagnostics.** The first command you actually need (`info`, `get`, `apply`, `snapshot`, …) does its own connect + auth via the gateway daemon. If that command's JSON has `error.code == "auth_required"`, re-run `login` once and retry. If it has `error.code == "connection_refused"` / `"timeout"` / `"no_route"`, that IS the same signal `ping` would give — no need to run `ping` again. **Forbidden** running `ping` followed by `login` followed by the real command on every turn; that's 3 round-trips for the work of 1. Only call `ping` standalone when the user explicitly asks "is camera X reachable?" or "why can't I connect?".

**Verify only when needed.** Re-`get` after a write **only** on capability-gated config SETs that can silently keep the old state (`light ir/whiteled/spotlight set`, `image flip/tune set`, `audio config`, `detect motion/ai set`, `osd set`, generic `config set`). **Forbidden** verifying after `apply` (already verified), `ptz move/stop/preset`, `system reboot`, `system upgrade` (confirm via `info` after the device reboots, not a re-`get`), `snapshot`, `preview *`, `stream url`, `audio mute/unmute/talk`, `vod download`, `users passwd`, `privacy mask set`. Full table in `references/troubleshooting.md#verify-rules`.

**Other safety rules** (kept verbatim — these break things if violated):

- **Target selectors are global options** (pre-subcommand). **Forbidden** positional. Priority: `--camera` > `--host` > `--uid` > env. Batch: `--tag`, `--cameras A,B`, `--all-devices`. **Must** pass `--channel N` for NVR.
- **Credential safety**: **Forbidden** `--password PLAIN` on argv. **Must** use `--camera <name>` (from `aliases.toml` 0600), `REOLINK_PASSWORD` env, or `--password-stdin`. If no camera registered and op isn't trivially read-only, ask user to run `device add` first.
- **Stored passwords are encrypted** (`RLENC1:…`, AES-256-GCM) with the key in `credentials.key` next to `aliases.toml`; a plaintext config is converted automatically on first use. Do **not** try to read a password out of `aliases.toml` — it is ciphertext, and there is no command that reveals it. Backing up or moving a config means copying **both** files; with only one of them the passwords are unrecoverable and must be re-entered via `device update <camera> --password-stdin`. If a command reports a password that "cannot be decrypted", the key file is missing or mismatched — that is not a wrong-password problem, so do not retry with guesses.
- **Pre-write read**: **Must** `get` current value before any write that's NOT covered by an `apply` recipe; confirm side effects from the table below; verify NVR channel.
- **Protocol**: `--protocol auto` is right almost always.
- **Battery devices on LAN (transparent wake)**: when `--uid` is given without `--host`, the gateway automatically runs the BC3.0 §F.2 wake handshake on UDP 2026 before login (in customer / no-P2P builds). **Forbidden** calling `reolink-cli wake` as a precondition — it is a hidden diagnostic command. **Must** just call `info` / `preview` / `ptz` / etc. with `--uid` and accept that the **first** call may take 2–8 s while the device boots; subsequent calls within the gateway session TTL reuse the live session and have no wake overhead.
- **Events monitor exclusivity**: when intent pairs trigger + action ("announce when a person is detected", "car detected → log"), **Must** use `events monitor init/check/run` with a TOML rule. **Forbidden** writing `while true; do events query…; done` shell loops — the rule engine already has debounce, parallel dispatch, SIGTERM draining, cursor bootstrapping, action-timeout, retry. See `references/event-monitor.md`.

## Global Options

`--host`/`--uid`/`--camera`/`--cameras A,B`/`--tag`/`--all-devices`, `--user`/`--password`/`--channel`, `--protocol auto`, `--output json|text`, `--gateway-addr HOST:PORT`, `--config-file`/`--cameras-file`. Env equivalents: `REOLINK_HOST/UID/ALIAS/USER/PASSWORD/CHANNEL/PROTOCOL/GATEWAY_ADDR/CONFIG_FILE/ALIASES_FILE`. Run `reolink-cli --help` or `<subcmd> --help` for exact flag shapes.

## Batch Operations

- **Must** keep the same selector throughout a workflow — the batch framework handles fan-out.
- **Forbidden** enumerating with `--tag` then switching to `--camera` inside the same workflow.
- Batch output has per-target `ok`; a single failure doesn't fail the batch. **Must** check `summary.failed > 0` and iterate `results[]`.

**Degenerate case:** when a batch selector (`--tag X`, `--cameras A`, `--all-devices`) resolves to *exactly one* device, the CLI emits the **single-target envelope** (`{ok, command, protocol, data}`), not the batch report. **Must** test `"summary" in response` to detect which shape you got. **Forbidden** assuming `results[]` exists.

## Error Recovery

| Error | Cause | Next step |
|---|---|---|
| `reolink-cli: command not found` | Binary not installed (installing the skill does not install the binary) | Run the install snippet in `references/setup.md` → **Install the `reolink-cli` binary**, then retry |
| `gateway connect failed: Connection refused` | Gateway not running | `reolink-cli gateway start --addr 127.0.0.1:9000 &` then retry |
| `ping` returns `reachable:false, reason:"timeout"` | IP not routable (cross-subnet / VPN not up / host off / firewall) | Tell user: verify VPN / check subnet; **do not** try `login` — it would hit the same timeout |
| `ping` returns `reachable:false, reason:"refused"` | Host reachable but port 9000 closed | Wrong port / wrong IP / gateway service not running on device |
| `ping` returns `reachable:false, reason:"no_route"` | No routing entry at all | Check `netstat -rn` / VPN |
| `ping` returns `skipped:true, reason:"uid only..."` | UID-only target | Expected — proceed directly to `login` |
| `device unreachable` (retryable) | Net drop / device off / wrong port | Re-`ping`; check sibling |
| `auth required` / `invalid credentials` | Wrong creds | `device update`; admin-reset via Reolink app if locked out |
| `invalid params` | Caller bug | Fix request, don't retry |
| `unsupported` | Firmware lacks feature | `device inventory --capabilities` to confirm; skip |
| `Connection reset` after `system reboot` | Expected | CLI swallows this one; re-ping after 30–60s |
| Remote (UID) login timeout | First-connect warm-up | Retry with `--timeout-secs 15+` |
| `wake timed out after 3 attempts: no response from device with uid X` | Battery device not reachable on the local broadcast domain | Verify device is on the same /24 as the gateway host, UDP 2026 not firewalled, device not depleted; **do not** retry tightly — each attempt already takes ~3 s and the device may genuinely be off-network |
| `device acknowledged wake (booting) but did not report ready within 30s` | MCU woke but Linux main failed to come up | Physical-side issue (battery low, firmware stuck); user must check the device |
| `no active session` (gateway) | Token expired | Re-login via `set auth.login` |
| HTTP 401 (gateway) | Missing `Authorization: Bearer` | Add header |
| HTTP 403 (gateway) | Token invalid/expired | Re-login |
| HTTP 410 on `/api/login` or `/api/request` | Old v0.1.1 endpoint | Use `POST /api` + Bearer |
| `users remove admin` fails | Device refuses removing last admin | Don't |
| `users passwd` permission error | Non-admin changing someone else's | Log in as admin |

## Command Reference

Signatures only — run `<cmd> --help` for flag details; see `references/<topic>.md` for per-feature examples.

**Discovery / Registry:** `discover`, `device list|resolve|show|add|update|remove|import|inventory|analyze|expand`, `config init`

**NVR multi-channel:** `device expand <nvr-name> [--yes | --names A,B,C] [--drop-parent]`. RLN-series only; one entry per channel auto-tagged with parent name.

**Identity:** `ping`, `login`, `info`, `capabilities`

**Config paths** (`config get/set PATH` with merge semantics):
`led`, `device-name`, `language`, `time-zone`, `time-format`, `network`, `osd`, `osd-format`, `system-general` (get-only).
*(The paths `image` / `audio` / `alarm` / `alarm-policy` / `ai` were removed — they were stubs. Use dedicated commands below.)*

**Preview / Snapshot:** `preview capture|play|start|stop`, `snapshot [-o FILE] [--stream]`

**Benchmark:** `benchmark [--iterations N] [--phases connect,login,info,snapshot] [--reuse-session] [--warmup M]` — per-phase p50/p95/p99/mean/stddev. Read-only.

**Doctor:** `doctor` — 9 sanity checks (binary, dirs, config.toml, registry, perms 0600, legacy cleanup, gateway TCP). Non-zero exit on fail. **Use first** for "broken" reports.

**Completions:** `completions {bash|zsh|fish|powershell|elvish}` — emits to stdout; redirect into shell's completion dir. Re-run after `self-update`.

**Gateway status:** `gateway status` — 500ms TCP probe of the resolved gateway-addr. Text shows `[LISTENING] / [DOWN] / [UNCONFIGURED]` + the `gateway start` command on down.

**Stream URLs:** `stream url [--kind rtsp,rtmp,flv] [--stream main,sub,ext] [--with-auth]` — defaults to `rtsp main`. `--with-auth` embeds creds (use only when user wants pasteable URL); without it ships sibling `user`/`password` JSON fields. NVR: `device expand` then `--tag <nvr> stream url`. RTSP path is `/Preview_{NN}_{main|sub|ext}`. Detail in `references/media.md`.

**Light:** `light {ir|statusled} {get|set --state auto|on|off}`, `light ir apply --state auto|on|off` (recipe; prefer for "set X"), `light spotlight set --enable|--disable [--duration]`, `light whiteled {get|set [--enable|--disable] [--brightness 0-100] [--alarm-mode] [--detect-type T,...]}`. *Caveat:* E-series can `ok:true` on `light ir set` while silently keeping old state — `apply` recipe surfaces this in `verified:false`; check `device inventory --capabilities` if write ignored.

**Image:** `image flip {get|set|apply [--flip|--no-flip] [--mirror|--no-mirror]}` (apply is the idempotent recipe), `image tune {get|set [--bright N] [--contrast N] [--saturation N] [--hue N] [--sharpen N]}` — all 0–255, 128 = neutral. If a user says "60%" that's `~160`.

**OSD:** `osd {get|set|apply [--name NAME] [--datetime|--no-datetime] [--name-overlay|--no-name-overlay]}` (apply is the idempotent recipe)

**System:** `system reboot`; `system upgrade <file.pak> [--factory-reset] [-y]` — flash firmware (gateway reads the LOCAL file; ⚠️ bricking risk, match model+hw_ver; auto windowed/stop-and-wait by capability; detail in `references/admin.md`)

**Users (device accounts):** `users list`, `users add NAME --level admin|user`, `users remove NAME`, `users passwd NAME`. Password via TTY prompt or `--password-stdin` — never `--password PLAIN`. Name + password each 1–31 chars. Non-admin users can only change their own password.

**Audio:** `audio config {get|set}`, `audio volume {get|set LEVEL}` (0–100), `audio mute`, `audio unmute`, `audio replies`, `audio talk {--file PATH | --stdin} [--sample-rate N]`. `audio volume` is master; `audio config.volume` is per-profile — ask which. `audio talk` pushes PCM16 LE mono to camera speaker via talkback (cmd 201 open + 202 stream). Gate on `capabilities.audioTalk=1`.

**Privacy:** `privacy mask {get|set [--enable|--disable] [--json JSON]}`. Get first to see current regions (device-pixel `{x,y,width,height}`).

**PTZ:** `ptz move DIR [--speed 1-64] [--duration-ms]`, `ptz stop`, `ptz preset {list|goto ID|set ID NAME|delete ID}`, `ptz {zoom|focus} {get|set --pos N}`, `ptz focus auto --enable|--disable`, `ptz patrol {list|start|stop}`, `ptz guard {get|set|snapshot|goto}`, `ptz autotrack {get|set [--enable|--disable] [--mode N] [--detect-type T,...] [--priority T,...]}`. Directions: `left|right|up|down|left-up|left-down|right-up|right-down`. Speed 1–64 (not %). If user says "speed 50" ask if it means % or literal.

**Recording:** `record schedule {get|set [--enable|--disable] [--fps 1-15] [--pre-time] [--plan-type daily|weekly] [--week-table BITMAP] [--start-hour H --start-min M --end-hour H --end-min M]}`, `record config get` (read-only: cycle / pre-record / post-record / packageTime). `--week-table` is 7-bit bitmap (Mon=bit0 … Sun=bit6); weekdays=31, Mon-Sat=63, all=127. **Manual start/stop not supported** — cmd 277/278/587/588 return 405.

**Storage:** `storage status` (read-only SD/HDD capacity + mount state). **Forbidden** format/init ops — direct users to the Reolink app if they need to format.

**VOD:** `vod search [--from ISO --to ISO | --since DURATION] [--type T,...] [--stream main|sub] [--limit N]`, `vod download NAME [-o FILE]`. Time must be **naive local ISO** (`YYYY-MM-DDTHH:MM:SS`, no TZ, no ms). Cross-month queries rejected — split per month. Filenames case-sensitive.
Types: `manual|sched|io|md|people|vehicle|face|dog_cat|visitor|other|package`

**Detection:** `detect motion {get|set|apply [--enable|--disable] [--sensitivity 0-100] [--use-pir|--disable-pir]}`, `detect ai {get|set|apply} --type TYPE [--sensitivity 0-100] [--stay-time SECS]`. `apply` is the idempotent recipe — prefer it for "set sensitivity to N"-style intent. AI types: `person|vehicle|dog_cat|package|cry` (subset varies by model).

**Notifications:** `notify push {get|set [--interval SECS] [--rich N] [--consent N]}`

**Events (gateway required):** `gateway start [--addr HOST:PORT]` once, then `events {query [--last N] [--after] [--since] [--types T,...] | stream [--timeout] [--types] | monitor {init|check|run|reload|status|history}}` with `--gateway-addr HOST:PORT`. `monitor` is the declarative rule engine — see `references/event-monitor.md`. **Event `--types` vocabulary is different from VOD `--type` vocabulary** — events use `motion|people|vehicle|face|dog_cat|visitor|package|cry` (no `md`, `sched`, `manual`, `io`, `other`). `md` is VOD-only. `--since` on `events query` accepts `<N>m|h|d` only (NOT seconds) — use `1m` minimum.

**WiFi:** `wifi get` — diagnostic: read current SSID / authMode / encryptType / channel / countryCode. The `key` field is always redacted to `""` by the device firmware. Use to confirm a previous `wifi set` actually applied (sometimes Phase 4 rediscover times out cross-subnet but the SET succeeded — `wifi get` confirms). `wifi set --ssid <SSID> {--psk <PSK> | --psk-stdin} [--no-test] [--no-update-registry] [--rediscover-timeout-secs <N> (default 90)] [--hidden]` — push new SSID+PSK; 4-phase orchestrator: (1) capability probe, (2) WifiTest pre-check, (3) commit, (4) BCDI rediscover + registry auto-update. Exit codes: 0 success / 3 auth/commit reject / 4 rediscovery timeout. Safety: device on wireless with `wifiTestAtWireless=0` cap will refuse without `--no-test`; the device itself also enforces this server-side. **Recommended path**: wired device → `wifi set --ssid X --psk-stdin` then echo PSK in. **Credential safety**: **Must** use `--psk-stdin` (pipe PSK via stdin) rather than `--psk PLAIN` on argv — same rule as passwords.

**Wake (diagnostic, hidden):** `wake --uid <UID> [--host <HOST>]` — send BC3.0 §F.2 UDP wake packet without logging in. Broadcast if `--host` is omitted. Marked `hide = true` in top-level help — appears only when explicitly queried (`wake --help`). Normal workflow does **not** need this; `info`/`login`/`ptz`/etc. auto-wake battery devices via the gateway. **Forbidden** calling `wake` as a pre-step before any of those commands.

**Raw:** `raw CMD [--body-xml|--ext-xml|--body-file|--ext-file]`.

**Self-description:** `reolink-cli features [--output json|text]` — prints the installed version, the list of subcommands this binary supports, feature highlights with their `since` version, and the XDG file layout. **Must** run this (or rely on AGENTS.md Part 5) before dispatching subcommands you haven't confirmed exist on the user's binary — skill docs track master, the binary may lag.

**Cache management:** `reolink-cli cache {status|clean}`. `status` reports per-category size + oldest/newest file timestamps under `~/.cache/reolink-cli/`. `clean [--older-than 7d] [--category audio|snapshots|captures|downloads|logs|all] [--apply]` lists candidates by default; add `--apply` to delete. `--older-than 0` matches every file. Empty date-bucket subdirs under `snapshots/` are auto-pruned.

## Gateway HTTP API

Single entry `POST /api` with `Authorization: Bearer <token>` and body `{action, path, params}`. Login is itself a call: `{action:"set", path:"auth.login", params:{username, password, host, protocol?, channel?}}` → `{status:"success", data:{token, info}}`. Streaming endpoints (`/api/events`, `/api/preview/video`, `/api/snapshot`, `/api/vod/download`) take `?token=` in the query for browser-native elements; the token supplies the device credentials server-side, so **never put `user`/`password` in a URL** (requests without a valid token are rejected 401/403). See `references/gateway-http.md` for curl recipes and the full spec.

## Side-effectful commands

**Must** confirm with the user before running any of these. **Forbidden** executing them opportunistically or as part of a read-only inspection flow:

| Command | Side effect |
|---|---|
| `ptz move|goto|patrol start|guard goto` | Physical motion |
| `light spotlight --enable`, `light whiteled --enable` | Bright visible light |
| `audio volume set` (high), `audio replies` triggers | Loud output |
| `privacy mask --disable` | Unmasks previously hidden regions |
| `system reboot` | 30–60s downtime; aborts in-flight |
| `users remove|passwd` (others) | Affects login; session persists until reboot |
| `record schedule --disable` | No new recordings |
| `detect motion|ai --disable` | No push / no white-LED trigger / no md-rule recording |
| `cache clean --apply` | Permanent file deletion under `~/.cache/reolink-cli/` — always preview with a dry-run first |

## Gotchas

- **NVR:** **Must** pass `--channel N`; wrong channel silently returns wrong config. **Must** verify via `device resolve` when uncertain.
- **Capability variance:** `detect ai --type` support differs per model. Battery cams may be `person` only. **Must** run `device inventory --capabilities` before scripting AI calls across devices.
- Empty `{}` response ≠ error on paths the device doesn't expose — do not treat as failure.
- Argv wins over env when both are set for `--password`.
- Remote (UID) first connect is 10–15 s; **Must** bump `--timeout-secs 15+` when first-connecting a UID target.
- `preview capture` writes BC framing, not raw H.264 — ffplay needs `-f hevc|-f h264`. `preview play` already handles that.
- **Forbidden** running `events query` / `events stream` without `--gateway-addr` — it will fail fast with a clear error, but don't attempt it.
- Gateway tokens don't auto-refresh. **Must** re-login after long pauses or on HTTP 403.
- Batch cannot prompt mid-run. **Must** register cameras (with stored creds) before any batch operation.

## File locations (XDG layout)

Single parent per category — easy to purge, easy to find. **Must** prefer these paths in rules, examples, and command suggestions. **Forbidden** scattering artifacts across `/tmp/*.pcm`, `/var/reolink/...`, `/etc/reolink/...`.

| Category | Path | Managed by |
|---|---|---|
| Persistent config (CLI, aliases, monitor rules) | `~/.config/reolink-cli/` | CLI (`config init`, `device add`, `events monitor init`) — 0600 perms |
| App state (pidfile, cursor, debounce, trigger history) | `~/.local/state/reolink-cli/` | events monitor daemon — `monitor-state.json` + `monitor-history.jsonl` + `monitor.pid` |
| Disposable artifacts (snapshots, PCM clips, captures, VOD) | `~/.cache/reolink-cli/{audio,snapshots/<date>,captures,downloads}/` | user / rule authors — **Must** use this prefix |
| Claude Code plugin cache | `~/.claude/plugins/cache/reolink-cli/` | Claude Code (`/plugin update` refreshes) |

events monitor expands `~/` in `path` and `pcm` fields and auto-`mkdir -p`'s the snapshot parent dir — safe to write rules with `~/.cache/reolink-cli/snapshots/{date}/...` without pre-creating anything. Bulk purge: `rm -rf ~/.cache/reolink-cli`.

## Launcher

Prefer the installed binary: `reolink-cli …`. Plugin-bundled:
`${CLAUDE_PLUGIN_ROOT}/scripts/run-cli.{sh,cmd}`.

## References

Topic-scoped recipe files. **Must** load only the one matching your task; **Forbidden** reading the full set.

| File | Read when |
|---|---|
| `references/setup.md` | Discovery, registry, identity, generic `config get/set` |
| `references/media.md` | Preview / snapshot / VOD |
| `references/controls.md` | Light / image / OSD / audio / privacy |
| `references/ptz.md` | Any `ptz …` |
| `references/detection.md` | Motion / AI detection (`detect motion`, `detect ai`) |
| `references/recording.md` | Record schedule + core config (`record schedule`, `record config get`) |
| `references/storage.md` | SD card / HDD read-only status (`storage status`) |
| `references/notifications.md` | Mobile push (`notify push`) |
| `references/events.md` | Gateway event bus — `events query` / `events stream`, event shape |
| `references/event-monitor.md` | `events monitor` rule engine — TOML-driven automation (preferred over shell watchers) |
| `references/voice-alert.md` | Detection-triggered voice announcement via `audio talk` (shell-watcher legacy) |
| `references/admin.md` | Device user accounts, `system reboot`, raw debug |
| `references/gateway-http.md` | Gateway `POST /api` from curl or non-CLI clients |
| `references/troubleshooting.md` | Something failed; or full intent map |

Other docs (in the repo, not this skill):

- `docs/cli-reference.md` — generated flag reference
