# Storage (SD card / HDD status)

Read-only query of the camera's SD card (or NVR HDD slots). **Forbidden** write operations in this skill — no format, no init, no policy change. If a user asks to format, direct them to the Reolink mobile app.

## Scope

- cmd 102 `NET_GET_HDD_CFG_V20`. Verified on E1 Outdoor fw v3.1.0.5714.
- On IPCs: usually 1 slot (microSD).
- On NVRs: N slots — `items[]` has one entry per slot.

## Rules

- **Must** treat this as a pure inspection command — no prompts, no confirmations, just output.
- **Forbidden** asserting "the SD card is healthy" from `formatted=true && mounted=true` alone — those flags say the filesystem is readable, not that it isn't wearing out. For health, advise the user to check Reolink app dashboards.
- `remainGB` near 0 with `cycle: true` in `record config get` is **normal** (loop-record fills the card then overwrites oldest). Don't alarm the user.
- `mounted: false` means no card / unmounted / filesystem error — ask the user to check the physical slot.

## Command

```bash
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 storage status
# {
#   "ok": true,
#   "data": {
#     "items": [
#       {"number": 0, "totalGB": 29.54, "remainGB": 0.98, "formatted": true, "mounted": true}
#     ]
#   }
# }
```

## Fields

| Field | Meaning |
|---|---|
| `number` | Slot index (0-based). Always 0 on IPCs. |
| `totalGB` | Total capacity (GB, decimal) — computed from wire-level `capacity` GB + `capacityM` MB. |
| `remainGB` | Free space (GB, decimal). |
| `formatted` | 1 = fs present; 0 = uninitialized. |
| `mounted` | 1 = device has opened the fs for R/W; 0 = no card / error. |

## Related

- [`recording.md`](recording.md) — `record config get` for the cycle policy that fills the card.
- [`media.md`](media.md) — `vod search / download` to retrieve recorded files from the card.
