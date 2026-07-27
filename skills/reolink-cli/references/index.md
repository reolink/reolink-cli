# Recipe Index

Load the file matching your task — don't read all of them.

| File | Read when the task involves |
|---|---|
| [`setup.md`](setup.md) | Discovery (`discover`), device registry (`device add/list/update/remove/import/inventory`), identity (`ping`, `login`, `info`, `capabilities`), or generic `config get/set` paths |
| [`media.md`](media.md) | Preview (`preview capture/play/start/stop`), snapshot, `stream url` (RTSP/RTMP/FLV integration helper for Frigate / HA / go2rtc / VLC), VOD search & download |
| [`controls.md`](controls.md) | Light (IR / status-LED / spotlight / whiteled), image (flip / tune), OSD, audio, privacy mask |
| [`ptz.md`](ptz.md) | Any `ptz …` — movement, presets, zoom/focus, patrol, guard, autotrack |
| [`detection.md`](detection.md) | Motion detection, per-type AI detection (`detect motion` / `detect ai`) |
| [`recording.md`](recording.md) | Record schedule + core config (`record schedule get/set`, `record config get`, week bitmap, daily/weekly windows) |
| [`storage.md`](storage.md) | SD card / HDD read-only status (`storage status`) |
| [`notifications.md`](notifications.md) | Mobile push (`notify push get/set`) — device's own cloud push, not gateway events |
| [`events.md`](events.md) | Gateway event bus — `events query` snapshot, `events stream` NDJSON, event shape & type vocabulary |
| [`event-monitor.md`](event-monitor.md) | `events monitor` rule engine — declarative "on X do Y" automation (`events monitor init/check/run`), replaces shell watcher scripts |
| [`voice-alert.md`](voice-alert.md) | Detection → TTS → camera speaker (`audio talk`). Dynamic voice alerts on person/vehicle events via cmd 201/202 talkback |
| [`admin.md`](admin.md) | Device user accounts (`users …`), `system reboot`, `system upgrade` (firmware flash), raw debug commands |
| [`gateway-http.md`](gateway-http.md) | Driving the gateway's `POST /api` from curl / a non-CLI client |
| [`troubleshooting.md`](troubleshooting.md) | Something failed and you need to diagnose; user phrased a request ambiguously and you need the full intent-map |

Each topic file is self-contained with copy-pasteable examples. Safety conventions (credential handling, "ping → login → read → write → verify" flow) are in the parent `SKILL.md` — don't duplicate them here.
