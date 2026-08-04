# Changelog

All notable changes to the public `reolink-cli` distribution are documented here.
This is the customer-facing release history; it tracks the LAN-only (external)
builds published as GitHub Releases.

## [0.10.8] — 2026-08-04

A security release. Three of these were found by auditing our own code rather
than by a report, and one of them was introduced by the previous release's
hardening.

### Security

- **`reolink-cli self-update` verified nothing at all.** It resolved the latest
  release, downloaded the archive, unpacked it and overwrote both binaries — no
  checksum, no signature — and carried its own `REOLINK_UPDATE_REPO` override
  with nothing anchoring it. 0.10.5 gave the installers a committed-checksum
  anchor and left this path untouched, and it is the one that runs on machines
  that already have the tool, repeatedly, often with `--yes`. It now verifies
  against the same committed checksum and fails closed.

- **The gateway's cross-origin guard was bypassable by DNS rebinding.** It
  compared `Origin` against `Host`, and rebinding makes those agree: an
  attacker's domain, re-resolved to 127.0.0.1, produces a request where both are
  `evil.example`. The guard allowed it and `Access-Control-Allow-Origin: *`
  handed the response back. Not merely a read —
  `POST /api/cameras/<name>/login` authenticates with the password stored in
  `aliases.toml`, so any page could mint a token and then read snapshots and the
  live event stream. The gateway now also requires `Host` to be an address it
  actually bound to.

  **Consequence, deliberate:** reaching the dashboard from a browser through a
  custom hostname is refused. Use `localhost`, `127.0.0.1`, or the bound
  address. Requests without an `Origin` — `curl`, go2rtc, Home Assistant
  server-side pulls, `<img src>` — are unaffected.

- **The event stream never re-checked its token.** `/api/events` validated once
  at connect and then streamed forever, so a stream opened with a valid token
  kept delivering camera events long after that token expired. It now re-checks
  every 30 s and closes when the token is gone — using a check that deliberately
  does *not* refresh the inactivity window, or a subscription would renew its
  own token indefinitely.

- **`self-update`'s scratch directory could be taken over.** It was
  `create_dir_all` on a predictable `<tmp>/reolink-update-<pid>`, and
  `create_dir_all` succeeds when the path already exists. Another local user
  could own that directory and swap the archive in the window between the
  checksum passing and the two later reads of the same file — installing
  binaries that were never verified and are then executed. Now created
  exclusively, mode 0700 at creation, with a random component.

- **A dead hook shipped in every release archive piped an environment-variable
  URL into a shell.** `plugins/reolink-cli/scripts/ensure-binaries.sh` carried
  three `curl "$REOLINK_REPO_URL/-/raw/master/scripts/install.sh" | sh` calls
  with no verification of any kind, against a GitLab-shaped path left over from
  when this project was private. No manifest registered it and nothing invoked
  it. Deleted rather than hardened.

- **The tarball's Windows installer could discard your Claude Code settings.**
  On any read or parse error it fell back to an empty object and wrote that over
  the file — for `~/.claude/settings.json` that is permissions, hooks, model
  settings and MCP servers. It now leaves an unreadable file untouched and says
  so.

- **`GITHUB_TOKEN` was on curl's command line** in `install.sh`, where `ps`
  makes it readable by every other user on the machine — while `self_update.rs`
  refused to do exactly that and explained why. The header now goes to curl on
  stdin.

### Fixed

- **Uninstalling killed every gateway on the machine, not just this install's.**
  The Windows branch called `taskkill /F /IM reolink-gateway.exe` directly below
  a comment explaining that it must not, because that is image-name-wide and
  hits other installations. Same defect as #29 on Unix, fixed there and left
  standing here. It now filters by executable path, and says which processes it
  skipped.

- **`setup --uninstall` exited 0 having left `reolink-cli` behind on Windows.**
  The OS locks a running image so the binary cannot delete itself; that printed
  a warning and reported success, which is what a script or package manager
  reads. It now exits non-zero and gives the one command that finishes the job.

- **`self-update` asked for confirmation before checking whether the platform is
  supported**, so a Windows user consented to an update that was never possible.

- **The cross-origin guard refused a gateway bound to port 80**, because a
  browser omits the default port and the new `Host` check required one.

- Two independent sources of test-suite flakiness, together failing about one
  run in four: temp directories named from a clock that is not
  nanosecond-granular, and an `lsof` latency being reported as a logic failure.

### Documentation

- `SECURITY.md` states what download verification proves and what it does not,
  and that **any local process able to reach the gateway port can control your
  cameras** — the boundary is the machine, not the process.
- The one-line install had no documented uninstall path; `setup --uninstall` is
  now the primary instruction.
- `scripts/check-past-findings.py` turns every previously reported defect into
  an assertion, so they cannot quietly regress.

## [0.10.7] — 2026-08-03

### Security

Reported privately as GHSA-65x2-w384-qp7j by Bassem Chagra, as a follow-up to
the report behind 0.10.5's committed-checksum change. Two of the three findings
were valid as filed; the third was half right, and investigating it turned up a
worse hole in a path the report did not cover.

- **`self-update` verified nothing at all.** It resolved the latest release,
  downloaded the archive, unpacked it, and overwrote both binaries — no
  checksum, no signature — and carried its own `REOLINK_UPDATE_REPO` override
  with nothing anchoring it. The installers had been given a committed-checksum
  anchor in 0.10.5; this path had not, and it is the one that runs on every
  machine that already has the tool, repeatedly, often with `--yes`. It now
  verifies against the same committed checksum and fails closed. Not in the
  report — found while checking it.

- **The checksum source followed `REOLINK_REPO`** (finding 2). Both the archive
  and the checksum were fetched from the overridden repository, so pointing it
  at another repository meant the archive was validated against *that*
  repository's own committed checksums: attacker supplies both halves, every
  check passes, and the installer prints "ok". The checksum source is now pinned
  to `reolink/reolink-cli` in `install.sh`, `install.ps1` and `self-update`.
  `REOLINK_REPO` still moves the download, so a mirror serving identical bytes
  works; a fork serving its own build no longer validates itself.

- **A crafted archive could choose which binary got installed** (finding 3).
  The binaries were located with `find "$tmp" -name reolink-cli | head -n1`,
  which searches the whole extraction tree and takes whatever the walk reaches
  first — so an archive carrying a second `reolink-cli` under a directory
  sorting earlier won, and that file was then made executable and run.
  Reproduced with such an archive before fixing. All three paths now derive the
  directory name from the asset name and read `bin/<name>` from it, and refuse
  a symlink or reparse point in that position.

  The other half of that finding — that `..` and absolute members could write
  outside the extraction directory — did **not** reproduce: BSD tar refuses `..`
  and exits non-zero, GNU/busybox tar strips the prefix and keeps the file
  inside the destination. A pre-scan that refuses both member types was added
  anyway, so the guarantee comes from our code rather than from whichever tar
  is installed.

- **The README told manual verifiers to use the anchor it had just discredited**
  (finding 4). Two passages pointed at the release-attached `SHA256SUMS` while a
  third explained why that file cannot be trusted. All now point at
  `checksums/<tag>.sha256`, with a worked example.

- **`SECURITY.md` now states what verification does and does not prove**, as a
  table of covered and uncovered threats. The uncovered ones are a compromised
  maintainer account and a compromised build machine: the checksum is written by
  the same pipeline that builds the archive, so integrity here is not
  authenticity. Closing that needs a signature anchored outside the pipeline,
  which this project does not have yet — GitHub build attestation is not
  currently possible because releases are not built in GitHub Actions.

### Added

- **Statically linked musl builds for Linux x86_64 and arm64** (#54).
  `reolink-cli-<ver>-external-linux-arm64-musl.tar.gz` and its x86_64 sibling
  join the release. Alpine and the distributions built on it — Home Assistant
  OS is the one that raised this — have no glibc, so the existing Linux
  archives could not merely run badly there, they could not load at all:
  `Error relocating ./reolink-cli: __res_init: symbol not found`. The musl
  archives are static and need no runtime at all.

  `install.sh` detects musl (loader path, with `ldd --version` as a second
  probe) and picks the right archive; `self-update` resolves the musl archive
  when the running binary is a musl build, which it can only know at compile
  time — `env::consts` reports `linux`/`aarch64` for both C libraries, and a
  musl install that updated itself into a glibc binary would be unable to
  start.

  x86_64 is included although only arm64 was asked for. Adding musl detection
  to the installer and then publishing one of the two architectures would mean
  x86_64 Alpine detects musl and finds no archive — a worse failure than not
  detecting it at all.

  These are additions. The glibc archives keep their names, because an existing
  install reconstructs the same filename it came from when it self-updates.

- **`discover` now reports each device's `mac` and hardware model** (#36).
  Asked for by the reporter of the merge bug — a MAC is what lets you line
  eleven cameras up against DHCP leases, and the model is useful for the
  devices that do not answer ONVIF, which is most of them out of the box.

  Both were already in the broadcast reply and were being read past: the
  layout is `net_scan_devinfo_t` from the vendor SDK header, `cMac[32]` at
  offset 164 and `cMouduleType[32]` at 196. The model is published as a
  `reolink-lan://hardware/<model>` scope, mirroring ONVIF's
  `onvif://www.onvif.org/hardware/<model>`, so "what model is this" has one
  place to look whichever probe answered. `mac` merges into the ONVIF record
  like `uid` does, and never overwrites an existing value.

  The `access_key` in the same reply stays unread. It is a credential, it does
  not help identify anything, and the reply is an unauthenticated LAN broadcast
  whose contents end up in logs and agent transcripts. A test asserts it does
  not appear in the output.

### Fixed

- **`REOLINK_PASSWORD` triggered the warning telling you not to put passwords
  on the command line.** `--password` reads that environment variable, so by
  the time the value arrived it was indistinguishable from one typed on argv,
  and the check warned for both — telling anyone following the documented safe
  path to stop doing exactly what they were doing, and printing a second,
  duplicate warning for the people who really were on argv. The remaining check
  reads the actual argv, so it can tell the difference. `--password` on the
  command line still warns, once.

- **`device import` ignored the friendly name of any device without ONVIF.**
  The scope lookup only understood `onvif://www.onvif.org/<key>/`, but the
  Reolink broadcast publishes the name as `reolink-lan://name/…` — so on the
  models that ship with ONVIF off, which is most of them, imported cameras were
  described as "Discovered via lanUdp" and aliased off their IP address. 0.10.6
  had stopped `discover` from throwing that name away; the one command that
  would use it was not looking where it is kept. The lookup now accepts either
  scheme, ONVIF first, so registries that already import keep their aliases
  unchanged.

- **`AGENTS.md` and `GEMINI.md` still described a private-vendor tarball.**
  They told agents to "get a fresh release tarball from their vendor" and
  stated there was "no in-place network upgrade" — while line 131 of the same
  file documented `reolink-cli self-update`, which does exactly that. The
  troubleshooting table also documented an error message,
  `no prebuilt binary for <os>-<arch>`, that appears in neither installer; the
  real ones are `unsupported OS` / `unsupported arch`. Both files now describe
  the one-line installer and `self-update`, and the table lists the strings the
  installers actually print, plus the musl symptom.

- **`GEMINI.md` had the stale "works without the gateway" list**, the one
  corrected in `SKILL.md` a release earlier: `features`, `doctor` and
  `cache status|clean` need no gateway either, and they are what an agent
  reaches for first. One copy had been fixed and the other had not, which is
  the whole problem in miniature.

### Changed

- **The skill's install snippet is now a call to `install.sh`** rather than its
  own copy of the download logic. That copy was the fourth place platform
  detection lived, it had already drifted once (#43), and — the reason this is
  a fix and not tidying — it verified nothing it downloaded. `install.sh`
  checks the archive against the checksum committed to this repository and
  refuses to install on a mismatch.

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
