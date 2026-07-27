# Troubleshooting & Intent Mapping

Two things live here:

1. **Decision trees** for diagnosing common failures — walk top-down, stop at first match.
2. **Intent map** for loose user phrasings → precise commands (mirror of the table in `SKILL.md`, kept here for agents that didn't load the whole skill).

---

## "Camera not working" — top-level tree

Start here whenever the user reports a camera problem without specifics.

```
reolink-cli --camera <X> ping
├── timeout / device unreachable
│     └── network layer — see "Unreachable" tree below
├── "no device key" / invalid target
│     └── resolve/registry — see "Wrong target" tree
└── ok
    └── reolink-cli --camera <X> login
        ├── auth required / invalid credentials
        │     └── credentials — see "Auth failing" tree
        ├── timeout (UID only)
        │     └── First-connect warm-up; retry with --timeout-secs 15+
        └── ok
            └── reolink-cli --camera <X> info
                ├── error / unexpected
                │     └── Protocol / firmware — see "Protocol mismatch" tree
                └── ok
                    └── Basic connectivity is fine; diagnose the specific
                        feature the user is asking about.
```

### Unreachable

```
ping fails
├── Is the device on the same network? (ask user)
│     └── no  → user must route / VPN first
├── Can you reach the device port from this host?
│     └── try `nc -zv <host> 9000` or `curl -sv http://<host>:9000`
│         (but only if user authorizes network probes)
├── Was the device recently rebooted?
│     └── wait 30–60s, retry
├── Remote (UID) target?
│     └── first probe is 10–15s; retry with --timeout-secs 15
└── Otherwise → device is probably off / on a different network;
               ask user to physically check.
```

### Auth failing

```
login fails with auth error
├── Is the alias's stored password right?
│     └── `reolink-cli --camera <X> device show <X>` (masked)
│         `reolink-cli device update <X> --user admin` then re-prompt for password
├── Account locked after too many attempts?
│     └── wait 5 minutes; device auto-unlocks
├── Admin password forgotten?
│     └── CLI cannot recover. User must factory-reset via Reolink app.
└── Non-admin trying admin-only op (e.g. users add)?
      └── log in as admin: `device update <X> --user admin`
```

### Wrong target

```
"route not found" / "no device url or token" / resolves to nothing
├── Alias not in aliases.toml?
│     └── `reolink-cli device list` → confirm; add with `device add`
├── Selector conflict?
│     └── `reolink-cli --camera X --host Y device resolve` — shows precedence
└── NVR channel wrong?
      └── default channel=0 but NVR needs explicit --channel N
```

### Protocol mismatch

```
ping ok + login ok + info errors
├── Firmware mismatch (unusual NVR)?
│     └── force --protocol auto (covers ~all cases)
└── Capability missing (e.g. AI type this model doesn't have)?
      └── `device inventory --capabilities` or `device analyze --capabilities`
          to list actual supported surfaces.
```

### `system reboot` aftermath

```
system reboot was issued:
├── Got "Connection reset" in the response
│     └── EXPECTED. CLI already swallows this for system reboot.
├── Any other command hits "Connection reset" right after
│     └── also expected if the device is mid-reboot;
│         wait 30–60s and retry.
└── Device doesn't come back after 90s
      └── hardware issue; user should physically check power/network.
```

### Gateway token trouble

```
Gateway (/api) call returns HTTP 401/403
├── HTTP 401 "authorization bearer token required"
│     └── missing `Authorization: Bearer <token>` header — add it.
├── HTTP 403 "invalid or expired token"
│     └── re-login via `{"action":"set","path":"auth.login","params":{…}}`.
│         Gateway tokens don't auto-refresh; long pauses can expire them.
├── HTTP 410 on /api/login or /api/request
│     └── old v0.1.1 endpoints removed. Use POST /api + Bearer.
└── HTTP 502 "device unreachable"
      └── gateway itself is up; the UPSTREAM device is down.
          fall back to the "Unreachable" tree above.
```

### Feature "not working"

```
user: "X is broken / doesn't respond"
├── Is X actually supported on this model?
│     └── `device inventory --capabilities`
│         → if absent, firmware doesn't expose it; tell user.
├── Is X gated on a prerequisite? (common ones)
│     ├── events query        → gateway running + --gateway-addr
│     ├── detect ai           → AI type supported by model
│     ├── ptz.*               → device has motors (not on fixed cams)
│     ├── light whiteled      → device has white LED
│     ├── audio talk          → `capabilities.audioTalk=1` + SD/session not busy
│     ├── storage status      → SD card physically inserted
│     └── record manual       → NOT supported (all IPCs so far) — fallback to schedule
├── Read X, modify, re-read, compare?
│     └── If the write is accepted but the read still shows old value,
│         the device probably silently ignored the request —
│         log the exact params and check capability.
└── Otherwise → bug. Capture `--output json` of both the get and the set,
               plus `info` and `capabilities`, and report.
```

### `audio talk` — "camera stays silent"

Use when user says "no sound / can't hear / silent" after `audio talk` returns `ok:true`.

```
audio talk returned ok:true but user hears nothing
├── Is volume muted or zero?
│     └── `audio config get` → check `volume` (1..=100); bump via
│         `audio volume set 80` if low. Also check `audio mute` wasn't
│         called — run `audio unmute`.
├── Is the device even in audible range?
│     └── Obvious but ask: user near the camera? Mic/speaker covered?
│         Outdoor cam in noisy environment?
├── Was the input PCM actually valid?
│     └── `ffplay -f s16le -ar 16000 -ac 1 ~/.cache/reolink-cli/audio/alert.pcm`
│         on the host — if host can't play it, neither can the camera.
│         Re-encode: `ffmpeg -y -i SRC -f s16le -ar 16000 -ac 1 ~/.cache/reolink-cli/audio/alert.pcm`.
├── Did the sample rate match the device's TalkAbility?
│     └── `raw 10` (NET_GET_TALK_ABILITY_V20) → `audioConfigList` lists
│         supported `sampleRate`. E1 Outdoor: 16 kHz only.
├── Did another app hold the talk session open?
│     └── Close Reolink mobile app / other clients, retry. Device may
│         refuse a second open until the previous one times out.
├── Did the response actually send frames?
│     └── `{samplesPushed: N}` in the response; `N = pcm_samples`. If N=0,
│         the CLI read zero bytes from --file / --stdin — recheck the path.
└── Otherwise → suspect encoder drift. File an issue with:
               • `capabilities` JSON
               • `raw 10` output (TalkAbility)
               • Length + first 32 bytes of the PCM input (hex-dumped)
               • Gateway log with RUST_LOG=debug
```

### Verify rules {#verify-rules}

Governs whether a write operation needs a follow-up `get` to confirm the change. The SKILL.md rule is the short form; this is the full per-command table.

#### Verify-required (must `get` again after `set`)

| Command | Why |
|---|---|
| `light ir set` | E-series returns `ok:true` but keeps old state on unsupported firmware |
| `light whiteled set` / `light spotlight set` | Model-gated capability; silent no-op if absent |
| `image flip set` / `image tune set` | Some firmware clamps values silently |
| `audio config set` | `visitorLoudspeaker` / `preAlarm` gated on capability bits |
| `detect motion set` / `detect ai set` | Sensitivity may be clamped to model range |
| `osd set` | `--name-overlay` silently ignored on some firmwares |
| `config set led\|network\|osd\|...` | Generic path; device-side merge may drop fields |

#### Verify-exempt (the set response is authoritative)

| Command | Why |
|---|---|
| `ptz move` / `ptz stop` | State is motion; verifying "did it move" needs physical observation |
| `ptz preset goto/set/delete` | Device returns error if preset invalid; success ⇒ effect |
| `system reboot` | Device drops connection — nothing to re-read |
| `snapshot` / `preview capture` / `preview play` / `preview stop` | One-shot or stream; output is the artifact |
| `audio mute` / `audio unmute` / `audio talk` | Transient; verification round-trip has no race-free meaning |
| `vod download` | Transfer; `ok:true` means bytes saved |
| `users passwd` (own password) | Device enforces via auth; next login is the verify |
| `privacy mask set` | Already uses GET-merge-SET internally |

### `audio talk` — 422 BUSY

As of v0.2.11 the gateway routes `audio.talk` through a dedicated TCP (skipping cmd 192) and auto-retries once on 422 with 3s/5s backoff, so this rarely surfaces to the user. When it does, the remaining cause is almost always *another* process holding the device-side talk slot:

```
audio talk returns "talkback busy: device reports BUSY (422)..."
├── Another reolink-gateway process holding a stale TCP?
│     └── `pgrep -fa reolink-gateway`; if multiple, kill the older one.
│         Most common cause in dev — a prior test session's gateway still
│         has ESTABLISHED to the camera.
├── Reolink app / browser / second CLI talking?
│     └── Close them; device permits ONE talk session globally.
├── Two automation rules firing audio_talk concurrently?
│     └── Add debounce, or use `matching = "first"` to serialize.
└── Exhausted the above?
      ├── reolink-cli --camera X system reboot   (clears immediately)
      └── Wait 2–5 min for device-side timeout, then retry
Forbidden: hammer-retrying past the built-in backoff — state won't change
without one of the clears above.
```

### `storage status` — "no card detected"

```
storage status returns items:[] OR mounted:false
├── Empty items[] (no SD slot reported)?
│     └── Some IPCs have no slot — confirm with physical model check.
├── `mounted: false, formatted: false`?
│     └── Card inserted but uninitialized. Agent MUST NOT format —
│         tell user to format via Reolink mobile app (this skill is
│         read-only for storage).
├── `mounted: false, formatted: true`?
│     └── Card has a filesystem but device can't mount it. Usually:
│         • Card unplugged while powered on
│         • Filesystem corruption
│         • Card wore out (SD cards do fail)
│         Ask user to reseat card; if still false, card may be dead.
└── `mounted: true, remainGB: 0` with `record.config.cycle: true`?
    └── NORMAL. Loop-record fills the card and overwrites oldest. Do NOT
        alarm the user — only escalate if `cycle: false` AND `remainGB < 1`.
```

### `events monitor` — refuses to start

```
events monitor run returns "another daemon (pid N) appears to be running..."
├── Is the PID actually alive?
│     reolink-cli events monitor status   (running:true/false, pid)
│     OR `kill -0 <pid>` (Unix)
├── YES, running → use it:
│     reolink-cli events monitor reload   (SIGHUP — reloads TOML, keeps cursor)
│     reolink-cli events monitor history --last 20   (recent fires)
│     kill <pid>                           (graceful SIGTERM)
└── NO, stale pidfile → reclaim:
      rm ~/.local/state/reolink-cli/monitor.pid
      reolink-cli events monitor run ...
```

### `events monitor reload` — "no daemon running" / stale pidfile

- "no daemon running (pidfile ... not found)" → daemon isn't up; just run it.
- "pid N not running; removed stale pidfile" → safe; now `run` again.
- Windows → SIGHUP is Unix-only. Stop (`kill <pid>`) and `run` again to pick up rule changes.

### `events monitor` — rule file edits not taking effect

```
edited ~/.config/reolink-cli/monitor-rules.toml, daemon still runs old rules
├── Daemon reloads on SIGHUP, not on file save.
├── Send SIGHUP → `reolink-cli events monitor reload`
│     ✓ cursor/debounce state preserved; settings.hook_timeout re-applied;
│       poll_interval is captured once at start and sticky (restart to change).
└── If reload fails (invalid TOML), daemon keeps the OLD rules and logs a warn.
      Fix the file, reload again — no restart needed.
```

---

## Intent Map (verbose — for when SKILL.md isn't loaded)

| User phrasing | Command | Notes |
|---|---|---|
| add a user | `users add` | Device account, NOT a CLI alias |
| add a camera | `device add` | CLI alias, NOT device account |
| change password | `users passwd` OR `device update` | Ask: camera login account or the password used by CLI |
| who's logged in | `users list` | Filter `loginState: true` in the JSON |
| kick someone off | `users remove` or `users passwd` + `system reboot` | Active session survives removal until reboot |
| turn off the blinking light | `light statusled set --state off` | Body LED |
| night vision off | `light ir set --state off` | Invisible IR |
| turn on the spotlight | `light spotlight set --enable` | Manual |
| alarm-triggered white LED | `light whiteled set --enable --detect-type …` | Alarm rule-driven |
| too dark | `image tune set --bright N` | Check `light ir get` first for night |
| upside down | `image flip set --flip` | Vertical |
| mirrored | `image flip set --mirror` | Horizontal |
| mask something | `privacy mask set --enable [--json ...]` | Read current regions first |
| rename on-screen | `osd set --name "…"` | The label burned into the video |
| rename in app | `config set device-name --value '{"deviceName":"…"}'` | App-visible device name |
| restart / reboot | `system reboot` | 30–60s offline |
| factory reset | (not in CLI) | Point user at the Reolink mobile app |
| snapshot | `snapshot -o FILE` | Single JPEG |
| **preview / take a look / watch N minutes** | **`preview play`** (opens ffplay window) | Default when user's verb is watch/preview. NOT `preview capture` — that writes to file, user sees nothing live |
| record / record N seconds / save a clip / save it | `preview capture --packets ≈N×fps` | Only when user's verb is record/save/export. Main ≈ 25 fps, Sub ≈ 10 fps |
| live view | `preview play` | |
| loud / volume | `audio volume set N` | 0–100 master |
| mute alarm | `audio mute` | Alarm-audio only, not preview |
| person detection | `detect ai set --type person --sensitivity …` | Check model supports `person` |
| vehicle | `detect ai set --type vehicle …` | Not on all models |
| pet | `detect ai set --type dog_cat …` | Outdoor models |
| turn on recording | `record schedule set --enable` | |
| download yesterday | `vod search --since 24h` → `vod download NAME` | Copy filename exactly |
| any alarms today | `events query --since 24h` | Gateway required |
| voice alert / voice announcement / say something when someone arrives / play voice when a person is detected | `audio talk --file X.pcm` after `events stream --types people` | Needs `capabilities.audioTalk=1`; PCM16 LE mono only. See `voice-alert.md` |
| SD card info / storage card / memory card / capacity / remaining | `storage status` | Read-only; no format. For format, point user at Reolink app |
| record config / recording params / pre-record seconds / clip size | `record config get` | Read-only; cycle, pre/post-record, package time |
| start recording now / manual record / record a clip now | — | **Not supported** on Reolink IPCs (cmd 277/278/587 all 405). Offer `record schedule set --enable` as fallback |
| patrol | `ptz patrol start` | Pre-configured routes only |
| follow people / auto-track | `ptz autotrack set --enable --detect-type people` | Needs motors + AI |

When you can't map cleanly, **ask with 2–3 options** rather than guess.
