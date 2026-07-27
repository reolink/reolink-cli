# Voice Alert (Detection → Camera Speaker)

Product recipe: on person/vehicle detection, play a dynamic voice line from the camera's own speaker. Uses **talkback** (cmd 201 open + cmd 202 stream) — no device-side audio-file storage required.

## Scope

- **Input**: Raw PCM16 little-endian mono samples (from TTS / pre-recorded).
- **Output**: Camera speaker plays in real time (~2 s trailing latency for first frame).
- **Trigger**: External loop subscribed to `events stream`.
- **Capability gate**: `capabilities.audioTalk` must be `1` (run `reolink-cli ... capabilities`).

## Rules

- **Must** run `reolink-cli capabilities` before first use. If `audioTalk = 0`, this path is unavailable on that model — fall back to static `visitor_loudspeaker` config (device-side auto-reply).
- **Must** feed **PCM16 LE mono** at a sample rate the device advertises (verify via `reolink-cli raw 10` — cmd `NET_GET_TALK_ABILITY_V20`). E1 Outdoor confirmed: 16 kHz / 16-bit / mono.
- **Forbidden** sending raw AIFF/WAV/MP3/AAC — the gateway does not demux, only raw PCM16 samples accepted.
- **Forbidden** stereo input — convert to mono first (`ffmpeg -ac 1`).
- **Must** cap single-clip length under ~90 s. Longer clips exceed the gateway's frame size budget.
- During a `talk_open` / push, other commands on the same session continue to work — but avoid issuing `ptz move` or `preview start` mid-push (they share the TCP connection and can stutter the audio pacer).

### 422 BUSY — handled automatically (as of v0.2.11)

The `audio.talk` path no longer shares a TCP with the pooled session. Each clip gets a dedicated login that skips cmd 192 (alarm subscribe), which previously collided with cmd 201 (talk open) on E1 Outdoor fw v3.1.0.5714. On the rare transient 422 the CLI auto-retries once with a 3s + 5s backoff after the gateway evicts the pooled session.

**You should almost never see a 422 surface.** When it does, the cause is usually *another* client holding the device-side talk slot — not a bug in this CLI:

1. **Stale gateway process on a different port.** `pgrep -fa reolink-gateway` — if two are running, the older one may still have an `ESTABLISHED` TCP to the camera. `kill` it and retry.
2. **Reolink app / browser / second CLI** has talkback open. Close them.
3. **Two automation rules firing `audio_talk` concurrently** on the same camera. Add debounce or serialize them.

Only after those three are ruled out fall back to `system reboot` (clears talk state immediately) or waiting 2–5 min for the device timeout. **Must** NOT hammer-retry — after the automatic backoff, a third immediate attempt will keep seeing the same stale state.

## Commands

```bash
# One-time setup: XDG cache dir for disposable audio artifacts.
mkdir -p ~/.cache/reolink-cli/audio

# Generate voice clip (macOS — English)
say -v "Samantha" "Please step back, this area is being monitored." \
  -o ~/.cache/reolink-cli/audio/alert.aiff
ffmpeg -y -i ~/.cache/reolink-cli/audio/alert.aiff -f s16le -ar 16000 -ac 1 \
  ~/.cache/reolink-cli/audio/alert.pcm

# Chinese variant: substitute -v "Ting-Ting" and a Chinese string —
# `say` ships with multilingual voices on macOS.

# Push to camera speaker
reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 \
  audio talk --file ~/.cache/reolink-cli/audio/alert.pcm --sample-rate 16000

# Alternative: pipe via stdin
say -v "Samantha" "Please step back" -o - --data-format=LEI16@16000 | \
  reolink-cli --camera front-door --gateway-addr 127.0.0.1:9000 audio talk --stdin
```

**Why `~/.cache/reolink-cli/audio/`**: standard XDG cache dir. Always writable by the user; safe to delete any time. Pair with snapshot output in `~/.cache/reolink-cli/snapshots/` for a single parent purge target: `rm -rf ~/.cache/reolink`.

Response shape:
```json
{"ok":true, "data":{"samplesPushed":40950, "durationMs":2559, "sampleRate":16000}}
```

## End-to-end: detection → TTS → speaker

```bash
#!/bin/bash
# Daemon: person detected → camera says something
set -e
ALIAS=front-door
GW=127.0.0.1:9000

reolink-cli --camera "$ALIAS" --gateway-addr "$GW" \
  events stream --types people --timeout 0 | \
while read -r line; do
  event_type=$(echo "$line" | jq -r '.eventType')
  [ "$event_type" != "people" ] && continue

  hour=$(date +%H)
  if [ "$hour" -ge 22 ] || [ "$hour" -lt 7 ]; then
    MSG="This area is monitored at night. Please leave."
  else
    MSG="Hello, who are you looking for?"
  fi

  CACHE=~/.cache/reolink-cli/audio
  mkdir -p "$CACHE"
  say -v "Samantha" "$MSG" -o "$CACHE/alert.aiff"
  ffmpeg -y -i "$CACHE/alert.aiff" -f s16le -ar 16000 -ac 1 "$CACHE/alert.pcm" 2>/dev/null

  reolink-cli --camera "$ALIAS" --gateway-addr "$GW" \
    audio talk --file "$CACHE/alert.pcm" --sample-rate 16000 >/dev/null 2>&1
done
```

**Operational notes:**
- Debounce at the script level (don't play on every `people status=MD` — use a time gate of ≥ 10 s).
- Rotate `MSG` text to avoid the camera becoming a single broken-record announcement.
- Log each play to a file; users will want to audit "camera talked at X:Y".

## Linux TTS alternative (no `say`)

```bash
mkdir -p ~/.cache/reolink-cli/audio
espeak-ng -v en "Please step back, this area is monitored." \
  -w ~/.cache/reolink-cli/audio/alert.wav
ffmpeg -y -i ~/.cache/reolink-cli/audio/alert.wav -f s16le -ar 16000 -ac 1 \
  ~/.cache/reolink-cli/audio/alert.pcm

# Other-language variant: -v es "no merodee aquí" — espeak-ng supports many locales.
```

## Why this path (not "visitor loudspeaker")

`audio config set --visitor-loudspeaker 1` is simpler but has three hard limits:
1. The voice line is pre-uploaded via the Reolink mobile app — no dynamic content.
2. `audioListId` selects from files the device already has; switching takes effect on the *next* trigger, not immediately.
3. Not every model has the audio-file subsystem (e.g., E1 Outdoor fw v3.1.0.5714 returns 405 on cmd 427 quick-reply GET).

`audio talk` streams host-generated audio each time, so the voice line is fully dynamic (TTS, recorded, contextual). Trade-off: the host must be running when the event fires; if the host is offline, no alert plays.

## Related

- [`detection.md`](detection.md) — enabling the AI person detection that fires the `people` event type.
- [`events.md`](events.md) — `events stream` consumer API that drives this loop.
- [`controls.md`](controls.md) — `audio volume`, `audio mute` (master controls that affect playback loudness).
