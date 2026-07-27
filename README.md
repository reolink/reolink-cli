<div align="center">

<img src="docs/banner.svg" alt="Reolink CLI" width="320">

**A local-first command-line tool for operating Reolink cameras — JSON by default, with a built-in MCP server and a cross-agent skill so AI agents drive the same core.**

![version](https://img.shields.io/badge/version-0.10.0-blue)
![platform](https://img.shields.io/badge/platform-macOS%20·%20Linux%20·%20Windows-lightgrey)
![build](https://img.shields.io/badge/build-external%20·%20LAN--only-green)

</div>

---

Operate Reolink IP cameras from the command line over your **local network** —
JSON out by default, so everything pipes into `jq` or a script. The bundled MCP
server and agent skill drive the same runtime, so an AI agent can do it in plain
language.

```console
$ reolink-cli --camera front-door info | jq '{model, firmware, name}'
{
  "model": "Reolink Video Doorbell",
  "firmware": "v3.0.0.6696_26062799",
  "name": "Front Door"
}
```

## Highlights

- 🔍 **Discovery** — LAN broadcast, plus bulk `device import`
- 🎥 **Live media** — `preview play`, file/stdout capture, batch capture, JPEG snapshot
- 🕹️ **PTZ** — pan/tilt/zoom, presets, patrol, guard, autotrack, real timed jog
- 💡 **Lights** — IR, spotlight (with native **blink**), white-LED, status LED
- 🧠 **Detection** — motion + AI (person / vehicle / dog_cat / package)
- 📼 **Recording & storage** — schedule, SD/HDD status, VOD search & download
- 🔔 **Events** — query/stream + a declarative rule engine (`events monitor`)
- 🗣️ **Two-way audio** — talkback / TTS straight to the camera speaker
- 🌐 **Stream URLs** — RTSP / RTMP / FLV for Frigate, Home Assistant, go2rtc, VLC
- 🤖 **AI-native** — built-in MCP stdio server + cross-agent operator skill
- 🧩 **Fleet-aware** — camera & tag selectors, local session daemon for a fast control plane

## Install

### AI agents

**Claude Code — no Node required.** Install the plugin from inside Claude Code:

```text
/plugin marketplace add reolink/reolink-cli
/plugin install reolink-cli@reolink-cli
```

The binary for your platform is fetched automatically the first time you ask
about a camera. Then just talk to your agent: *“show me the front door camera”*,
*“point the back-yard camera left”*, *“blink the porch spotlight 3 times”*.

**Other agents (Codex / Cursor / Gemini / Copilot / OpenCode / 70+) — requires
[Node.js](https://nodejs.org).** The cross-agent `skills` installer places the
skill into each agent’s own directory:

```bash
npx skills@latest add reolink/reolink-cli
```

Pick `reolink-cli` and the agents to install it into; the binary is fetched on
first use, exactly as above.

### Command line only — no Node required

One line — detects your platform, installs `reolink-cli` + `reolink-gateway` to
`~/.local/bin`, and initializes config:

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh | sh
```

```powershell
# Windows (PowerShell)
iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 | iex
```

Already installed? Upgrade in place with `reolink-cli self-update --yes`.

<details>
<summary>Prefer a downloadable archive?</summary>

Grab the archive for your platform from the
[latest Release](https://github.com/reolink/reolink-cli/releases/latest),
extract, and run the bundled installer:

```bash
tar -xzf reolink-cli-*-external-darwin-arm64.tar.gz && cd reolink-cli-* && ./install.sh
# Windows: extract the .zip and run .\install.ps1
```

The archive is self-contained: binaries + the skill/plugin + installer +
`THIRD-PARTY-LICENSES.txt`, and each has a `SHA256SUMS` entry on the Release for
verification.

</details>

<details>
<summary>Uninstall</summary>

```bash
reolink-cli setup --uninstall --purge && npx skills remove reolink-cli
```

Claude Code users: also run `/plugin uninstall reolink-cli` to clean the marketplace entry.

</details>

## Quick start

```bash
# Write the config and registry templates. Both land in your OS config
# directory and are created owner-only (0600).
reolink-cli config init

# Start the local gateway — most control commands route through it
reolink-cli gateway start --addr 127.0.0.1:9000 &
export REOLINK_GATEWAY_ADDR=127.0.0.1:9000

# Register your first camera. Pick a name of your own: `config init` writes
# placeholder entries (front-door, garage, lab-v30) to show the file format,
# and `device add` refuses to overwrite an existing one.
reolink-cli device add porch --host 192.168.1.41 --user admin --tags outdoor,entry --password-stdin

reolink-cli --camera porch login
reolink-cli --camera porch info
reolink-cli --camera porch snapshot --file ./porch.jpg
```

The placeholder entries are examples, not cameras. Remove them once you have
registered your own: `reolink-cli device remove front-door`.

Bulk-import discovered devices (credentials via `REOLINK_PASSWORD`, never
plaintext `--password` on the command line):

```bash
export REOLINK_PASSWORD='<device-password>'
reolink-cli --user admin device import
unset REOLINK_PASSWORD
```

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

## AI agents & MCP

`reolink-cli` is built to be driven by AI agents. There are two ways in — a
natural-language **skill** and a structured **MCP server** — both reusing the
exact same core runtime as the CLI.

### 1. Operator skill — talk to your cameras

`npx skills@latest add reolink/reolink-cli` installs the `reolink-cli` skill
into whichever agents you use. The skill teaches the agent the full command
surface and the safety rules, so you just say what you want:

> *“is the front door camera online?”*
> *“point the driveway cam to preset 2, then take a snapshot”*
> *“let me know if anyone shows up at the door tonight”*

The agent maps intent to the right `reolink-cli` invocation, chains multi-step
flows, and **never guesses device state** — it only reports what a command
actually returned.

### 2. MCP server — structured tools

For agents that prefer typed tool calls, or tight automation loops:

```bash
reolink-cli mcp-server
```

JSON-RPC 2.0 over stdio, reusing the same core runtime. Wire it into Claude Code:

```json
"mcpServers": {
  "reolink-cli": {
    "command": "reolink-cli",
    "args": ["mcp-server"],
    "env": { "REOLINK_GATEWAY_ADDR": "127.0.0.1:9000" }
  }
}
```

The gateway must be running separately — the MCP server routes through it,
exactly as the CLI does.

## Platform support

Prebuilt binaries are published on each [Release](https://github.com/reolink/reolink-cli/releases):

- macOS arm64 (Apple Silicon)
- Linux x86_64
- Linux arm64
- Windows x86_64

`self-update` covers macOS and Linux. On Windows it exits with the download
link instead: the archive is a `.zip`, and a running `.exe` cannot be replaced
in place — upgrade by extracting the new archive and running `install.ps1`.

`preview play` expects `ffplay` on `PATH` (or pass `--player`, or set
`REOLINK_PLAYER`).

> Best supported on current Reolink IP cameras and NVRs over the LAN. Support
> for some newer models may be partial — check a specific command with
> `reolink-cli --camera <name> device inventory --capabilities`.

## Responsible use

This tool controls cameras and reads their recordings. Use it only on devices
you own or are authorised to administer.

- **Authorised devices only.** Discovery broadcasts on your LAN and login
  attempts against cameras you do not control are unauthorised access in most
  jurisdictions, regardless of intent.
- **Not a scanner.** `discover` is a UDP broadcast for locating your own
  cameras. Do not use it, or `ping`, to sweep networks you were not asked to
  work on.
- **The footage is someone's home.** Snapshots, recordings and the event
  history this tool writes to disk are personal data. Protect them the way you
  would protect the camera's own storage, and delete what you no longer need.

## Security

- **The gateway binds `127.0.0.1` by default** and refuses browser
  cross-origin requests. Passing `--addr 0.0.0.0:9000` exposes camera control
  to everyone on your LAN — do it deliberately, never by default.
- **This is a LAN-only build.** It reaches cameras over the local network
  (`--host <ip>`); remote access via Reolink's P2P relay is not included.
  Confirm with `reolink-cli --version` → `(external · LAN-only)`.
- **Report vulnerabilities privately** — see [SECURITY.md](SECURITY.md).

### Safe credential handling

- **Never pass `--password` on the command line.** It is visible to every other
  user via `ps` and lands in your shell history. Use `--password-stdin`, the
  `REOLINK_PASSWORD` environment variable, or register the camera once with
  `device add` and refer to it by name.
- **Stored passwords are encrypted at rest.** Camera passwords in
  `aliases.toml` are AES-256-GCM ciphertext (`RLENC1:…`), decrypted with a key
  in `credentials.key` beside it. An existing plaintext config is converted
  automatically the first time you run any command — you do not have to do
  anything. Both files are owner-only (`0600`), and the CLI refuses to read them
  if they are group- or world-readable. Do not relax that, and do not commit
  them anywhere.
- **Back up `credentials.key` together with `aliases.toml`.** Neither is usable
  without the other. If the key is lost the passwords cannot be recovered and
  must be re-entered with `device update <camera> --password-stdin`.
- **This protects the file, not the account.** The key sits next to the data, so
  anything that can read both can decrypt. What it removes is the casual
  exposure: a copied config, a backup, or an AI agent reading the file no longer
  hands over every camera credential in the clear.
- **Credentials never go in a URL.** Gateway media endpoints take a session
  token instead, which expires after 300 s of inactivity.
- **`stream url --with-auth` is the one exception** — it embeds
  `user:password@` in the printed RTSP/RTMP/FLV URL because players need it
  there. That URL is a live credential: do not paste it into a ticket, a chat,
  or a dashboard others can read. Without the flag, no credentials are printed.
- **Redact before sharing output.** Command output can contain UIDs, serial
  numbers, LAN addresses and stream URLs.

## Installers

> **While this repository is private**, the one-line installers and the release
> download URLs return 404 for anonymous callers — GitHub does not serve private
> content that way. Until it is made public, export a `GITHUB_TOKEN` with access
> to this repository before running an installer, or fetch the archive with
> `gh release download`.


`install.sh` and `install.ps1` fetch and run executables, so here is exactly
what they do:

- resolve the latest release from the GitHub API, then download that release's
  asset from `github.com` — no other host is contacted
- **verify the download against the release's `SHA256SUMS` and abort on any
  mismatch**, missing entry, or missing checksum file
- install two binaries to `~/.local/bin` (`%USERPROFILE%\.local\bin` on
  Windows) — **no `sudo`, no system directories, no services**
- stop a running `reolink-gateway` **only if it runs from that same prefix**,
  so another installation is never touched
- overwrite previous binaries in that prefix; nothing else on disk is modified
- add the prefix to your user `PATH` if it is missing (Windows)

They are ordinary text files: read them before running, as you should with any
install script. To skip them entirely, download an archive from the
[Releases](https://github.com/reolink/reolink-cli/releases) page, verify it with
`shasum -a 256 -c SHA256SUMS`, and copy the two binaries wherever you like.

## Trademarks

"Reolink" and the Reolink logo are trademarks of Reolink Innovation Limited.
The Apache 2.0 licence covers the code and docs in this repository — it grants
no rights to the Reolink name or logo. If you publish a fork, rename it and
remove the marks; see [TRADEMARKS.md](TRADEMARKS.md).

## License

- **This repository** — the skill, plugin manifests, and docs (text) — is
  licensed under the **[Apache License 2.0](LICENSE)** (see also [NOTICE](NOTICE)).
- **The prebuilt `reolink-cli` binaries** on the
  [Releases](https://github.com/reolink/reolink-cli/releases) page are
  **proprietary**, governed by the EULA bundled in each release archive. The
  underlying CLI source is not published here.
- **Third-party open-source components** bundled in the binaries are listed in
  `THIRD-PARTY-LICENSES.txt` inside each release archive.
