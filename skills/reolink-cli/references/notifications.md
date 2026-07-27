# Push Notifications

## Scope

`notify push` controls the device's own push-notification behavior (to Reolink cloud / mobile app). **Not** the gateway's event stream — see [`events.md`](events.md) for that.

## Rules

- **Must** check current config (`notify push get`) before changing.
- `--interval SECS` controls minimum gap between pushes (dedup window).
- `--rich 1` enables rich push (thumbnail); `--rich 0` disables.
- **Forbidden** enabling rich push without confirming the user's mobile app supports it (older apps may drop rich payloads).

## Commands

```bash
reolink-cli --camera front-door notify push get
reolink-cli --camera front-door notify push set --interval 30 --rich 1
reolink-cli --camera front-door notify push set --interval 60 --rich 0
```

## Related

- [`detection.md`](detection.md) — disabling detection rules kills push triggers upstream.
- [`events.md`](events.md) — gateway's in-memory event bus (different mechanism).
