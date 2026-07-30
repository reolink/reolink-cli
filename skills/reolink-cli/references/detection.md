# Detection: Motion + AI

## Scope

Motion (`detect motion`) and per-type AI (`detect ai`). AI types: `person | vehicle | dog_cat | package | cry`.

## Rules

- **Must** run `device inventory --capabilities` before scripting `detect ai --type X` across multiple devices — AI-type support varies per model (battery cams may only support `person`).
- **Must** warn the user before `detect motion|ai set --disable` — disabling stops push notifications, white-LED alarm trigger, and md-rule recording downstream.
- **Forbidden** asserting a device supports a specific AI type without capability confirmation.
- `--sensitivity` scales differ per command (higher = more sensitive on both):
  `detect motion set` takes **1–50** (v20 MD spec range, default 9);
  `detect ai set` takes **0–100**. Values valid for one are out of range for the other.

## Motion

```bash
reolink-cli --camera front-door detect motion get
reolink-cli --camera front-door detect motion set --enable --sensitivity 30
reolink-cli --camera front-door detect motion set --disable --use-pir
```

## AI (per type)

```bash
reolink-cli --camera front-door detect ai get --type person
reolink-cli --camera front-door detect ai set --type person --sensitivity 80 --stay-time 2
reolink-cli --camera front-door detect ai set --type vehicle --sensitivity 70
reolink-cli --camera front-door detect ai set --type dog_cat --sensitivity 50
```

## Batch

`detect ai get` with `--tag` or `--all-devices` requires the gateway (`--gateway-addr HOST:PORT`); batch framework routes through it.

**Related:** [`events.md`](events.md) for seeing detection-triggered alarms, [`recording.md`](recording.md) for md-rule recording.
