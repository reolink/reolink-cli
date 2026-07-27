# Reolink Camera Operator

You have access to `reolink-cli` for operating Reolink cameras locally. The binary must be installed and the gateway must be running for most commands.

## Setup

The user installs `reolink-cli` and `reolink-gateway` once by extracting their release tarball and running `./install.sh`. Both binaries land under `~/.local/bin/`. To upgrade later, the user gets a fresh tarball and re-runs `./install.sh`.

```bash
# Start the gateway (required for most commands)
reolink-cli gateway start --addr 127.0.0.1:9000 &

# Register a camera
reolink-cli device add front-door --host 192.168.x.x --user admin
```

## Primary Surface

`reolink-cli` (JSON stdout). Only `device add|list|update|remove|resolve|show`, `config init`, and `discover` work without the gateway. Everything else needs the gateway running.

**Envelopes:**
- CLI: `{ok:true, command, protocol, data}` / `{ok:false, error:{code, message, retryable}}`
- Gateway `POST /api`: `{status:"success", data}` / `{status:"error", code, message}`

## Credential Safety

Never pass `--password PLAIN` on argv. Use `--alias front-door` (from `aliases.toml`), `REOLINK_PASSWORD` env, `--password-stdin`, or interactive prompt.

## Workflow

**Default: just run the command.** The gateway daemon caches auth across CLI invocations, so you don't pay ping+login per command. Most user intents map to **one** CLI call.

- `ping` and `login` are **diagnostics, not pre-steps** — the first real command (`info`, `get`, `snapshot`, …) does its own connect + auth via the gateway. Only `ping` standalone when the user explicitly asks "is camera X reachable?".
- **Do not** pre-read `<subcmd> --help` to discover flags. The *Key Commands* table below already lists them; the binary's `reolink-cli features --output json` enumerates the surface at runtime. Each extra tool round adds ~2–3 s of perceived latency.
- **Batch sequenced commands in a single shell call.** "PTZ full sweep" / "snapshot before & after a move" should be one Bash invocation with `&&`, not N separate calls. Each separate call costs one more agent turn (~2–3 s perceived).
- Re-`get` after a write **only** if the recipe isn't an idempotent `apply` (which already verifies internally).
- **Battery devices (LAN wake is automatic).** When a target has a UID but no host (e.g. `aliases.toml` entry with only `uid = "..."`), the gateway runs the BC3.0 §F.2 wake on UDP 2026 transparently before login. Just issue the business command (`info`, `preview`, …) — **do not** call `wake` explicitly (it is a hidden diagnostic). The first call may take 2–8 s while the device boots; subsequent calls reuse the live session and feel instant.

## Key Commands

**Discovery / Registry:** `discover`, `device list|add|update|remove|resolve|show|inventory`

**Identity:** `ping`, `login`, `info`, `capabilities`

**Preview / Snapshot:** `preview capture|play|start|stop`, `snapshot [-o FILE]`

**PTZ:** `ptz move DIR [--speed 1-64]`, `ptz stop`, `ptz preset list|goto|set|delete`, `ptz zoom|focus get|set`

**Light:** `light ir get|set --state auto|on|off`, `light spotlight set --enable|--disable`, `light whiteled get|set`

**Image:** `image flip get|set [--flip] [--mirror]`, `image tune get|set [--bright N] [--contrast N] ...` (0–255, 128=neutral)

**OSD:** `osd get|set [--name NAME] [--datetime|--no-datetime]`

**Audio:** `audio volume get|set LEVEL` (0–100), `audio mute`, `audio unmute`

**Users:** `users list`, `users add NAME --level admin|user`, `users remove NAME`, `users passwd NAME`

**Detection:** `detect motion get|set [--sensitivity 0-100]`, `detect ai get|set --type person|vehicle|dog_cat|package`

**Recording:** `record schedule get|set [--enable|--disable] [--fps 1-15]`

**VOD:** `vod search [--since DURATION]`, `vod download NAME [-o FILE]`

**Events (gateway):** `events query [--since 24h] [--types motion|people|vehicle]`, `events stream`

**System:** `system reboot`; `system upgrade <file.pak> [--factory-reset] [-y]` — flash firmware. ⚠️ bricking risk: match the package's model+hw_ver to `info` first; the GATEWAY reads the LOCAL file path; auto windowed/stop-and-wait by capability; confirm via `info` after the device reboots.

**Raw:** `raw CMD`

## Target Selectors (global options)

`--alias ALIAS` > `--host IP` > `--uid UID`. Batch: `--tag TAG`, `--aliases A,B`, `--all-devices`. NVR: add `--channel N`.

## Error Recovery

| Error | Fix |
|-------|-----|
| `gateway connect failed: Connection refused` | `reolink-cli gateway start --addr 127.0.0.1:9000 &` |
| `auth required` / `invalid credentials` | `device update` or Reolink app reset |
| `wake timed out after 3 attempts` (UID-only target) | Battery cam not reachable on the LAN broadcast domain; verify same subnet + UDP 2026 not firewalled. Do not retry tightly — each attempt already costs ~3s. |
| `unsupported` | Check `device inventory --capabilities` |
| `Connection reset` after `system reboot` | Expected; re-ping after 30–60s |

## Gotchas

- `preview play` opens a live ffplay window.
- Events require the gateway running
- NVR: always pass `--channel N` (wrong channel returns wrong config silently)
- Remote (UID) first connect: 10–15s; use `--timeout-secs 15`
- Batch selector resolving to 1 device returns single-target envelope, not `results[]`
