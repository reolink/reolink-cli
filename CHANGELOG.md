# Changelog

All notable changes to the public `reolink-cli` distribution are documented here.
This is the customer-facing release history; it tracks the LAN-only (external)
builds published as GitHub Releases.

## [0.10.6] — 2026-07-31

Most of this release came from issues and pull requests opened here.

### Fixed

- **`discover` dropped the UID and device name for any device that answered
  both probes** (#36). Deduplication kept the ONVIF record and discarded the
  Reolink broadcast record wholesale, under a code comment praising ONVIF's
  "rich metadata" — but the UID and the friendly name live *only* in the
  broadcast reply, and those are the two fields that let a person tell eleven
  cameras apart. The reporter had four devices listing without UIDs on Linux.

  Records are now merged per IP: the ONVIF entry gains the UID, the
  `reolink-lan://name/…` scope, the device kind, and the port-qualified host
  (`<ip>:9000`, which is what `device add --host` wants; a bare `<ip>` is not).
  An existing UID is never overwritten.

  Whether a device lands in `lan` or `lanUdp` depends on whether ONVIF is
  enabled on it (off by default on many models) and whether the network passes
  WS-Discovery (Windows Defender commonly eats it). The `counts` split still
  differs between machines and now **stops mattering** — every entry carries the
  same fields whichever bucket it landed in.

  Verified by A/B against hardware: with ONVIF temporarily enabled on a camera
  so it answered both probes, 0.10.5 reported `uid: null`, no name and a bare-IP
  host; this build reports all three with the ONVIF metadata intact.

### Documentation

Six pull requests from @ch-bas, all of them the same defect wearing different
clothes: a fact that lives in the code, restated in prose, where the
restatement had drifted.

- **`--week-table` was documented backwards** (#48). It is `Sun=bit0 … Sat=bit6`,
  now stated with its authority: the vendor SDK defines `iWeekTable` as *"index
  0:sunday, index 1~index 6:Monday->Saturday"*, with four corroborating
  definitions in the same header. The doc said `Mon=bit0` until today, so the
  `31` and `63` copied from it select the wrong days — and a schedule on the
  wrong days does not look broken.
- **`detect motion set --sensitivity` is 1–50, not 0–100** (#49). The range is
  enforced by the parser, so the doc's own example (`--sensitivity 60`) could
  never run. Confirmed three ways: the v20 spec, and both a camera and an NVR
  reporting `{"min": 1, "max": 50}` for themselves.
- **The skill's install snippet could never download anything on macOS** (#47):
  it mapped `Darwin` to `macos` while the published asset says `darwin`, and its
  glob omitted `-external-`.
- **Windows users are no longer told to `self-update`** in the quick start
  (#42) — it covers macOS and Linux only, as the same README says further down.
- **The archive example is platform-agnostic and zsh-safe** (#40); zsh treats an
  unmatched glob as an error rather than passing it through.
- Reference docs no longer restate value ranges or deprecation status (#50).
  `--help` is generated from the code and cannot drift; a hand-copy only gets
  staler. What stays is what `--help` cannot say — for instance that motion and
  AI sensitivity use *different* scales, which is the trap, not the numbers.

### Build

- The version lived in sixteen hand-edited places; now it lives in two. The six
  crates inherit `[workspace.package]`, both README badges became live
  shields.io release lookups (a copy that cannot go stale beats a copy that is
  checked), and the skill's example output no longer names a version. Cutting a
  release is now one line plus a CHANGELOG entry.
- `scripts/check-doc-commands.py` feeds every `reolink-cli` line in a fenced
  code block to the real binary's parser, which validates subcommands, flag
  names and value ranges before a command does anything. It runs against
  TEST-NET-1 with config paths redirected to a temp dir, so nothing touches a
  device. Verified to catch rather than merely pass: restoring `--sensitivity
  60` makes it fail. It cannot see whether a documented *meaning* is right —
  that class is what a human reader catches.

### Policy

- **Published releases and tags are permanent from now on** (#38). Deleting a
  superseded release breaks every downstream pinning that version, and it was
  wrong of us to do it. `v*` tags are now protected by a ruleset with no bypass
  actors (verified: an admin deletion attempt returns 422). Releases 0.10.0
  through 0.10.4 were deleted under the old policy and cannot be honestly
  restored; **0.10.5 is the oldest surviving release and the first one covered
  by this guarantee.**

## [0.10.5] — 2026-07-30

### Fixed

- **`setup --uninstall` did not stop your own gateway on macOS**, then deleted
  the binary out from under it, leaving a process running a file that no longer
  exists.

  This came out of a contributor report (#29, #31) about the docs' manual
  `pkill -f reolink-gateway` fallback matching every install on the machine. The
  same mistake was one layer down in the code, and worse there:
  `process_exe_path` used `ps -p <pid> -o comm=` on non-Linux platforms under a
  comment asserting that prints the executable's full path. It does not — it
  echoes argv[0], so a gateway started as `reolink-gateway` from `PATH` reported
  a bare name, which the ownership check rejects as non-absolute. That comment
  had never been executed.

  The question is now asked backwards: `lsof -t -a -d txt <prefix>/bin/reolink-gateway`
  lists the processes whose *executing image* is that file, which avoids argv
  entirely. `-d txt` restricts it to the image, so a process merely reading the
  binary is not a candidate. Linux keeps `/proc/<pid>/exe`.

  Verified with two gateways from different prefixes, one started by bare name:
  ours was stopped, the second install was left alone.

### Verified

- **`device expand` now has hardware behind it on the firmware from #25.** An
  RLN4E running v3.6.5.562 — the same version as the RLN8-410 in that report —
  confirms the original bug (cmd 199 answers code 300) and the fix: the channel
  with a camera answers, empty channels are refused, and scanning 20 channels
  takes 0.9 seconds.

  The channel field genuinely selects the channel, which is worth stating on its
  own: a protocol that ignored it would look identical on a one-camera device,
  with every channel returning channel 0's data.

  Correction to a note in #25 along the way: on an NVR with no cameras attached,
  cmd 44 is refused on *every* channel, which briefly read as the firmware not
  implementing it. It does. The refusal means "no camera on that channel" —
  exactly the signal the probe wants.

  Non-contiguous numbering is covered by an integration test reproducing the
  reporter's device. Reverting the naming to the 0.10.3 behaviour makes it fail,
  which is the only reason to believe it guards anything.

## [0.10.4] — 2026-07-30

Four fixes found by installing 0.10.3 and running it against real hardware. The
first is 0.10.3's own.

### Fixed

- **`device expand` named child cameras after the wrong channel.** The `channel`
  field was correct; the names were not. Defaults and descriptions used the
  position in the discovered list rather than the real channel number. On the
  NVR from #25 — cameras on channels 1, 9, 10 and 11 — that produces `nvr-ch0`
  through `nvr-ch3`, four aliases each claiming a channel it does not connect to.

  Nothing fails loudly, which is what makes it bad: you find out by wondering
  why `nvr-ch1` shows the wrong camera. It was 0.10.3's fix left half-done — the
  probe learned the real channel numbers and the naming never used them.

  Non-contiguous-channel hardware is not something I have, so this is pinned by
  three unit tests rather than one hand-check.

- **`reolink-gateway --help`, `--version` and `--addr` all failed with
  "invalid socket address".** The binary took `args[1]` as the listen address,
  so any flag was handed to `bind()` and the error pointed at something entirely
  unrelated to the real problem. Unrecognised arguments are now rejected by name;
  `--addr` and the bare positional form both work (`reolink-cli gateway start`
  uses the positional one). `reolink-gateway --version` also reports the build
  flavor now, the same way the CLI does.

- **The CLI could hang forever talking to the gateway.** If something occupies
  the gateway port and accepts the connection without answering, the control
  channel had no timeout: no output, no exit, indefinitely — and an AI agent
  driving the CLI wedges with it. Docker and OrbStack both listen on `:9000` by
  default, the port this tool documents, so it is easy to land in. There is now
  a 60-second bound on the control channel with an error naming the likely
  cause. Preview and VOD share the underlying read path and stay unbounded on
  purpose.

- **The channel scan had no overall budget.** Per-request I/O timeouts (10s) add
  up once a device stops answering mid-scan. The scan is capped at 30 seconds
  total and reports how far it got (`scanned` / `requested`), so a truncated
  scan reads as "checked 6 of 20" instead of looking like a complete answer.

### Added

- **`./scripts/check-version-sync.sh --set <version>`** rewrites all nine version
  locations from one list, then re-checks its own work so a location whose
  pattern drifted is reported rather than skipped (#7, #27).

## [0.10.3] — 2026-07-30

Came from an issue opened here.

### Fixed

- **`device expand` failed on an NVR that declines `GetSupport`** (#25). An
  RLN8-410 on firmware v3.6.5.562 answers cmd 199 with code 300, which aborted
  the whole command.

  Following that report turned up a second, quieter bug: **even when 199
  succeeded, the channels written were wrong.** `channelNum` is a *count*, and
  the code registered `0..count`. The reporter's four cameras sit on channels
  1, 9, 10 and 11 — so on a cooperative NVR it would have created four entries
  pointing at slots 0–3, three of them empty.

  `expand` now asks 199 for an upper bound when it answers, ignores it when it
  does not, then probes each channel and registers only the ones that answer,
  with their real channel number. The probe uses cmd 44 (OSD get), which is
  per-channel and refused on an empty slot.

  The probe runs on **one** connection. The channel travels in each request's
  extension XML rather than in the session, so a single connection can ask
  about every channel. Opening a session per channel would hold one TCP
  connection per candidate — the gateway pools sessions with a 300-second TTL
  and reaps them lazily — and an NVR that caps concurrent connections would
  start refusing partway through, silently reporting the rest as empty. That
  would produce a short, confident, wrong channel list: worse than the hard
  failure it replaced. Measured after scanning 20 channels: 1 established
  connection to the device.

  Not verified: no RLN8-410 here. The single-connection property and the
  single-camera refusal are verified on hardware; the non-contiguous channel
  path is sound in logic and untested in fact.

## [0.10.2] — 2026-07-29

Both changes came from issues opened here.

### Added

- **`config get performance`** — live device load: `cpuUsedPercent`, `codeRate`,
  `netDataRate` (#9). Verified on hardware: an E1 Outdoor reports 60% CPU.

  Not every model implements it. Those answer with a device-level rejection
  rather than a fabricated zero — a camera reported as 0% busy when it never
  said so would be worse than an error. `codeRate` reads 0 on an idle camera and
  only becomes meaningful while a stream is running; it is reported rather than
  hidden, so you can tell "idle" from "not reported".

  This is distinct from `benchmark`, which times the **client** round trip.

### Fixed

- **Protocol-detection failures blamed the host when the host was fine** (#10).
  An NVR channel failed with `unable to detect protocol — device unreachable, or
  not a Reolink v20/v30 device` while another channel on the same host worked in
  the same session, sending the reporter to check VLAN routing and firewall
  rules.

  Each channel opens its own session, so the probe runs **per channel** —
  blaming the host is wrong by construction whenever another channel is working.
  The probe also collapsed four outcomes into one: connect timed out, connect
  refused, **connected but no answer**, and unrecognised magic. That third case
  matters: a device that is up but declining an additional connection looks
  identical on the wire to one that is unreachable.

  The message now names the channel and the actual failure, and points at
  `--protocol v20` to skip the probe.

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

## [0.6.0] — not published

Prepared as the first public distribution but never released here; the
first published release was 0.7.0. Kept for the record of what it covered.

- LAN-only camera operation: discover, login, info, snapshot, live preview, PTZ,
  IR / spotlight / LEDs, image tuning, OSD, motion + AI detection, recording +
  SD-card status, VOD search/download, alarm events, users, reboot, firmware
  upgrade, RTSP/RTMP/FLV stream URLs.
- Cross-agent skill/plugin: install into Claude Code, Codex, Cursor, Gemini,
  OpenCode, and 70+ agents via `npx skills add`.
- Prebuilt binaries for macOS (arm64), Windows (x64), and Linux (x64),
  with `SHA256SUMS` and bundled `THIRD-PARTY-LICENSES.txt`.
