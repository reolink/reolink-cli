# Events Monitor (Rule Engine)

Declarative "when X happens, do Y" automation that replaces ad-hoc shell watcher scripts. Single CLI process — `reolink-cli events monitor run`. Reads rules from TOML. Polls gateway event bus, matches rules, dispatches actions.

> ⚠️ **If you catch yourself starting to write `while true; do reolink-cli events query ...` — STOP.** That bash pattern always ends up reinventing debouncing, SIGTERM handling, action timeouts, and cursor bookkeeping — badly. Use this rule engine instead. A 10-line TOML rule replaces 60 lines of brittle shell.

**Preferred over** the shell-script watcher pattern in `voice-alert.md` (kept as legacy fallback only, documented for historical context).

## Scope

- **Input trigger**: gateway ring events (`people` / `vehicle` / `motion` / `dog_cat` / etc.)
- **Actions**: `snapshot`, `audio_talk`, `light_spotlight`, `ptz_goto`, `exec` (shell), `log`
- **State**: per-rule debounce + cursor persisted to `~/.local/state/reolink-cli/monitor-state.json` (atomic `.tmp`+rename); restart resumes without replaying or skipping events
- **History**: every rule fire appended as JSONL to `~/.local/state/reolink-cli/monitor-history.jsonl`; trimmed to `history_max_entries` at startup
- **Control**: pidfile at `~/.local/state/reolink-cli/monitor.pid` (refuses to double-start); SIGTERM / Ctrl-C drains cleanly; SIGHUP (or `events monitor reload`) re-reads the TOML without dropping the cursor

## Rules

- **Must** run `events monitor check` before `run` to validate the TOML.
- **Must** debounce rules that can fire rapidly (walking back and forth → multiple `people MD` → debounce ≥10s).
- **Forbidden** putting secrets in rule strings — the TOML is stored in plaintext under `~/.config/reolink-cli/`.
- **Forbidden** long-running (`>30s`) `exec` commands — hard timeout will kill them. Use detached spawn inside the hook if needed.
- **Must** use `{device}` / `{iso}` placeholders for path templates that may collide across devices or times.

## Workflow

### 1. Generate template

```bash
reolink-cli events monitor init
# → ~/.config/reolink-cli/monitor-rules.toml  (2400 B, commented)
```

Flags: `--file PATH` to write elsewhere, `--force` to overwrite.

### 2. Edit rules

See [Rule reference](#rule-reference) below. Minimum viable:

```toml
[[rule]]
name = "person-greet"
device = "front-door"
trigger = "people"
status = "MD"
debounce = "20s"
actions = [
  { type = "audio_talk", pcm = "~/.cache/reolink-cli/audio/hello.pcm" },
]
```

Paths support `~/` expansion and the snapshot action `mkdir -p`'s the parent directory before writing — safe to use date-bucketed templates like `~/.cache/reolink-cli/snapshots/{date}/...` on the first fire of a new day.

### 3. Validate

```bash
reolink-cli events monitor check
# ✓ prints rulesLoaded count + per-rule summary
# ✗ rejects duplicate rule names, empty actions, invalid durations
```

### 4. Run daemon

```bash
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 \
  events monitor run
```

Logs go to stderr (`RUST_LOG=info` for normal, `debug` for verbose). `nohup ... &` for background; systemd/launchd service unit templates are still a manual exercise.

### 5. Inspect / reload / stop

```bash
reolink-cli events monitor status                # running? pid? cursor? last fire per rule?
reolink-cli events monitor history --last 20     # tail trigger history (JSONL)
reolink-cli events monitor reload                # Unix: SIGHUP → re-read rules file without dropping cursor
```

Stop: Ctrl-C or `kill <pid>` — drains in-flight actions, flushes state, exits 0. Second `run` call refuses to start if the pidfile names a live PID (safety against double-daemons racing on the same event ring); a stale pidfile (PID gone) is reclaimed silently.

## Rule reference

```toml
[settings]                        # all optional
poll_interval       = "5s"        # <N>s|m|h; how often to drain the gateway ring
hook_timeout        = "30s"       # per-action hard timeout
matching            = "first"     # "first" = stop at first match; "all" = fire every match
state_file          = "~/.local/state/reolink-cli/monitor-state.json"   # cursor + debounce snapshot; atomic (.tmp+rename)
history_file        = "~/.local/state/reolink-cli/monitor-history.jsonl" # one JSONL line per rule fire
history_max_entries = 1000                                           # trimmed at startup, not per-append

[[rule]]
name     = "night-intruder"           # required; unique; used in logs
device   = "front-door"               # optional; omit = any alias
trigger  = "people"                   # required; string OR array of strings
status   = "MD"                       # optional; filter on data.status
debounce = "20s"                      # optional; default "0s"
actions  = [ ... ]                    # required; non-empty list
```

### Triggers (eventType values)

`motion | people | vehicle | face | dog_cat | visitor | package | cry` — matches the gateway event-type vocabulary. Multi-match: `trigger = ["people", "vehicle"]`.

### Actions

| `type` | Required | Optional | Purpose |
|---|---|---|---|
| `snapshot` | `path` | `stream = "main"\|"sub"` | JPEG to file; path supports templates |
| `audio_talk` | `pcm` | `sample_rate = 16000` | Push PCM16 LE mono through talkback |
| `light_spotlight` | `enable` (bool) | `duration` (seconds) | Visible spotlight on/off; pair with night `people` triggers |
| `ptz_goto` | `preset_id` (u32) | — | Move to PTZ preset; pair with `people`/`vehicle` to orient |
| `exec` | `command` | `args = []` | Run arbitrary binary; event JSON piped to stdin |
| `log` | `message` | `level = "info"` | Structured log line (debug/info/warn/error) |

**Webhook?** No first-class action — use `exec` with curl/wget. Example for Slack/ntfy/Home Assistant:
```toml
{ type = "exec", command = "curl",
  args = ["-sS", "-X", "POST", "-H", "Content-Type: application/json",
          "--data-binary", "@-", "https://hooks.slack.com/..."] }
```
The event JSON is piped on stdin; `--data-binary @-` forwards it verbatim.

### Template placeholders (any string field)

| Token | Value |
|---|---|
| `{ts}` | Unix timestamp (seconds) |
| `{iso}` | Local ISO `2026-04-22T09:44:24` |
| `{date}` | `2026-04-22` |
| `{time}` | `09-44-24` (dash-separated; safe for filenames) |
| `{device}` | alias |
| `{rule}` | rule.name |
| `{event.type}` | eventType |
| `{event.channel}` | channel |
| `{event.data.status}` | MD / none |
| `{event.data.aiType}` | people / vehicle / none |

## Examples

### Person at front door + full audit trail

```toml
[[rule]]
name = "front-door-person"
device = "front-door"
trigger = "people"
status = "MD"
debounce = "30s"
actions = [
  { type = "snapshot",    path = "~/.cache/reolink-cli/snapshots/{date}/{device}-{time}.jpg" },
  { type = "audio_talk",  pcm = "~/.cache/reolink-cli/audio/greeting.pcm" },
  { type = "log",         message = "person detected at {device} (ts={ts})" },
]
```

### Custom shell pipeline via `exec`

```toml
[[rule]]
name = "push-to-feishu"
trigger = "people"
debounce = "1m"
actions = [
  { type = "snapshot", path = "~/.cache/reolink-cli/snapshots/{date}/alert-{time}.jpg" },
  { type = "exec",     command = "/usr/local/bin/feishu-notify.sh",
                       args = ["~/.cache/reolink-cli/snapshots/{date}/alert-{time}.jpg"] },
]
```

The hook (`feishu-notify.sh`) receives the full event JSON on stdin and can extract fields via `jq`.

### Different reactions by event type

```toml
[[rule]]
name = "vehicle-log-only"
trigger = "vehicle"
debounce = "2m"
actions = [ { type = "log", message = "car seen at {device}" } ]

[[rule]]
name = "person-alert"
trigger = "people"
status = "MD"
debounce = "30s"
actions = [ { type = "audio_talk", pcm = "~/.cache/reolink-cli/audio/alert.pcm" } ]
```

`matching = "first"` (default) → only the first matching rule fires. Order matters.

## Troubleshooting

### Rule never fires

1. Ring has the event? `events query --since 2m --types people` — if empty, detection isn't triggering.
2. Rule matches? Check `device`, `trigger`, `status` filters. Missing `status = "MD"` means it also matches `status = "none"` end events.
3. Debounced? If an earlier fire is within `debounce` window, later events suppress. Shrink debounce or wait.
4. Daemon restarted? Cursor bootstraps to "now" on start → pre-start ring events are skipped.

### `audio_talk` fails

As of v0.2.11, `audio.talk` routes through a **dedicated TCP** per clip (skipping cmd 192), and the CLI auto-retries once on 422 BUSY with 3s/5s backoff. You should almost never see a talkback failure surface here. If you do:

1. **Other gateway processes?** — `pgrep -fa reolink-gateway`. A stale gateway on a different port can still hold an `ESTABLISHED` TCP to the camera. Kill it.
2. **Other client talking?** — the Reolink app, a browser session, or a second CLI caller can hold the device-side talk slot. Close them.
3. **PCM file present + even-byte length?** — `audio_talk` takes raw PCM16 LE mono, not AIFF/WAV. See [`voice-alert.md`](voice-alert.md) for the `say → ffmpeg` pipeline.

Only fall back to "reboot camera / wait 2–5 min" after those three are ruled out.

### Snapshot path

The monitor `mkdir -p`'s the parent directory automatically (as of v0.2.8), so `~/.cache/reolink-cli/snapshots/{date}/...` works on the first fire without pre-creating date dirs. If it fails, check:

- **Permission** — write failure on `/etc`, `/var` without sudo.
- **Invalid template** — a stray placeholder like `{unknown}` stays literal in the path.

Recommended parent: `~/.cache/reolink-cli/` (XDG cache, always writable by the user, easy to purge with `rm -rf`).

## Related

- [`voice-alert.md`](voice-alert.md) — manual/legacy shell-script pattern (kept as fallback)
- [`events.md`](events.md) — the underlying `events query` / `events stream` that powers the monitor
- [`detection.md`](detection.md) — enabling the AI detection types that drive rule triggers
- [`media.md`](media.md) — `snapshot` command used by the `snapshot` action
