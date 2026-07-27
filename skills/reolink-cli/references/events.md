# Events (Gateway)

Events are served from the gateway's in-memory ring buffer. **Must** have the gateway running and pass `--gateway-addr HOST:PORT` to every `events` subcommand.

## Rules

- **Must** start the gateway once before any `events` call: `reolink-cli gateway start --addr 127.0.0.1:9000 &`
- **Must** `login` once per gateway lifetime — gateway maintains the device session + cmd 192 alarm subscription in the background.
- **Forbidden** reporting "no events" to the user immediately after gateway startup; ring buffer takes seconds to populate and event flow depends on device activity.
- **Forbidden** mixing VOD `--type` vocabulary with event `--types`. They're different:
  - **Events**: `motion | people | vehicle | face | dog_cat | visitor | package | cry`
  - **VOD** (see [`media.md`](media.md)): `manual | sched | io | md | people | vehicle | face | dog_cat | visitor | other | package`
- Ring buffer capacity: 500 entries (FIFO). Old events get evicted.

## Query buffered events (snapshot)

```bash
# Last N
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 events query --last 20
# Time window
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 events query --since 1h
# Filter by type
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 events query --since 1h --types motion,people
```

## Fleet-wide query

```bash
reolink-cli --tag outdoor --gateway-addr 127.0.0.1:9000 events query --since 1h --types motion
```

## Live stream (NDJSON)

```bash
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 events stream --types people,vehicle
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 events stream --timeout 60
```

## Event shape

Each item:
```json
{
  "timestamp": 1776765505,
  "channel": 0,
  "device": "192.168.1.58:9000",
  "eventType": "motion",
  "data": { "status": "MD", "aiType": "people", "aiTypes": ["people"] }
}
```

- `eventType`: normalized label — `motion | people | vehicle | face | dog_cat | visitor | package | cry | none | raw.cmd<N>`
- `status`: raw `<status>` from device (`MD` = motion detected; `none` = ended).
- `aiType` / `aiTypes`: AI classification (e.g. `people`).
- `raw.cmd<N>` items are ambient state reports (PTZ param change, floodlight, siren, sleep) — safe to filter out.

## Related

- [`detection.md`](detection.md) — detection rules must be enabled for event types to be emitted.
- [`notifications.md`](notifications.md) — separate mechanism (mobile push).
- [`gateway-http.md`](gateway-http.md) — consuming events via curl / browser (`GET /api/events`).
