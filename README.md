<div align="center">

<img src="docs/banner.svg" alt="Reolink CLI" width="320">

**A local-first command-line tool for operating Reolink cameras — JSON by default, with a built-in MCP server and a cross-agent skill so AI agents drive the same core.**

![release](https://img.shields.io/github/v/release/reolink/reolink-cli)
![platform](https://img.shields.io/badge/platform-macOS%20·%20Linux%20·%20Windows-lightgrey)
![build](https://img.shields.io/badge/build-external%20·%20LAN--only-green)

</div>

---

Control Reolink cameras over your **local network** — no cloud account, no app.
Script it with `jq`, or let an AI agent drive it in plain language.

```console
$ reolink-cli --camera front-door info | jq '{model, firmware, name}'
{
  "model": "Reolink Video Doorbell",
  "firmware": "v3.0.0.6696_26062799",
  "name": "Front Door"
}
```

> **What this repository is.** The official distribution point for the prebuilt
> `reolink-cli` binaries (proprietary, royalty-free EULA — see [License](#license)),
> plus the agent skill, plugin manifests and installers (Apache 2.0). The CLI
> source code is not published here.

## Does it work with my camera?

It talks to Reolink devices directly over your LAN:

- **IP cameras and video doorbells** with a LAN address, wired or Wi-Fi
- **NVRs and the Home Hub** — `device expand <nvr>` registers one entry per
  channel, which is also the only way to reach a battery camera paired to a hub
- **Battery cameras**, on your Wi-Fi or through a Home Hub — a sleeping camera
  can take several seconds to answer the first command

Features differ by model. Ask the camera rather than guessing:

```bash
reolink-cli --camera porch capabilities
```

An operation the model does not implement fails with a clear "device does not
support" error, never silently.

## Highlights

- 🔍 **Discovery** — LAN broadcast, plus bulk `device import`
- 🎥 **Live media** — `preview play`, file/stdout capture, batch capture, JPEG snapshot
- 🕹️ **PTZ** — pan/tilt/zoom, presets, patrol, guard, autotrack, real timed jog
- 💡 **Lights** — IR, spotlight (with native **blink**), white-LED, status LED
- 🎚️ **Video encoder** — resolution, frame rate, bit rate, H.264/H.265, GOP per stream
- 📢 **Siren** — sound / silence the built-in siren on demand
- 🧠 **Detection** — motion + AI (person / vehicle / dog_cat / package)
- 📼 **Recording & storage** — schedule, SD/HDD status, VOD search & download
- 🔔 **Events** — query/stream + a declarative rule engine (`events monitor`)
- 🗣️ **Two-way audio** — talkback / TTS straight to the camera speaker
- 🌐 **Stream URLs** — RTSP / RTMP / FLV for Frigate, Home Assistant, go2rtc, VLC
- 🤖 **AI-native** — built-in MCP stdio server + cross-agent operator skill
- 🧩 **Fleet-aware** — camera & tag selectors, local session daemon for a fast control plane

The authoritative command list comes from the binary: `reolink-cli --help`,
`reolink-cli <command> --help`, or `reolink-cli features` for a machine-readable
manifest.

<details>
<summary>Command overview</summary>

| Area | Commands | What you can do |
|---|---|---|
| **Setup & registry** | `init`, `device`, `config`, `doctor`, `setup` | Scaffold config, register/import cameras, tag them, health-check the install |
| **Connect & inspect** | `ping`, `login`, `info`, `capabilities`, `status`, `benchmark` | Reach a camera, read model/firmware/serial, list what the model supports, measure round-trip latency |
| **Discovery** | `discover` | Find cameras on the LAN (broadcast) |
| **Live media** | `preview`, `snapshot`, `stream` | Play or capture live video, grab a JPEG, print RTSP/RTMP/FLV URLs |
| **Image & encoder** | `image`, `encode`, `osd` | Flip/mirror, encoder settings per stream, on-screen name/time overlay |
| **Lights** | `light` | IR / night vision, spotlight (with **blink**), white-LED, status LED |
| **Audio** | `audio` | Volume, alarm mute, **siren**, quick replies, two-way talkback / TTS |
| **PTZ** | `ptz` | Pan / tilt / zoom, focus, presets, patrol, guard, autotrack, timed jog |
| **Detection & events** | `detect`, `notify`, `events` | Motion + AI detection, push settings, query/stream events, rule engine |
| **Recording & storage** | `record`, `vod`, `storage`, `log` | Recording schedule, VOD search & download, SD/HDD status, device logs |
| **Privacy & users** | `privacy`, `users` | Privacy-mask regions, manage device accounts |
| **Network** | `wifi` | Push a new SSID + PSK (pre-validated), auto-rediscover, update the registry |
| **System** | `system` | Reboot |
| **Gateway & tooling** | `gateway`, `mcp-server`, `plugin`, `cache`, `self-update` | Run the local gateway, expose MCP tools, maintain the skill cache, update the binaries |

</details>

## Install

### Claude Code — no Node required

```text
/plugin marketplace add reolink/reolink-cli
/plugin install reolink-cli@reolink-cli
```

The plugin carries both the skill and the MCP server. The binary for your
platform is fetched the first time you ask about a camera, and the agent starts
the local gateway when it needs it. Then just talk: *“show me the front door
camera”*, *“point the back-yard camera left”*, *“blink the porch spotlight 3
times”*.

### Other agents — requires [Node.js](https://nodejs.org)

Codex, Cursor, Gemini, Copilot, OpenCode and 70+ others:

```bash
npx skills@latest add reolink/reolink-cli
```

Pick `reolink-cli` and the agents to install it into; the binary is fetched on
first use, as above.

### Command line only — no Node required

Installs `reolink-cli` + `reolink-gateway` to `~/.local/bin` (no `sudo`) and
initializes config:

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh | sh
```

```powershell
# Windows — works from PowerShell or the Command Prompt
powershell -NoProfile -Command "iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 -UseBasicParsing | iex"
```

Both installers verify the download before installing anything — see
[Installers](#installers) for exactly what they do.

**Upgrading:** `reolink-cli self-update --yes` on macOS/Linux. On Windows,
re-run the installer (a running `.exe` cannot replace itself).

<details>
<summary>Prefer a downloadable archive?</summary>

Grab the archive for your platform from the
[latest Release](https://github.com/reolink/reolink-cli/releases/latest),
[verify it](#verifying-a-download), extract, and run the bundled installer:

```bash
tar -xzf reolink-cli-*.tar.gz && cd reolink-cli-*/ && ./install.sh
# Windows: extract the .zip and run .\install.ps1
```

The archive is self-contained: binaries + the skill/plugin + installer +
`THIRD-PARTY-LICENSES.txt`.

</details>

<details>
<summary>Uninstall</summary>

```bash
reolink-cli setup --uninstall            # add --purge to also delete config and the camera registry
npx skills remove reolink-cli            # if you installed the skill with npx
```

Claude Code users: also run `/plugin uninstall reolink-cli`.

</details>

## Quick start

**1. Start the gateway.** Most commands go through a small local process that
keeps camera sessions open, so repeated commands are fast. Leave it running in
its own terminal (or under your service manager):

```bash
reolink-cli gateway start --addr 127.0.0.1:9000
```

**2. Tell the CLI where it is** — for this shell, or permanently by adding
`gateway-addr = "127.0.0.1:9000"` to `config.toml` (`reolink-cli doctor` prints
where that file lives):

```bash
export REOLINK_GATEWAY_ADDR=127.0.0.1:9000
```

Port 9000 already taken (Portainer, MinIO, …)? Use any free port in both places.

**3. Find a camera, register it, use it:**

```bash
reolink-cli discover                                      # cameras on your LAN
reolink-cli device add porch --host 192.168.1.41 --user admin --password-stdin
reolink-cli --camera porch info
reolink-cli --camera porch snapshot --file ./porch.jpg
```

`--password-stdin` prompts for the password, so it never lands in your shell
history. `device list` also shows a few disabled example entries the installer
wrote to illustrate the file format — `device remove <name>` clears them.

Many cameras at once — credentials via the environment, never `--password`:

```bash
export REOLINK_PASSWORD='<device-password>'
reolink-cli --user admin device import
unset REOLINK_PASSWORD
```

`preview play` needs `ffplay` on `PATH` (or pass `--player`, or set
`REOLINK_PLAYER`).

## Multi-device workflow

Target selection stays explicit — there is no hidden “current device” state.

| Selector | Meaning |
|---|---|
| `--camera <name>` | one registered device |
| `--cameras <a,b,c>` | several registered devices |
| `--tag <tag>` | every device carrying a tag |
| `--all-devices` | the whole registry |
| `--host <ip[:port]>` | an ad-hoc device by address |

```bash
reolink-cli device list
reolink-cli --tag outdoor device inventory --capabilities
reolink-cli --tag outdoor snapshot           # fan out across a tag group
```

## Frigate, Home Assistant, go2rtc, VLC

Print a camera's stream URLs, read from its real port configuration:

```bash
reolink-cli --camera porch stream url --kind rtsp,rtmp,flv --stream main,sub
```

Credentials come back as separate JSON fields. `--with-auth` embeds
`user:password@` in the URL for players that need it — treat that output as a
password.

## AI agents & MCP

Two ways in, both driving the same runtime as the CLI:

- **The skill** — natural language. It teaches the agent the command surface and
  the safety rules, so you say *“point the driveway cam to preset 2, then take a
  snapshot”* or *“let me know if anyone shows up at the door tonight”*. The agent
  **never guesses device state** — it only reports what a command returned.
- **The MCP server** — typed tool calls for tight automation loops. The Claude
  Code plugin already registers it. For any other MCP client:

  ```json
  "mcpServers": {
    "reolink-cli": {
      "command": "reolink-cli",
      "args": ["mcp-server"],
      "env": { "REOLINK_GATEWAY_ADDR": "127.0.0.1:9000" }
    }
  }
  ```

  JSON-RPC 2.0 over stdio; the gateway must be running, as for the CLI.

## Platform support

Prebuilt binaries on each [Release](https://github.com/reolink/reolink-cli/releases):

| OS | Architectures |
|---|---|
| macOS | arm64 (Apple Silicon) |
| Linux (glibc) | x86_64, arm64 |
| Linux (musl, static) | x86_64, arm64 — Alpine, Home Assistant OS, slim Docker images |
| Linux 32-bit ARM | armv7 (Pi 2/3/4 on a 32-bit OS), armv6 (Pi 1 / Zero) — glibc 2.28+ |
| Windows | x86_64 |

`install.sh` picks the right one for you, including on a Raspberry Pi whose
64-bit kernel runs a 32-bit userland. Choosing by hand? `getconf LONG_BIT`
decides arm64 vs armv7, not `uname -m`; and when unsure between glibc and musl,
take musl — it runs on both, while a glibc build on a musl host fails with a
confusing `symbol not found`. `file "$(command -v reolink-cli)"` says
"statically linked" for a musl build.

**Home Assistant OS:** the `homeassistant` container is aarch64 Alpine. Run the
one-line installer *inside that container* (it selects musl), and make sure the
gateway is reachable from there — start it in the same container, or point
`REOLINK_GATEWAY_ADDR` at one on the LAN.

## Responsible use

Use this tool only on cameras you own or are authorised to administer.
`discover` and `ping` are for locating your own devices, not for sweeping
networks you were not asked to work on. Snapshots, recordings and event history
written to disk are personal data — protect them like the camera's own storage,
and delete what you no longer need.

## Security

- **The gateway binds `127.0.0.1` by default** and refuses browser
  cross-origin requests. `--addr 0.0.0.0:9000` exposes camera control to your
  whole LAN — do it deliberately.
- **LAN-only build.** Remote access via Reolink's P2P relay is not included;
  `reolink-cli --version` shows `(external · LAN-only)`.
- **Report vulnerabilities privately** — see [SECURITY.md](SECURITY.md), which
  also documents what the tool does by design.

### Safe credential handling

- **Never pass `--password` on the command line** — it shows up in `ps` and
  your shell history. Use `--password-stdin`, `REOLINK_PASSWORD`, or register
  the camera once with `device add` and refer to it by name.
- **Stored passwords are encrypted at rest** (AES-256-GCM) with a
  `credentials.key` kept next to the registry. Config files are owner-only
  (`0600`) and the CLI refuses to read them otherwise. **Back up the registry and
  its `credentials.key` as a pair** — neither works without the other. Details:
  [SECURITY.md → Stored credentials](SECURITY.md#stored-credentials).
- **Credentials never go in a URL.** Gateway media endpoints use a session token
  that expires after 300 s of inactivity. The one exception is
  `stream url --with-auth`, which you ask for explicitly.
- **Redact before sharing output** — it can contain UIDs, serial numbers, LAN
  addresses and stream URLs.

## Installers

`install.sh` and `install.ps1` are plain text — read them before running. They:

- download the latest release from `github.com` only
- **verify it against `checksums/<tag>.sha256` committed to this repository's
  default branch**, never the checksum attached to the release, and abort on any
  mismatch or missing entry
- install two binaries to `~/.local/bin` (`%USERPROFILE%\.local\bin` on
  Windows) — no `sudo`, no system directories, no services
- stop a running `reolink-gateway` only if it runs from that same prefix
- overwrite previous binaries in that prefix; nothing else on disk is modified
- add the prefix to your user `PATH` if it is missing (Windows)

### Verifying a download

```bash
tag=vX.Y.Z                                    # the release you downloaded
curl -fsSL -o CHECKSUMS \
  "https://raw.githubusercontent.com/reolink/reolink-cli/main/checksums/$tag.sha256"
shasum -a 256 -c CHECKSUMS --ignore-missing    # sha256sum -c on Linux
```

Use this committed file, **not** the `SHA256SUMS` attached to the release:
whoever can replace a release asset can regenerate the checksum beside it. This
proves integrity, not who built the archive — [SECURITY.md](SECURITY.md#download-verification-what-it-proves-and-what-it-does-not)
states exactly what it does and does not cover.

## Trademarks

"Reolink" and the Reolink logo are trademarks of Reolink Innovation Limited.
The Apache 2.0 licence covers the code and docs in this repository — it grants
no rights to the Reolink name or logo. If you publish a fork, rename it and
remove the marks; see [TRADEMARKS.md](TRADEMARKS.md).

## License

- **This repository** — the skill, plugin manifests, installers and docs — is
  licensed under the **[Apache License 2.0](LICENSE)** (see also [NOTICE](NOTICE)).
- **The prebuilt `reolink-cli` binaries** on the
  [Releases](https://github.com/reolink/reolink-cli/releases) page are
  **proprietary**, governed by the EULA bundled in each release archive. The
  CLI source is not published here.
- **Third-party open-source components** bundled in the binaries are listed in
  `THIRD-PARTY-LICENSES.txt` inside each release archive.
