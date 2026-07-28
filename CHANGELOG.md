# Changelog

All notable changes to the public `reolink-cli` distribution are documented here.
This is the customer-facing release history; it tracks the LAN-only (external)
builds published as GitHub Releases.

## [0.10.1] — 2026-07-27

### Fixed

- **`self-update` could never download anything.** It asked for
  `reolink-cli-<ver>-macos-arm64.tar.gz` while the published archive is
  `reolink-cli-<ver>-external-darwin-arm64.tar.gz` — all three supported
  platforms were wrong. The archives had gained an `-external` flavour segment
  so an internal build can never be mistaken for the customer build, and the
  macOS token had moved from `macos` to `darwin`; neither reached the updater.
  It stayed invisible because the download only happens when an update exists —
  running it on the current version returns `already up to date` and never gets
  that far.

  Windows remains unsupported by `self-update` and now says so with the download
  link: that archive is a `.zip` while the updater only untars, and a running
  `.exe` cannot be replaced in place. Upgrade there by extracting the new
  archive and running `install.ps1`.

- **The agent skill misspelled `--cameras` as `--cameraes`.** A copied command
  failed with an unrecognized-argument error.

### Build

- The packaging script now refuses to produce an archive whose filename the
  updater cannot reconstruct, so this class of drift cannot ship again.

## [0.10.0] — 2026-07-25

Stored camera passwords are no longer kept in plaintext.

### Breaking

- **Passwords in `aliases.toml` are now ciphertext** (`RLENC1:…`, AES-256-GCM),
  decrypted with a key in `credentials.key` beside it (`0600`). An existing
  plaintext config is converted automatically the first time you run any
  command — **you do not have to do anything**, and hand-written plaintext
  passwords keep working and are converted on the next load. The `password` in
  `config.toml` is the last fallback in the same resolution chain and is covered
  too.
- **`aliases.toml` can no longer be copied or backed up on its own** — take
  `credentials.key` with it. With only one of the two the passwords cannot be
  recovered and must be re-entered with
  `reolink-cli device update <camera> --password-stdin`.

### Why

This tool is built to be driven by AI agents, and reading a config file is the
cheapest thing an agent can do: with plaintext, a single `cat` puts every camera
credential into a transcript that usually leaves the machine. The real isolation
boundary is still the operating system (`0600`); the ciphertext is a second
layer so that obtaining the file alone — a copy, a backup, an agent reading it —
yields nothing. It does not defend against something that reads the key file as
well.

### Notes

- One entry that cannot be decrypted no longer takes the whole file down with
  it: it keeps its ciphertext, the rest of the registry loads normally, and the
  error is raised only when that camera is actually used. Otherwise the repair
  itself (`device update`) would hit the same error and leave no way out.
- A missing or mismatched key is reported as exactly that, with the command to
  fix it — never as an empty password or a silent login failure against the
  camera.
- Encryption failure is a hard error; nothing is written. A password is never
  stored readable while reporting success.

## [0.9.1] — 2026-07-25

Found while validating the published 0.9.0 packages end to end. The security
boundary was re-verified and is unchanged (cross-origin rejection, media
endpoint authentication, no credentials in URLs, loopback-only default bind,
`0600` credential files); everything below is functional or documentation.

### Behaviour change

- **A bare `ptz focus auto` now reads the setting instead of erroring.** 0.9.0
  changed it from "silently enable autofocus" to a hard error, which stopped it
  from mutating your camera but left no way to read the setting back at all —
  you could change autofocus without being able to record what it had been.
  Writing still requires an explicit `--enable` / `--disable`.

### Fixed

- **Uninstall left the installer's `PATH` export in your shell rc.** The block
  `install.sh` appends to `~/.zshrc` says it is removed on uninstall, but
  nothing removed it: the bundled `uninstall.sh` forwards to
  `reolink-cli setup --uninstall`, which had no shell-rc handling. Every
  uninstall left behind an `export PATH` pointing at a deleted directory. It is
  now stripped precisely between its `# >>> reolink-cli PATH >>>` markers,
  across `.zshrc`, `.bashrc`, `.bash_profile` and `config.fish`. A block
  belonging to a different install prefix is left alone, and a block whose
  closing marker is missing (hand-edited) is refused rather than deleted to
  end-of-file.
- **The skill documented a `--keep-config` flag that does not exist**, so an
  agent following it produced `error: unexpected argument`. Omitting `--purge`
  is what preserves config, cache and state. The skill now also states that the
  agent skill directories are global paths, removed regardless of
  `REOLINK_PREFIX`.
- **`AGENTS.md` documented a `REOLINK_PURGE` environment variable for a full
  wipe on Windows.** `uninstall.ps1` only forwards arguments and never reads the
  environment, so anyone following it believed their stored credentials had been
  erased while the files remained on disk. Use `--purge` on both platforms.
- **An exported-but-empty `ZDOTDIR` was treated as set**, diverging from the
  installer's `${ZDOTDIR:-$HOME}`.

## [0.9.0] — 2026-07-25

Fixes from a three-platform black-box regression (macOS / Windows / Linux) and
live-hardware testing. **Contains three behaviour changes** — read the first
section before upgrading if you parse this tool's output in scripts.

### Behaviour changes (may break scripts)

- **`light ir get` now returns `on` / `off` / `auto`**, matching what `--state`
  accepts. It previously echoed the device's own words `open` / `close`, so
  `set --state off` followed by `get` reported `close` and a script asserting on
  what it had just written always failed.
- **`ptz zoom set` / `ptz focus set` no longer echo the value you passed.** They
  returned `{"pos": <your request>}` without ever reading the device back —
  asking for zoom 999 on a lens whose maximum is 27 answered `{"pos": 999}`
  while the lens sat at 27. They now read back and report
  `{pos, requested, verified}`, and when the position cannot be read they omit
  `pos` entirely and report `verified: false`.
- **`ptz focus auto` now requires an explicit `--enable` or `--disable`.** With
  no flag it used to default to "enable", so a command that reads like a query
  silently switched autofocus on.

### Fixed

- **Recording search returned nothing for any multi-day range.** The firmware
  answers a wide time range with an empty list rather than an error, which is
  indistinguishable from "no recordings" — a whole-month search always came back
  empty, and so did `--since` as soon as it spanned more than a day. The range is
  now split into per-day queries and merged. Verified on hardware: 0 → 200
  recordings for a full month.
- **`ping` with a multi-device selector failed outright** instead of fanning out,
  which is exactly the case you want it for ("which of these are online?"). It
  now emits the same `{summary, results[]}` envelope as other batch commands, and
  an unreachable camera counts as failed in the summary and exit code — it
  previously reported all-clear.
- **`setup --uninstall` killed gateway processes belonging to other installs.**
  Termination is now scoped to the prefix being removed.
- **`--purge` left the state directory behind on Windows** because the
  uninstaller derived its own paths, which had drifted from the ones the
  application uses. Both now come from one list, which also covers the legacy
  directories the app migrates from.
- **A device saying "this model has no such feature" with a 400 was
  indistinguishable from a bad parameter** — no PTZ, no SD card and an
  unsupported AI type all reported only `device command N failed`.
- The protocol selector for `stream url` is `--kind`; every documented example
  said `--protocol`, which fails.
- Corrected the documented format of a downloaded recording: current firmware
  returns a complete MP4, not the raw frame stream the docs described.

## [0.8.0] — 2026-07-25

Security release. **Contains breaking changes** — if you script the gateway HTTP
API directly, read the first two items before upgrading.

- **Camera passwords are no longer accepted in gateway URLs.** `/api/snapshot`,
  `/api/vod/download` and `/api/preview/video` now require a session token and
  resolve the device credentials server-side. Putting the password in a URL leaked
  it into shell history, `ps` output and any proxy log on the path. If you built
  those URLs with `&user=…&password=…`, get a token from `set auth.login` and pass
  `?token=…` instead; the token is bound to its device.
- **The gateway now refuses browser cross-origin requests.** Every response
  previously carried `Access-Control-Allow-Origin: *` while
  `POST /api/cameras/<name>/login` required no authentication, so any web page you
  visited could obtain a token and read your camera snapshots and live detection
  events — binding to loopback did not prevent this, because the browser runs on
  the same machine. Requests whose `Origin` does not match the address they were
  sent to are now rejected. Callers that send no `Origin` — `curl`, go2rtc, Home
  Assistant, and `<img src>` / `<video src>` embeds — are unaffected.
- **Session tokens now expire** after 300 seconds of inactivity (the window
  refreshes on each use). Previously a token stayed valid for the life of the
  gateway process.
- **MCP tools no longer accept a plaintext `password` argument.** It would be
  written verbatim into the agent's transcript. Register cameras with
  `reolink-cli device add` and target them by `alias`, or set `REOLINK_PASSWORD`
  when starting the server.
- **The gateway binds `127.0.0.1` by default** instead of all interfaces. Pass
  `--addr 0.0.0.0:9000` to expose it on the LAN deliberately.
- **Fixed a denial-of-service in XML parsing** (RUSTSEC-2026-0194 / -0195). Device
  replies are untrusted input, so a malformed one could pin the CPU.
- Snapshots, recordings, captures, log exports and the event-monitor history are
  now written owner-only; config files are written atomically so a password is
  never briefly readable by other local accounts. On Windows, config files now get
  an owner-only ACL.
- **Release archives ship a `.sha256`** — verify your download before extracting.
- **New MCP tool `camera_snapshot`** — JPEG capture, matching the `snapshot` CLI
  command.
- `preview stop` issued immediately after `preview start` no longer fails.
- `setup --uninstall` no longer leaves a stray skill document behind.

## [0.7.2] — 2026-07-21

Patch release. A full independent retest of 0.7.1 plus several rounds of deep
testing found and fixed a batch of edge-case bugs, all verified on real hardware.

- **`ping <ip>` works with a bare IP again** — it no longer demands an explicit
  `:port`.
- **Rapid, back-to-back `snapshot` calls no longer occasionally fail** — added an
  automatic retry so quick bursts (and `benchmark`) are reliable.
- **Clearer errors.** Motion-detection sensitivity is validated to the range the
  camera actually accepts; a feature the camera doesn't support now says so
  plainly instead of a cryptic failure; an unreachable camera reports a network
  error (not an auth error); `osd set --name` and `image tune` give precise
  bounds. `wifi get` output is flattened to match every other command.
- **`doctor` self-repair fixes config permissions correctly** (previously it
  could leave `config.toml` in a state the CLI itself rejected).
- Docs/help: corrected the `raw` example and the macOS cache path shown by
  `cache` / `status`.

## [0.7.1] — 2026-07-21

Patch release. Fixes found in a pre-release audit, verified on real hardware.

- **`stream url` no longer prints your password by default.** The default output
  now shows only the host, user and stream URLs (plus a `with_auth` flag). Pass
  `--with-auth` to get a ready-to-paste URL with the credentials embedded. This
  keeps passwords out of logs, terminals and AI-assistant context.
- **Light controls now take effect.** Setting the IR / night-vision LED and the
  body status LED previously reported success without changing anything on the
  camera. `light ir` and `light statusled` (and the matching MCP tools) now work,
  and `light statusled` confirms the change — returning a clear error instead of a
  false success if the camera can't apply it.
- **Clearer error when a camera name is rejected.** `osd set --name` now explains
  that the camera only accepts letters, digits, spaces and hyphens (no `_ . #`),
  instead of a cryptic protocol error.
- **Safety warnings.** The CLI warns when a password is passed on the command line
  (visible to other processes) and when the gateway is started on an address
  reachable from your network.

## [0.7.0] — 2026-07-20

- **Device running log** — browse and export the camera's on-device log
  (`reolink-cli log …`).
- **One-line install** — `curl … install.sh | sh` (macOS/Linux) and
  `install.ps1` (Windows); no Node required for the CLI or Claude Code.
- **`self-update`** pulls the latest build from GitHub Releases.
- **MCP** launcher now passes `REOLINK_GATEWAY_ADDR`, so a non-default gateway
  address works out of the box.
- **Prebuilt binaries** — macOS arm64, Linux x86_64, Windows x86_64.

## [0.6.0] — unreleased

Initial public distribution.

- LAN-only camera operation: discover, login, info, snapshot, live preview, PTZ,
  IR / spotlight / LEDs, image tuning, OSD, motion + AI detection, recording +
  SD-card status, VOD search/download, alarm events, users, reboot, firmware
  upgrade, RTSP/RTMP/FLV stream URLs.
- Cross-agent skill/plugin: install into Claude Code, Codex, Cursor, Gemini,
  OpenCode, and 70+ agents via `npx skills add`.
- Prebuilt binaries for macOS (arm64), Windows (x64), and Linux (x64),
  with `SHA256SUMS` and bundled `THIRD-PARTY-LICENSES.txt`.
