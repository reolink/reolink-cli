# Recording (Schedule + Core Config)

Two distinct surfaces — keep them straight:

| Command | Protocol | What it controls |
|---|---|---|
| `record schedule {get\|set}` | cmd 594/595 `LongRunModeCfg` | Timed plan: weekly bitmap, time windows, fps, battery threshold |
| `record config get` | cmd 54 `RecordCfg` (read-only) | File-level: loop policy, pre/post-record, clip duration, stream list |

Manual start/stop (tap-to-start / tap-to-stop) is **NOT supported** — protocol cmds 277/278/587/588 all return 405 on the models we've probed. Fall back to toggling `record schedule --enable/--disable` for coarse on/off.

## Core Config (read-only)

```bash
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 record config get
# {
#   "channel": 0,
#   "cycle": true,          // loop (overwrite oldest) vs stop when full
#   "preRecordSecs": 10,    // lookback window before trigger
#   "postRecordSecs": 15,   // tail after trigger ends
#   "packageMinutes": 5,    // file split duration
#   "cycleList": [0, 1]     // stream indices recorded (0 = main, 1 = sub)
# }
```

**Forbidden** offering to write these fields — cmd 55 SET is not exposed in this skill (add only when a concrete user story needs it).

## Recording Schedule

## Rules

- `--week-table` is a **7-bit bitmap, Sun=bit0 … Sat=bit6** (matches `--help`). Common values:
  - Weekdays (Mon–Fri): `62`
  - Mon–Sat: `126`
  - All week: `127`
- **Must** read current (`record schedule get`) before overwriting — SET replaces the full schedule object.
- **Must** warn before `record schedule set --disable` — no new recordings will be written until re-enabled.
- `--fps` is 1–15. Higher = more storage.

## Read

```bash
reolink-cli --camera front-door record schedule get
```

## Enable / Disable

```bash
reolink-cli --camera front-door record schedule set --enable --fps 15
reolink-cli --camera front-door record schedule set --disable
```

## Weekly window (Mon–Sat 08:00–22:00)

```bash
reolink-cli --camera front-door record schedule set --enable --plan-type weekly --week-table 126 \
  --start-hour 8 --start-min 0 --end-hour 22 --end-min 0
```

## Daily window

```bash
reolink-cli --camera front-door record schedule set --enable --plan-type daily \
  --start-hour 0 --start-min 0 --end-hour 23 --end-min 59
```

**Related:** [`detection.md`](detection.md) for what triggers event-based recording, [`media.md`](media.md) for retrieving recorded VOD.
