# Media: Preview / Snapshot / VOD

## Preview

**Two commands, don't mix them up:**

| User said | Use | Why |
|---|---|---|
| preview / take a look / watch N minutes / watch live / live view / "watch the feed" | `preview play` | Opens an **ffplay window** the user can watch. This is what "preview" means to a human. |
| record N seconds / save a clip / save it / record / capture / dump | `preview capture --file FILE` | Writes a BC media file to disk. User sees **nothing live** — only a file afterwards. |

If you accidentally run `preview capture` when the user said "preview for N minutes", they'll watch a progress indicator while no window opens, then end up with a BC-format file that most players can't open directly (needs `ffmpeg -f h264|-f hevc` demux or piping to ffplay). Always default to `preview play` when the user's verb is watch/preview.

`--packets` counts BC media packets, not seconds. Main stream ≈ 25 pkt/s. "Watch ~60s" → `preview play --packets 1500`.

```bash
# Capture to file
reolink-cli --camera front-door preview capture --stream main --file /tmp/clip.bin --packets 300

# Capture to stdout, pipe to ffplay (hevc)
reolink-cli --camera front-door --protocol auto preview capture --stream main --file - --packets 1000000 \
  | ffplay -fflags nobuffer -flags low_delay -f hevc -

# Built-in player (auto-detects h264/hevc)
reolink-cli --camera front-door --protocol auto preview play --stream main

# Multi-device: pass a directory to --file; one file per device
reolink-cli --tag outdoor preview capture --stream sub --file /tmp/captures --packets 64
```

## Snapshot

```bash
mkdir -p ~/.cache/reolink-cli/snapshots
reolink-cli --camera front-door snapshot -o ~/.cache/reolink-cli/snapshots/snap.jpg
reolink-cli --camera front-door snapshot --stream sub > ~/.cache/reolink-cli/snapshots/snap.jpg
```

## Stream URLs (integration helper)

For Frigate / Home Assistant / go2rtc / VLC / OBS — anything that pulls RTSP / RTMP / HTTP-FLV directly from the camera. This does **not** start a stream; it just composes the URL strings. The command probes `network` config on the device for real ports + their enable flags so the URLs match the device's actual config.

```bash
# Default — one RTSP main URL (90% of integrations)
reolink-cli --camera front-door stream url
# data.channels[0].streams = [ { protocol:"rtsp", stream:"main", url:"rtsp://192.168.1.10:554/Preview_01_main", port:554, available:true } ]

# Full matrix: 3 protocols × 2 substreams for HA
reolink-cli --camera front-door stream url --kind rtsp,rtmp,flv --stream main,sub

# One-shot URL you can paste into VLC (user:pass@ embedded, percent-encoded)
reolink-cli --camera front-door stream url --with-auth

# NVR: expand once, then tag-fanout (one entry per channel)
reolink-cli --gateway-addr 127.0.0.1:9000 device expand nvr-lobby --yes
reolink-cli --tag nvr-lobby stream url --kind rtsp --stream main,sub

# Batch across a tagged fleet
reolink-cli --tag outdoor stream url --kind rtsp --stream main
```

**URL schemes it emits:**

| Protocol | Port probed | Path |
|---|---|---|
| `rtsp` | `rtspPort` (default 554) | `/Preview_{NN}_{main\|sub\|ext}` where NN = channel+1 zero-padded |
| `rtmp` | `rtmpPort` (default 1935) | `/bcs/channel{N}_{main\|sub}.bcs?channel={N}&stream={0\|1}` |
| `flv`  | `httpPort` (default 80) — **rtmpPort goes in query** | `/flv?port={rtmpPort}&app=bcs&stream=channel{N}_{main\|sub}.bcs` |

`ext` substream exists only on RTSP (most NVR firmwares). RTMP/FLV silently skip it. Reolink cameras do not expose native HLS — if the user asks for HLS, direct them to go2rtc / MediaMTX as a re-packager fed by the RTSP URL.

**`available: false` field** — the URL is correct but the device has that protocol's port **disabled** in its own network config. Tell the user: open Reolink app → Settings → Advanced → Port to enable. Don't "fix" by forcing the default port — it will just fail differently.

**Credential handling:**
- Default (no flag): URL is clean (`rtsp://192.168.1.10:554/...`), and `data.user` + `data.password` are sibling JSON fields. Safer to paste into Slack / Issues / share with a colleague.
- `--with-auth`: embeds `user:password@` into the URL, percent-encoded. One-shot, convenient for VLC but **do not** paste into logs / Slack / GitHub issues — it will leak credentials.

**Behind the scenes:** one gateway call — `get network` for ports. Gateway **must** be running (same as `info` / `config get`). For NVR/Hub multi-channel fan-out, use `device expand` (see `setup.md`) first — each channel becomes its own camera, then `--tag <nvr-name>` naturally fans out.

**Read-only, fast-path.** No verify step, no write side-effects.

## VOD (Recorded Video)

Time is **naive local ISO** (`YYYY-MM-DDTHH:MM:SS`, no timezone, no ms). Cross-month queries are rejected — split per month. Filenames are case-sensitive.

```bash
# Absolute range
reolink-cli --camera front-door vod search --from 2026-04-17T00:00:00 --to 2026-04-17T23:59:59

# Relative window
reolink-cli --camera front-door vod search --since 2h --type people,vehicle

# Download a specific recording (name from search output)
reolink-cli --camera front-door vod download "20260417_120000.mp4" -o /tmp/clip.mp4
```

Record types: `manual | sched | io | md | people | vehicle | face | dog_cat | visitor | other | package`.
