# Detection: Motion + AI

## Scope

Motion (`detect motion`) and per-type AI (`detect ai`). AI types: `person | vehicle | dog_cat | package | cry`.

## Rules

- **Must** run `device inventory --capabilities` before scripting `detect ai --type X` across multiple devices — AI-type support varies per model (battery cams may only support `person`).
- **Must** warn the user before `detect motion|ai set --disable` — disabling stops push notifications, white-LED alarm trigger, and md-rule recording downstream.
- **Forbidden** asserting a device supports a specific AI type without capability confirmation.
- `--sensitivity` uses **different scales for motion and AI** (higher = more
  sensitive on both), so a value valid for one is rejected by the other. Read the
  accepted range from `--help` rather than assuming — it is enforced at parse
  time, so a wrong value fails before touching the camera:
  `reolink-cli detect motion set --help`, `reolink-cli detect ai set --help`.

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
