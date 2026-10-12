# Reolink CLI Operator Guide

This guide is for people who use `reolink-cli` from a terminal. It covers
installation, the first camera, everyday operations, scripting, and recovery.
The public release connects to cameras on the local network. A camera may be
connected directly or through a local Home Hub or NVR.

For a command-oriented index, see the [CLI Reference](cli-reference.md). For
feature details, use the topic references under
[`skills/reolink-cli/references`](../skills/reolink-cli/references/index.md).
The installed binary remains authoritative: run `reolink-cli --help` and the
relevant command help when a release differs from this guide.

## Contents

- [Install and check the tools](#install-and-check-the-tools)
- [Connect the first camera](#connect-the-first-camera)
- [Command and credential rules](#command-and-credential-rules)
- [Common operations](#common-operations)
- [Hub and NVR child cameras](#hub-and-nvr-child-cameras)
- [Doorbell power mode](#doorbell-power-mode)
- [Firmware upgrades](#firmware-upgrades)
- [Multiple cameras and batch output](#multiple-cameras-and-batch-output)
- [JSON output and scripts](#json-output-and-scripts)
- [Troubleshooting](#troubleshooting)
- [Upgrade, uninstall, and data maintenance](#upgrade-uninstall-and-data-maintenance)
- [Command map](#command-map)

## Install and check the tools

The release package contains `reolink-cli` and `reolink-gateway`. The gateway
keeps local sessions and is required for device operations. The agent skill and
MCP integration are optional; direct terminal use does not need either one.

### macOS and Linux

Use the installer published with the repository. It selects the platform
archive, verifies its checksum, installs both binaries under `~/.local/bin`,
and initializes the local configuration:

```bash
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh | sh
reolink-cli --version
reolink-gateway --version
```

If piping a download is not allowed in your environment, download the script,
inspect it, and run it:

```bash
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh \
  -o /tmp/reolink-install.sh
sh /tmp/reolink-install.sh
```

The installer fails closed when a checksum is missing or does not match. Retry
once for a truncated download. If the checksum still fails, stop and report
the release and platform instead of bypassing verification.

### Windows PowerShell

Run this command from PowerShell or Command Prompt:

```text
powershell -NoProfile -Command "iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 -UseBasicParsing | iex"
```

The default directory is `%USERPROFILE%\\.local\\bin`. Open a new terminal and
check both binaries:

```powershell
reolink-cli --version
reolink-gateway --version
```

### Check the installation

```bash
reolink-cli --version
reolink-cli features
reolink-cli doctor
```

`features` reports the installed command surface and local paths. `doctor`
checks the binaries, configuration, registry, permissions, and gateway
reachability. Warnings before the first setup are expected; run it again after
the gateway and camera are configured.

## Connect the first camera

The following sequence registers a camera and performs a read-only check. The
address `192.0.2.10` is reserved for documentation; replace it with the actual
camera address and service port.

### 1. Initialize local files

```bash
reolink-cli config init
reolink-cli device list
```

The command creates a configuration file and a camera registry. Existing files
are preserved unless `--force` is supplied. Do not use `--force` on a working
installation unless replacing the templates is intentional.

### 2. Discover and register the camera

When the computer and camera share a LAN, start with discovery:

```bash
reolink-cli discover
```

Register the address returned by discovery:

```bash
reolink-cli device add porch --host 192.0.2.10:9000 --user admin \
  --tags outdoor,entry
```

The command prompts for the camera's local account password. A cloud account
password is not necessarily the same password. Registration saves the target;
it does not test login. Use `device update` when the alias already exists.

If discovery is empty, check the subnet, firewall, camera address, and whether
the camera is asleep. You can register a known local address directly.

### 3. Start the local gateway

In one terminal, keep the gateway running:

```bash
reolink-cli gateway start --addr localhost:9000
```

The gateway address belongs to the computer. It is separate from the camera
address even when both use port 9000. Add `--open` to open the local dashboard.

### 4. Verify from a second terminal

```bash
reolink-cli gateway status
reolink-cli --camera porch device resolve
reolink-cli --camera porch ping
reolink-cli --camera porch login
reolink-cli --camera porch info
reolink-cli --camera porch capabilities
```

The checks have different meanings:

| Check | Confirms |
|---|---|
| `gateway status` | The local gateway accepts a TCP connection |
| `device resolve` | Alias, address, channel, and password presence |
| `ping` | The selected target is reachable |
| `login` | The camera accepted the account and password |
| `info` | The returned model and firmware identify the target |
| `capabilities` | Features reported by this camera |

A successful ping does not prove that login succeeded. For a read-only
end-to-end diagnostic, use:

```bash
reolink-cli --camera porch device analyze --capabilities
```

## Command and credential rules

The general form is:

```text
reolink-cli [global options] <command group> <operation> [arguments]
```

- Put `--camera <alias>` before the command. The alias is the safest selector
  for a registered target.
- Use `--host <address:port>` for a one-shot local connection.
- Use `--channel <number>` when selecting a child channel on a Hub or NVR.
- Use `--gateway-addr <host:port>` when the gateway is not on its default
  address.
- Names are case-sensitive. Quote names that contain spaces.
- `--help` is read-only and can be used at any command level.

Do not put a real password in shell history or process arguments. Prefer the
registry prompt or stdin:

```bash
printf '%s' "$DEVICE_PASSWORD" | reolink-cli device add porch \
  --host 192.0.2.10:9000 --user admin --password-stdin
unset DEVICE_PASSWORD
```

For a one-shot command:

```bash
printf '%s' "$DEVICE_PASSWORD" | reolink-cli --host 192.0.2.10:9000 \
  --user admin --password-stdin info
unset DEVICE_PASSWORD
```

The CLI encrypts stored passwords in the registry. Back up the registry and
its adjacent `credentials.key` together. Treat both files as sensitive. On
Unix, they should be owner-readable only. A missing or mismatched key is a
key-file problem, not a bad camera password.

Before a write, read the current value and confirm the target. After a write,
read it again when the command reference says that read-back is supported. A
successful response means the device accepted the request; it does not always
prove that a physical action was observed.

## Common operations

The examples below assume the alias `porch` is registered and the gateway is
running.

### Inspect and change settings

```bash
reolink-cli --camera porch info
reolink-cli --camera porch capabilities
reolink-cli --camera porch config get device-name
reolink-cli --camera porch config set device-name \
  --value '{"deviceName":"Porch"}'
reolink-cli --camera porch config get device-name
```

Use dedicated commands for image, audio, detection, recording, and lighting
settings. Put complex JSON in a file and pass `--value-file` when shell quoting
becomes difficult.

### Snapshots and live video

```bash
reolink-cli --camera porch snapshot --file ./porch.jpg
reolink-cli --camera porch preview play --stream sub
reolink-cli --camera porch preview capture --stream sub --file ./porch.bin --packets 128
```

`preview play` needs `ffplay`. Start with the substream, then choose `main` for
higher resolution. A capture file contains preview data, not an MP4.

To integrate with VLC, Frigate, or another video application:

```bash
reolink-cli --camera porch stream url --kind rtsp --stream sub
```

Credentials are omitted by default. Use `--with-auth` only when a credential-
bearing URL is needed, and never paste that URL into a public issue.

### PTZ and presets

```bash
reolink-cli --camera porch ptz preset list
reolink-cli --camera porch ptz move left --speed 16 --duration-ms 500
reolink-cli --camera porch ptz stop
reolink-cli --camera porch ptz preset goto 1
```

Use a duration for a timed move. Stop an open-ended move explicitly. A fixed
lens camera may not implement PTZ; check `capabilities` first.

### Lights, audio, and talkback

```bash
reolink-cli --camera porch light ir get
reolink-cli --camera porch light ir set --state auto
reolink-cli --camera porch light spotlight blink --count 3 --on-ms 500 --off-ms 500
reolink-cli --camera porch audio config get
reolink-cli --camera porch audio siren play --times 1 --wait
```

Siren and talkback make sound at the camera. Confirm the target and situation
before running them. For talkback, provide raw 16 kHz mono signed 16-bit
little-endian PCM; convert an audio file first with `ffmpeg`.

### Image, encoder, OSD, and privacy mask

```bash
reolink-cli --camera porch image flip get
reolink-cli --camera porch image flip set --mirror
reolink-cli --camera porch encode get
reolink-cli --camera porch osd get
reolink-cli --camera porch privacy mask get
```

Read the current privacy mask before editing it. Disabling a mask exposes the
previously hidden area in live video and recordings.

### Detection and mobile push

```bash
reolink-cli --camera porch detect motion get
reolink-cli --camera porch detect motion set --enable --sensitivity 20
reolink-cli --camera porch notify push get
reolink-cli --camera porch notify push set --interval 30
reolink-cli --camera porch notify push get
```

The push command stores device settings. It does not send a test notification.
Enable push in the mobile app, enable a detection rule, then trigger the rule
to test delivery. Omitted options keep their current values.

### Recordings and events

```bash
reolink-cli --camera porch record schedule get
reolink-cli --camera porch storage status
reolink-cli --camera porch vod search --since 1d
reolink-cli --camera porch events query --last 20
```

Read a recording schedule before changing it. The event stream is NDJSON; do
not send it to a parser that expects one JSON document. For event-triggered
actions, use the declarative `events monitor` rule files described in the
event-monitor reference.

## Hub and NVR child cameras

An NVR or Home Hub exposes multiple camera channels through one local address.
Register the parent and expand it into child aliases:

```bash
reolink-cli device add lobby --host 192.0.2.20:9000 --user admin
reolink-cli device expand lobby --yes
reolink-cli device list
reolink-cli --camera lobby-ch0 info
```

Use the child alias for per-camera operations. Use `--tag lobby` for a batch
operation over all expanded children. Device-global operations, such as a
parent reboot, affect the whole Hub or NVR; confirm that scope first.

## Doorbell power mode

Supported wired-capable doorbells expose a `power-mode` configuration path.
Keep the gateway running and check the current value before switching:

```bash
reolink-cli --camera porch config get power-mode
reolink-cli --camera porch config set power-mode \
  --value '{"mode":"adapter","dryRun":1}'
reolink-cli --camera porch config set power-mode \
  --value '{"mode":"adapter"}'
reolink-cli --camera porch config get power-mode
```

Use `"mode":"battery"` to return to battery operation. `dryRun: 1` checks
whether the switch can be accepted without changing the mode. After a real
switch, inspect the returned status and the follow-up readback. A request can
be accepted while the detected source is disconnected or too weak. Devices
that do not expose this path return an unsupported error; do not retry it.

## Firmware upgrades

Firmware changes are device-wide and can interrupt service. Confirm the model,
hardware revision, file provenance, and target alias before starting:

```bash
reolink-cli --camera porch info
reolink-cli --camera porch capabilities
reolink-cli --camera porch system upgrade ./firmware.pak
```

Keep the gateway process running until the command finishes. The camera may
drop the connection and need several minutes to restart. Re-check `info` after
the reboot. Never use a firmware file for another model or hardware revision.

## Multiple cameras and batch output

Use tags or an explicit camera list for a read-only batch operation:

```bash
reolink-cli --tag outdoor info
reolink-cli --cameras porch,garage capabilities
```

Every batch result has its own `ok` value. A single failed target can coexist
with successful targets, so inspect `summary.failed` and each item in
`results[]`. Keep the same selector throughout a workflow.

## JSON output and scripts

JSON is the default output. A normal result has this shape:

```json
{"ok":true,"command":"info","data":{"model":"Example Camera"}}
```

Use `.data` for a single target and `.results[]` for a batch. Check the exit
code as well as the JSON value:

```bash
if reolink-cli --camera porch info >info.json 2>info.error; then
  jq '.data' info.json
else
  cat info.error >&2
fi
```

`--output text` is intended for people, not stable automation. Media commands
that write to stdout and event streams are exceptions to the normal JSON
envelope.

## Troubleshooting

Use this order to isolate a failure:

```bash
reolink-cli --version
reolink-cli doctor
reolink-cli gateway status
reolink-cli --camera porch device resolve
reolink-cli --camera porch login
reolink-cli --camera porch info
```

| Symptom | Next check |
|---|---|
| Binary not found | Check the install directory and `PATH`; install both binaries |
| Gateway connection refused | Start the gateway and use the same address in the CLI |
| Camera timeout | Check local address, port, power, subnet, and firewall |
| Login rejected | Check the camera-local account and lockout state |
| Stored password cannot be decrypted | Restore the matching `credentials.key` or re-enter the password |
| Hub child is unavailable | Confirm the channel and wake the child, then retry |
| Unsupported operation | Check `capabilities`, model, and firmware |
| Invalid parameters | Inspect the current value and command help before retrying |
| No video player | Install `ffplay` and start with the substream |
| Empty recording or event query | Check time range, timezone, storage, and recording rules |

When reporting a defect, include the CLI and gateway versions, exact command,
failing phase, raw error code, and a redacted result. Do not attach passwords,
keys, credential-bearing URLs, or the complete configuration directory.

## Upgrade, uninstall, and data maintenance

### Update the local software

On macOS and Linux:

```bash
reolink-cli self-update --yes
reolink-cli --version
reolink-gateway --version
```

On Windows, download the new archive and run the installer again because a
running executable cannot replace itself. Restart the gateway after updating,
then run `doctor` and a read-only `info` check.

### Cache and device logs

```bash
reolink-cli cache status
reolink-cli cache clean --older-than 7d
```

Cache cleanup previews by default. Add `--apply` only after reviewing the
candidate list. Device log commands are available on models that implement
them; save downloads to an explicit path and redact before sharing.

### Uninstall

The default uninstall removes installed binaries and keeps user data:

```bash
reolink-cli setup --uninstall
```

Add `--purge` only when deleting the registry, credentials, cache, and state is
intentional. Headless runs also require `--no-interactive`.

## Command map

| Goal | Command entry points |
|---|---|
| Initialize local files | `config init`, `init` |
| Discover and manage cameras | `discover`, `device list/show/add/update/remove/import/expand/resolve/inventory/analyze` |
| Check connectivity and identity | `ping`, `login`, `info`, `capabilities` |
| Device settings and power mode | `config get/set` |
| Live video and snapshots | `preview`, `snapshot`, `stream url` |
| PTZ and tracking | `ptz` |
| Lights and audio | `light`, `audio` |
| Image, encoder, mask, and OSD | `image`, `encode`, `privacy`, `osd` |
| Motion and AI detection | `detect` |
| Mobile push | `notify push` |
| Recordings and storage | `record`, `storage`, `vod` |
| Events and automation | `events` |
| Device logs | `log` |
| Reboot and firmware | `system` |
| Local gateway | `gateway` |
| Diagnostics and maintenance | `doctor`, `features`, `status`, `benchmark`, `cache`, `self-update`, `setup` |
| Shell completion | `completions` |
| Optional agent integration | `plugin refresh`, `mcp-server` |

Examples:

```bash
reolink-cli device --help
reolink-cli system upgrade --help
reolink-cli notify push set --help
reolink-cli completions powershell
```
