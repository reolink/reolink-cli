# Reolink CLI Operator Guide

This guide is for people who use `reolink-cli` directly from a terminal. It
covers installation, the first device, daily operations, scripting, and
troubleshooting. You do not need to install an AI skill or understand the
camera protocol first. For every flag and every command, see the [CLI command
reference](cli-reference.md) and the command's `--help` output.

The command surface varies by camera model and firmware. A command existing in
the CLI does not mean that every camera implements it. Check `--version`,
`features`, and `capabilities` before planning a device change.

## Contents

- [Install and check the tools](#install-and-check-the-tools)
- [Connect the first camera](#connect-the-first-camera)
- [Command and configuration rules](#command-and-configuration-rules)
- [Common operations](#common-operations)
- [Hub and NVR child cameras](#hub-and-nvr-child-cameras)
- [Doorbell power mode](#doorbell-power-mode)
- [Firmware upgrades](#firmware-upgrades)
- [Multiple cameras](#multiple-cameras)
- [JSON output and scripts](#json-output-and-scripts)
- [Troubleshooting](#troubleshooting)
- [Upgrade, uninstall, and data maintenance](#upgrade-uninstall-and-data-maintenance)
- [Command map](#command-map)

## Install and check the tools

### What the names mean

| Name | Purpose | Required for direct CLI use |
|---|---|---|
| `reolink-cli` | Accepts terminal commands and prints results | Yes |
| `reolink-gateway` | Keeps local device connections and serves the web dashboard | Yes for device operations; shipped with the CLI package |
| Skill | Teaches an AI assistant how to use the CLI | Optional |
| MCP | Exposes selected operations as structured AI tools | Optional |
| Plugin | Packages skills and client configuration | Optional |

The normal flow is: you enter a CLI command, the local gateway sends the
operation to the camera. Local commands such as `device list`, `device add`,
and `config init` do not need a camera connection. Device commands such as
`info`, PTZ, and snapshots require a running gateway.

### Choose a release package

Download a package matching your operating system and CPU from the project's
[Releases](https://github.com/reolink/reolink-cli/releases), or from the channel
provided by your administrator. Verify the downloaded archive with the checksum
published for that release.

| System | Typical asset suffix |
|---|---|
| Apple Silicon Mac | `darwin-arm64.tar.gz` |
| Linux x86_64 | `linux-x86_64.tar.gz` |
| Linux ARM64 | `linux-arm64.tar.gz` |
| Alpine / musl Linux | The matching `linux-*-musl.tar.gz` asset |
| Windows x64 | `windows-x86_64.zip` |

Use the exact asset name shown on the release page. Some assets include
`external`: those builds are **LAN-only** and connect by local IP or hostname.
Knowing a UID does not make a LAN-only binary able to reach a remote camera.

### macOS and Linux

Replace every `<...>` placeholder below before running it. Extract the archive
and run the installer from the directory containing `install.sh`, `bin/`, and
`plugins/`:

```bash
tar -xzf '<downloaded-archive>.tar.gz'
cd '<extracted-directory>'
./install.sh --binaries-only
```

This installs the CLI and gateway and skips AI-agent installation; Node.js is
not required. The default binary directory is `~/.local/bin`. Open a new
terminal after installation. If the command is still not found, test it in the
current shell with:

```bash
export PATH="$HOME/.local/bin:$PATH"
reolink-cli --version
reolink-gateway --version
```

Make the `PATH` change permanent as instructed by the installer.

### Windows PowerShell

```powershell
Expand-Archive '<downloaded-archive>.zip' -DestinationPath .
Set-Location '<extracted-directory>'
.\install.ps1 -BinariesOnly
```

The default binary directory is `%USERPROFILE%\.local\bin`. Open a new
PowerShell window and check the versions. To test the current window first:

```powershell
$env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
reolink-cli --version
reolink-gateway --version
```

If the execution policy blocks the script, run it for this process only after
you have verified the package source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -BinariesOnly
```

### Check the installation

```bash
reolink-cli --version
reolink-cli --output text features
reolink-cli --output text doctor
```

`features` reports this build's capabilities and its config, cache, and state
directories. `doctor` checks the binary, configuration, registry, and gateway.
Warnings before the first setup or gateway start are expected; repeat the check
after completing the next section.

Live playback also needs `ffplay` from FFmpeg. `jq` is only needed when you want
to filter JSON in a shell. Ordinary control commands and JPEG snapshots need
neither dependency.

## Connect the first camera

This section only registers and reads the camera; it does not change camera
settings. `192.0.2.10` is a documentation-only address and must be replaced
with the camera's address. `porch` is a local alias and can be renamed.

### 1. Initialize local configuration

```bash
reolink-cli config init
reolink-cli device list
```

The command creates `config.toml` and `aliases.toml`; existing files are skipped
unless `--force` is supplied. The result contains the actual paths used.

The template includes disabled `front-door` and `garage` examples. They are not
discovered devices and their names are still reserved in the registry. This
guide uses `porch` to avoid that collision. Do not run `config init --force` on
an existing installation unless you intend to overwrite both templates.

### 2. Find and register the camera

When the computer and camera are on the same LAN, start with:

```bash
reolink-cli discover
```

Register the address returned by discovery:

```bash
reolink-cli device add porch --host 192.0.2.10:9000 --user admin --tags outdoor,entry
```

Enter the **camera's local account** password when prompted. It may be different
from the Reolink cloud-account password. `:9000` is the usual device service
port; use the actual port if the camera was configured differently.

`device add` saves connection information but does not test login. If the alias
already exists, use `device update` instead of adding it again.

If this build supports P2P/UID, you can register a UID instead of an address:

```bash
reolink-cli device add remote-door --uid '<device-uid>' --user admin
```

LAN broadcast discovery normally cannot cross subnets or VLANs. A device that
does not appear in discovery is not necessarily offline. A battery camera paired
to a Hub may have no independent address; register it through the Hub as
described in [Hub and NVR child cameras](#hub-and-nvr-child-cameras).

### 3. Start the gateway

In one terminal, run:

```bash
reolink-cli gateway start --addr 127.0.0.1:9000
```

Keep this terminal open. The command running without returning to a prompt is
normal; press `Ctrl-C` to stop it. Add `--open` to open the dashboard at
<http://127.0.0.1:9000/>.

`127.0.0.1:9000` is the **gateway address on the computer**. It is different
from the camera address such as `192.0.2.10:9000`; the same port number is not a
conflict. The address written by `config init` matches this default.

### 4. Verify in a second terminal

```bash
reolink-cli gateway status
reolink-cli --camera porch device resolve
reolink-cli --camera porch ping
reolink-cli --camera porch login
reolink-cli --camera porch info
reolink-cli --camera porch capabilities
```

| Check | What it confirms |
|---|---|
| `gateway status` | The gateway address accepts TCP; it does not log in to the camera |
| `device resolve` | The final address, user, channel, and password presence; no camera connection |
| `ping` | Connectivity to the selected target |
| `login` | The camera accepted the account and password |
| `info` | The returned model, hardware, and firmware identify the intended target |
| `capabilities` | Features reported by this camera; the payload varies by model |

Successful single-device commands normally return `"ok": true` with the
operation result in `data`. Failures return a non-zero exit code and an error.
A successful `ping` does not prove that login succeeded. For a read-only
end-to-end diagnostic, run:

```bash
reolink-cli --camera porch device analyze --capabilities
```

## Command and configuration rules

### How to read a command

```text
reolink-cli [target and global options] <command group> <operation> [arguments]
```

For example, `reolink-cli --camera porch light ir set --state auto` selects the
registered camera `porch` and sets its IR mode to automatic.

- `--camera porch` and `--alias porch` are equivalent; this guide uses `--camera`.
- Global options appear before the command in the examples. Most global options
  also work after the command, but using the shown order is clearer for
  `device add` and `device update`.
- Names are case-sensitive. Quote names containing spaces, for example
  `--camera 'Front Door'`.
- `<name>` means “replace this placeholder”. `[OPTIONS]` in help output means
  optional flags; do not type the brackets.
- `--help` is read-only and can be explored at every level:

```bash
reolink-cli --help
reolink-cli light --help
reolink-cli light ir set --help
```

The default protocol is the stable v20 surface. v30 is provisional and limited;
ordinary users should not add `--protocol` unless a release note or support
instruction explicitly asks for it.

### Where configuration lives

| System | Default config directory |
|---|---|
| Linux | `~/.config/reolink-cli/`, or `$XDG_CONFIG_HOME/reolink-cli/` |
| macOS | `~/Library/Application Support/reolink-cli/` |
| Windows | `%APPDATA%\reolink-cli\` |

Use the actual paths printed by `features`. `config.toml` stores defaults such as
the user, channel, and gateway address. `aliases.toml` stores the camera
registry. New writes use `[cameras.<name>]`; older `[aliases.<name>]` files are
still accepted.

For a selected camera, values usually resolve in this order:

1. command-line flags and their environment variables;
2. the selected camera entry;
3. defaults in `config.toml`.

An explicit command-line flag wins over an environment variable. Protocol choice
is explicit value, then the camera entry, then v20. If a command targets the
wrong camera, run `device resolve` and check for leftover `REOLINK_HOST`,
`REOLINK_UID`, or `REOLINK_CAMERA` variables.

You can keep separate profiles by specifying both files:

```bash
reolink-cli --config-file ./office/config.toml --cameras-file ./office/aliases.toml config init
reolink-cli --config-file ./office/config.toml --cameras-file ./office/aliases.toml --camera porch info
```

Use the same paths on subsequent commands. `--aliases-file` is the compatibility
name for `--cameras-file`; the file is a TOML registry, not a one-name-per-line
list.

### Passwords and backups

For interactive use, let `device add` prompt without echoing the password. For
scripts or CI, inject a secret into `DEVICE_PASSWORD` and pipe it through stdin:

```bash
printf '%s' "$DEVICE_PASSWORD" | reolink-cli device add porch \
  --host 192.0.2.10:9000 --user admin --password-stdin
unset DEVICE_PASSWORD
```

Update an existing stored password the same way:

```bash
printf '%s' "$DEVICE_PASSWORD" | reolink-cli device update porch --password-stdin
unset DEVICE_PASSWORD
```

In PowerShell, use `$env:DEVICE_PASSWORD | reolink-cli device update porch --password-stdin`,
then run `Remove-Item Env:DEVICE_PASSWORD`. The variable must be supplied by
your secret manager or shell; the CLI does not generate it.

For a one-shot command without a registry entry:

```bash
printf '%s' "$DEVICE_PASSWORD" | reolink-cli \
  --host 192.0.2.10:9000 --user admin --password-stdin info
```

Do not put a real password in `--password`, shell history, process arguments, or
an exported command that you intend to paste into a ticket. `--password-stdin`
is intended for a pipe. When used directly in a terminal it waits for EOF: on
macOS/Linux enter the password, press Enter, then `Ctrl-D`; on Windows use
`Ctrl-Z` followed by Enter. It is not a hidden prompt.

Passwords written by the CLI are encrypted in the registry. The key is
`credentials.key` beside that registry, including for a custom registry path.
Back up the registry, config, and matching key together. Treat the whole set as
sensitive: anyone who obtains both ciphertext and key can recover the password.
Hand-written plaintext is not encrypted merely because the file is TOML.

On Unix, the registry and key must be readable and writable only by the owner
(`0600`); files created by the CLI use that mode. Fix permissions using the
actual path in the error. On Windows, use the file's access controls.

### A safe pattern for changes

Read the current value, confirm the target and effect, write the change, then
read it again to verify. Only operations that explicitly document a dry run
support one; power mode has `dryRun`, and cache cleanup is a dry run by default.
Do not add `--dry-run` to an unrelated command.

An accepted request is not always proof that the device state changed. When no
read-back is available, verify with the camera, indicator, or app. After a write
failure, query the state before repeating the operation.

## Common operations

All examples below assume that `porch` is registered and the gateway is
running. Write operations take effect on the camera.

### Read and change configuration

```bash
reolink-cli --camera porch config get system-general
reolink-cli --camera porch config get network
reolink-cli --camera porch config get device-name
reolink-cli --camera porch config set device-name --value '{"deviceName":"Porch"}'
reolink-cli --camera porch config get device-name
```

`config init` changes files on the computer; `config get/set` changes camera
settings. Put complex JSON in a UTF-8 file and use `--value-file` if shell
quoting becomes difficult. `system-general` and `performance` are read-only.
See the [configuration reference](cli-reference.md#config-get--set--init) for
the supported paths.

### Save a snapshot

```bash
reolink-cli --camera porch snapshot --file ./porch.jpg
```

Check the reported path and byte count, then open the image. Supplying an
explicit `--file` avoids depending on a default output location.

### Play and capture live video

Start with the lower-bandwidth substream:

```bash
reolink-cli --camera porch preview play --stream sub
```

Use `--stream main` for a higher-resolution stream. `preview play` requires
`ffplay`; the CLI detects H.264 or H.265 when possible. Specify a player path if
it is not on `PATH`:

```powershell
reolink-cli --camera porch preview play --stream sub --player 'C:\ffmpeg\bin\ffplay.exe'
```

Capture a bounded amount of preview data:

```bash
reolink-cli --camera porch preview capture --stream sub --file ./porch.bin --packets 128
```

`--packets` counts preview packets, not frames or seconds. A `.bin` file is not
an MP4. To pipe raw bytes to a player, the example below assumes HEVC; use
`h264` when the camera reports H.264:

```bash
reolink-cli --camera porch preview capture --stream sub --file - --packets 1000000 \
  | ffplay -fflags nobuffer -flags low_delay -f hevc -
```

With `--file -`, stdout contains video bytes and cannot be passed to `jq`.
Prefer `preview play` on Windows because older PowerShell versions can corrupt
binary pipelines. Long preview sessions increase battery use.

### Print RTSP and other stream URLs

```bash
reolink-cli --camera porch stream url --kind rtsp --stream sub
```

Use the result with VLC, an NVR, or another video application. The device must
support and enable the requested service. A successful UID connection does not
make a private LAN RTSP address reachable from the public internet. Passwords
are omitted by default; `--with-auth` embeds one in the URL, so do not share
that URL in a ticket or chat.

### PTZ and presets

```bash
reolink-cli --camera porch ptz preset list
reolink-cli --camera porch ptz move left --speed 16 --duration-ms 500
reolink-cli --camera porch ptz stop
reolink-cli --camera porch ptz preset goto 1
```

The first move is a timed pulse. A move without a duration needs an explicit
stop. If the network drops, check that the camera stopped. Preset `1` must exist
before it can be selected; saving or deleting a preset changes camera settings.
Zoom, focus, patrol, guard, and autotrack have their own help pages. A fixed
lens camera may not implement them.

### Lights, audio, and talkback

Read, change, and read back the IR mode:

```bash
reolink-cli --camera porch light ir get
reolink-cli --camera porch light ir set --state auto
reolink-cli --camera porch light ir get
```

Supported cameras can flash the spotlight and finish with it off:

```bash
reolink-cli --camera porch light spotlight blink --count 3 --on-ms 500 --off-ms 500
```

Use `light spotlight set --enable` or `--disable` for a persistent manual state.
Do not rely on the deprecated duration behavior for a guaranteed auto-off.
Read and change speaker volume as follows:

```bash
reolink-cli --camera porch audio config get
reolink-cli --camera porch audio config set --volume 40
reolink-cli --camera porch audio config get
```

Talkback input must be raw **16 kHz, mono, signed 16-bit little-endian PCM**;
an MP3 file cannot be passed as PCM directly:

```bash
ffmpeg -i greeting.mp3 -f s16le -ar 16000 -ac 1 greeting.pcm
reolink-cli --camera porch audio talk --file ./greeting.pcm --sample-rate 16000
```

Talkback sends sound through the camera. Confirm the target and situation before
running it. The same applies to the siren:

```bash
reolink-cli --camera porch audio siren enable get
reolink-cli --camera porch audio siren play --times 1 --wait
```

The siren command can be accepted without proving that the camera made an audible
sound. Check `speakerVolume` in the response first; on Hub children, the device-
wide siren switch and the selected channel switch must both be enabled. Use
`audio siren stop` if a one-shot sound must be stopped early. Quick replies and
other audio operations are listed by `audio --help`.

### Image, encoder, OSD, and privacy mask

```bash
reolink-cli --camera porch image flip get
reolink-cli --camera porch image flip set --mirror
reolink-cli --camera porch image flip get
reolink-cli --camera porch encode get
reolink-cli --camera porch encode capability
reolink-cli --camera porch osd get
reolink-cli --camera porch privacy mask get
```

`image flip` changes orientation, `image tune` changes image parameters,
`encode` changes video encoding, `osd` changes on-screen text, and `privacy
mask` changes masked regions. Read the supported encoder combinations before
writing a resolution, frame rate, or bit rate. Read a privacy mask before editing
it; disabling the mask exposes regions that were previously hidden in live video
and recordings:

```bash
reolink-cli --camera porch privacy mask get
reolink-cli --camera porch privacy mask set --enable
reolink-cli --camera porch privacy mask get
```

### Detection and mobile push

Motion sensitivity is **1–50**:

```bash
reolink-cli --camera porch detect motion get
reolink-cli --camera porch detect motion set --enable --sensitivity 20
reolink-cli --camera porch detect motion get
```

AI person sensitivity is a separate setting with a **0–100** range:

```bash
reolink-cli --camera porch detect ai get --type person
reolink-cli --camera porch detect ai set --type person --sensitivity 60
reolink-cli --camera porch detect ai get --type person
```

Not every camera supports every AI type. Mobile push settings are separate:

```bash
reolink-cli --camera porch notify push get
reolink-cli --camera porch notify push set --interval 30
reolink-cli --camera porch notify push get
```

#### First-time push setup

`notify push` stores the camera's mobile-app notification settings. It does not
send a test notification. To verify the complete path, do these steps in order:

1. In the Reolink app, enable push notifications for this camera and accept any
   privacy agreement shown there.
2. Make sure the gateway is running and use the registered camera alias, for
   example `porch`.
3. Enable at least one detection rule. For a simple motion test:

   ```bash
   reolink-cli --camera porch detect motion set --enable --sensitivity 20
   ```

4. Read the current push settings before changing them:

   ```bash
   reolink-cli --camera porch notify push get
   ```

5. Change only the setting you need, then read it back:

   ```bash
   # 30-second cooldown; keep the current format and consent choice
   reolink-cli --camera porch notify push set --interval 30
   reolink-cli --camera porch notify push get
   ```

6. Trigger the enabled detection in front of the camera and check the phone.
   A saved setting confirms that the camera accepted the value; it does not
   confirm that the app, phone permissions, network, and detection trigger are
   working.

Choose the notification format explicitly when needed:

| Command | Result |
|---|---|
| `notify push set` without `--rich` | Keep the current format |
| `notify push set --rich 0` | Text only; push remains enabled |
| `notify push set --rich 1` | Attach a camera image, if supported |
| `notify push set --rich 2` | Attach an animated GIF, if supported |

`--interval` is the cooldown between app alarm notifications, in seconds. The
device decides which values it accepts. `--consent 1` records that the user has
accepted Reolink's privacy agreement; never set it automatically. See the
[push reference](cli-reference.md#notify-push-get--set) for response fields and
the [troubleshooting guide](#troubleshooting) if a real trigger still produces
no notification.

### Recordings, storage, and downloads

```bash
reolink-cli --camera porch storage status
reolink-cli --camera porch record config get
reolink-cli --camera porch record schedule get
reolink-cli --camera porch vod search --since 2h --limit 20
```

For NVRs whose ordinary files report `recordType: none`, query the separate
alarm-video index when supported:

```bash
reolink-cli --camera nvr --channel 5 vod alarms --from 2026-10-29T00:00:00 --to 2026-10-29T23:59:59 --type people --limit 100
```

Use the device's local wall clock for this window. `--since` uses the computer's
local clock; use explicit times when their time zones differ. Results contain
`alarmType`, `fileName`, `fileId`, and alarm start/end times. These are detected
intervals, which can share one continuous recording file. `source` is
`alarm-video-index`; this query does not rewrite ordinary file classifications.
`scanned` counts examined intervals before local filtering, and `truncated`
means the limit stopped the search. Agents can use the read-only MCP tool
`camera_vod_alarms` with `channel`, `from`, `to`, and optional `recordType`.

Storage status, recording enabled state, recording schedule, and existing files
are separate things. `record schedule` is a battery-device-specific surface,
not a universal NVR weekly-plan editor. The CLI reads the existing schedule and
preserves fields you omit. If you provide plan-time flags, they replace the
plan-time list with the plan you specify. For a simple daily recording window:

```bash
reolink-cli --camera porch record schedule get
reolink-cli --camera porch record schedule set --enable --plan-type daily \
  --start-hour 0 --start-min 0 --end-hour 23 --end-min 59
reolink-cli --camera porch record schedule get
```

Do not use `--disable` unless you intend to stop new recordings until the
schedule is enabled again. Read the command's `--help` for battery thresholds,
FPS, and weekly day-bit meanings.

Copy a recording name from `vod search` instead of inventing one:

```bash
reolink-cli --camera porch vod download '<recording-name-from-search>' --file ./recording.bin
```

Some devices support a device-side time cut:

```bash
reolink-cli --camera porch vod download --from 2026-10-12T09:00:00 --to 2026-10-12T09:10:00 --file ./clip.hevc --audio ./clip.aac
ffmpeg -i clip.hevc -i clip.aac -c copy clip.mp4
```

Explicit times must omit an offset and use the camera's local wall time.
`vod search --since` instead uses the CLI computer's local clock. To investigate
an hour mismatch, run `reolink-cli --camera porch system time` and compare the
device clock, standard timezone, DST rules, NTP configuration and CLI clock.
Do not infer a DST rule from a fixed UTC offset. For a container, its timezone
is the CLI timezone when the CLI runs inside it; a host CLI uses the host timezone
even when the gateway is in a container.
DST can be inspected and explicitly configured from the CLI:

```bash
reolink-cli --camera porch system dst get
reolink-cli --camera porch system dst set --enable
reolink-cli --camera porch system dst set --enable --preset us
reolink-cli --camera porch system dst set --disable
```

A plain enable/disable preserves existing rules. Apply `--preset us` only for a
location that observes US DST; it sets +1 hour and the US recurring transition
rules. Custom start/end rules are described in the CLI reference. On a Hub/NVR,
DST affects its own system clock. NTP automatic synchronization does not enable
DST. Keep the correct base timezone and verify the local clock with `system time`
afterward. These commands work through a container gateway when both CLI and
gateway include this update, independent of the container's timezone. Writes
are read back before the command reports success.

The output is not necessarily MP4; the example assumes HEVC
video and AAC audio. If the camera rejects a time cut, download by recording
name instead.

### Recent events, history, and automation

```bash
reolink-cli --camera porch events query --since 30m --last 20
reolink-cli --camera porch events history --since 1d --limit 100
reolink-cli --camera porch events stream --timeout 60
```

- `query` reads the gateway's recent in-memory event buffer and loses entries
  when the gateway restarts.
- `history` asks the device for its stored event history, when supported. An
  omitted type filter explicitly requests the documented alarm types because
  some NVRs otherwise return no events.
- `stream` writes one JSON object per line (NDJSON) for live events. A 60-second
  run with no events can finish normally and does not prove detection is broken.
  It receives pushes without a separate query process. While subscribed, v20
  sessions use a read-only version request at most once per second to drain the
  receive loop; subscribers on the same session share that poll.

For an NVR or Hub, `query`, `stream`, and `monitor run` include all channels
unless a channel is selected by `--channel`, the camera alias, or the config
file. A child alias selects its stored channel, including channel 0. `history`
searches that selected channel and otherwise defaults to channel 0.

The query buffer retains up to 500 events. Idle `none` notifications are still
delivered by `stream` to clear alarm state, but do not occupy the query buffer.
Type filters and monitor triggers match individual types in combined AI
notifications such as `people,dog_cat`.

For a standing reaction such as “take a snapshot when a person appears”, use the
monitor rule engine:

```bash
reolink-cli events monitor init
reolink-cli events monitor check
```

Edit the file path returned by `init`, put in your own camera alias, and run the
foreground daemon in a separate terminal:

```bash
reolink-cli events monitor run
```

Closing the terminal does not turn it into a system service. Use
`events monitor status` and `events monitor history --last 20` from another
terminal. See the [event-monitor reference](../plugins/reolink-cli/skills/reolink-cli/references/event-monitor.md)
for rule syntax and actions.

### Wi-Fi, users, and reboot

These operations can interrupt connectivity or change access. Confirm that you
have a recovery path before applying them:

```bash
reolink-cli --camera porch wifi get
reolink-cli --camera porch users list
```

Pass the new Wi-Fi secret through stdin:

```bash
printf '%s' "$WIFI_PSK" | reolink-cli --camera porch wifi set --ssid '<new-wifi-name>' --psk-stdin
unset WIFI_PSK
```

The CLI tests the network, commits the change, and attempts LAN rediscovery.
Rediscovery timing out does not mean the Wi-Fi change was rolled back; check the
new network and then run `discover` or `device update` as needed. Do not use the
same stdin stream for both the device password and Wi-Fi password.

`users add/remove/passwd` changes camera accounts. After changing the account
used by the registry, update the local registry too. `system reboot` restarts the
camera; wait for it to return and verify with `login` and `info`. A system
operation on a Hub child can still affect the whole Hub.

## Hub and NVR child cameras

Register and verify the Hub or NVR first, then expand its channels:

```bash
reolink-cli device add home-hub --host 192.0.2.20:9000 --user admin
reolink-cli --camera home-hub info
reolink-cli device expand home-hub --yes
reolink-cli device list
```

`expand` creates one alias such as `home-hub-ch0` for each responding channel.
It reuses the parent's address and credentials and tags each child with the
parent alias. Channels are not necessarily contiguous; use the actual output
instead of deriving numbers from the channel count.

For a responding channel 0, either form selects the child:

```bash
reolink-cli --camera home-hub-ch0 info
reolink-cli --camera home-hub --channel 0 info
```

The top-level `info` response may still describe the Hub. Read the child identity
under `data.channel.device`. `standby` or `loginState=standby` is a recent Hub
report that the child is asleep, not a live preflight probe. Wake the child from
the camera or app and retry if appropriate.

`--channel` selects a camera behind a Hub/NVR; `--view` selects a physical lens
on that camera; `--stream main/sub` selects an encoding profile. They are three
different axes. Confirm views with `info`. Non-zero `--view` is not supported by
`preview` or `stream url` and must not be used there.

### Add or unbind a camera on the Hub

`hub add` and `hub remove` change real device bindings. `device add`,
`device remove`, and `device expand` manage the local registry only.

Use a registered **parent Hub** with a reachable LAN address and compatible
firmware. Keep the parent alias; a child alias from `device expand` is rejected.
A gateway is required. Before changing a binding, inspect the channel map with
`reolink-cli --camera home-hub info` and select one channel explicitly with
`--channel N` (0 through 63). Use a free channel for an addition. Channel 0 is a
valid child channel. The selected number does not select the Hub itself.

To add a camera that has its own LAN address:

```bash
reolink-cli --camera home-hub --channel 0 hub add --device-host 192.0.2.30:9000
```

This securely prompts for the **child camera's current password**. The Hub
login comes from the parent alias. `--device-user` defaults to `admin`; it is
separate from the global `--user` used to log in to the Hub. A bare IPv4 address
uses port 9000. If the camera has a factory-default empty password, pass
`--device-empty-password` explicitly.

Alternatively, send the child's UID to the Hub for pairing:

```bash
reolink-cli --camera home-hub --channel 0 hub add --device-uid EXAMPLECHILD001
```

Replace the example with the actual child UID. The Hub performs pairing; it
must be able to reach the child, and the child must be in a state that allows
pairing. These commands do not reset a camera. After a successful addition,
inspect the channels and register aliases for newly responding children:

```bash
reolink-cli --camera home-hub info
reolink-cli device expand home-hub --yes
reolink-cli --camera home-hub --channel 0 info
```

If expansion reports existing aliases, keep valid entries and choose unused
names for new channels. Inspect `info` under `data.channel.device` to confirm
which camera occupies the selected channel.

To unbind a real camera:

```bash
reolink-cli --camera home-hub --channel 0 hub remove
```

The command asks for confirmation, then securely prompts for a **new standalone
password** to assign to the child after unbinding. This is not the Hub password.
`--restore-user` defaults to `admin`. A nonempty password is required. Unbinding
can interrupt the child's Hub recording and access. This version does not
reassign the child's Wi-Fi network; use the Reolink app if a new network is
needed. Local aliases remain in place; remove a stale child alias with
`device remove` only after confirming the device state.

For scripts, store Hub credentials in the parent alias and pipe only the child
password. Do not pass both global `--password-stdin` and a child stdin flag:

```bash
printf '%s' "$CHILD_PASSWORD" | reolink-cli --camera home-hub --channel 0 \
  hub add --device-host 192.0.2.30 --device-password-stdin
printf '%s' "$STANDALONE_PASSWORD" | reolink-cli --camera home-hub --channel 0 \
  hub remove --restore-password-stdin --yes
```

The device operation can take up to 64 seconds. These two CLI commands wait up
to 120 seconds for the gateway response, including connection and login. They
never retry a management request automatically. A timeout or lost connection
means the outcome is unknown: inspect Hub channels before deciding whether to
try again. Error `401` means the child credentials were rejected; check the
reported remaining attempts. `406` means the Hub could not connect to the
child; `411` means unsupported child firmware; `412` means pairing failed;
`413`/`414`/`415` mean channel/device/powered-camera limits; `405` means the Hub
firmware does not support the operation. Model and firmware compatibility must
be verified on the target hardware. ONVIF pairing and channel exchange are not
exposed by these commands.

### Hub scene modes

Scene mode is the Hub/NVR equivalent of the Home/Away/Disarm control in the
Reolink app. It changes alarm tasks for paired channels; it does not change what
motion or AI detection can recognize. Read the Hub's scene ids and supported
tasks before switching or editing:

```bash
reolink-cli --camera home-hub scene show
reolink-cli --camera home-hub scene list
reolink-cli --camera home-hub scene set 3
reolink-cli --camera home-hub scene status
```

Scene ids are device-specific. `scene set --schedule` hands control back to the
weekly timetable. `scene edit --tasks` replaces the selected scene's task set,
so an empty task list disables recording and notifications for that scene.
These commands apply to a Hub/NVR; a plain camera normally returns `405`.

## Doorbell power mode

This applies only to doorbells that expose battery and external-supply mode.
Connecting a power source does not prove that it meets the device requirements
or that the camera switched modes. Confirm the wiring first, then use the
read-check-write-read sequence below. Replace `porch` with the doorbell or Hub
child alias:

```bash
# Read battery and supply status
reolink-cli --camera porch config get power-mode
# Check whether adapter mode is possible without changing the mode
reolink-cli --camera porch config set power-mode \
  --value '{"mode":"adapter","dryRun":1}'
# Switch to external wired power
reolink-cli --camera porch config set power-mode \
  --value '{"mode":"adapter"}'
# Confirm the resulting state
reolink-cli --camera porch config get power-mode
```

Only `powerSupplyStatus=normal` confirms adapter mode. `adapterStatus=adapter`
only identifies the detected source; `accepted=true` only says that the request
was accepted.

| Status or code | Meaning and next step |
|---|---|
| `lowChargeOnly` | The source can charge only; adapter mode is unconfirmed |
| `disconnected`, `tooLow`, `tooHigh` | Check the wiring and supply, then retry |
| `unknown` or missing `powerSupplyStatus` | The device did not provide enough information to confirm the mode |
| `426` | External power is insufficient |
| `427` | Wired power is disconnected |
| `428` | The battery is empty and cannot switch to battery mode |

To return to battery mode:

```bash
reolink-cli --camera porch config set power-mode --value '{"mode":"battery"}'
reolink-cli --camera porch config get power-mode
```

`dryRun` must be the integer `0` or `1`, not a string or Boolean. Power mode
does not enable continuous recording, pre-recording, or a recording schedule;
configure those separately. See the [power-mode reference](cli-reference.md#config-get--set--init)
for response fields.

## Firmware upgrades

`system upgrade` updates camera or Hub firmware. `self-update` updates the CLI
and gateway binaries on the computer.

Before a firmware upgrade, verify the target model, hardware version, and
current firmware; obtain a matching `.pak` or `.paks` package; and provide stable
power. After upload, the device flashes and reboots. Do not remove power until
it returns. The firmware path must be readable by the gateway host; the easiest
safe arrangement is to run CLI and gateway on the same computer.

For an independent camera:

```bash
reolink-cli --camera porch info
reolink-cli --camera porch system upgrade ./firmware.pak
```

The command asks for confirmation. Do not add `--factory-reset` casually; it
clears device settings. A successful upload does not mean flashing has finished.
Wait for the camera to return, then run `login` and `info` and verify the new
firmware.

For a Hub/NVR child, select one child alias or one explicit channel:

```bash
reolink-cli --camera home-hub-ch0 info
reolink-cli --camera home-hub-ch0 system upgrade ./child-firmware.pak
```

The equivalent explicit route is `--camera home-hub --channel 0`. Match the
package to the model, hardware, and firmware under `channel.device`.
**Channel 0 is a valid child channel**; it does not mean “upgrade the Hub”.
Upgrade routing accepts channels 0–63. If no explicit channel is supplied and
the selected alias has no channel, the device-level target is used.

Upgrade one target at a time. Batch selectors do not route a firmware package to
each child, and a channel that exists only in `config.toml` does not select a
child for this command. Before upgrading the Hub itself, run `device resolve` to
confirm that the parent alias is not a child alias. See the [firmware reference](cli-reference.md#system-upgrade)
for routing details.

## Multiple cameras

### Aliases and tags

```bash
reolink-cli device list
reolink-cli device show porch
reolink-cli device update porch --description 'Porch camera' --tags outdoor,entry
reolink-cli --camera porch device resolve
```

`--tags` replaces the tag list; it does not append. Use `--clear-tags` to remove
all tags. Disable or re-enable a registry entry with
`device update porch --disabled true` or `--disabled false`. `device remove porch`
only removes the local registry entry; it does not reset or delete the physical
camera.

### Confirm the scope before a batch read

| Selector | Target |
|---|---|
| `--camera porch` | One registered camera |
| `--cameras porch,backyard` | Several named registered cameras |
| `--tag outdoor` | Every enabled camera with this tag |
| `--all-devices` | Every enabled entry in the registry |

```bash
reolink-cli --tag outdoor device resolve
reolink-cli --tag outdoor device inventory --capabilities
reolink-cli --tag outdoor ping
reolink-cli --all-devices info
```

There is no hidden “current camera”; every operation names its target. Batch
output reports each result, so partial success must not be treated as total
success. `device inventory` exits non-zero when any result is `degraded` or
`failed`.

For batch preview capture, `--file` must be a directory:

```bash
reolink-cli --tag outdoor preview capture --stream sub --file ./captures --packets 128
```

Not every command supports batch selection. Test a write on one camera first and
perform firmware upgrades one target at a time.

### Import discovered cameras

When discovered cameras share one account password, import them through stdin:

```bash
printf '%s' "$DEVICE_PASSWORD" | reolink-cli --user admin --password-stdin \
  device import --discovery lan --alias-prefix office --tags office
reolink-cli device list
reolink-cli --tag office device inventory
```

`device import` skips targets already present and does not test every credential.
Register or update cameras individually when their passwords differ.

## JSON output and scripts

### Read a normal result

The default output is JSON. This is a shape example, not a real camera result:

```json
{"ok":true,"command":"info","protocol":"v20","data":{"model":"Example Camera"},"error":null}
```

The fields under `data` vary by command, camera, and release. Inspect the full
result before choosing a field:

```bash
reolink-cli --camera porch info | jq '.data'
reolink-cli --camera porch info | jq -e '.ok == true'
reolink-cli --output text --camera porch info
```

`text` is for people, not a stable scripting interface. Successful JSON goes to
stdout; runtime errors go to stderr. Argument errors may print normal help text.
Always check the exit code:

```bash
if reolink-cli --camera porch info > info.json 2> info-error.log; then
  jq '.data' info.json
else
  cat info-error.log >&2
fi
```

In Bash or zsh, enable `set -o pipefail` for pipelines so a failed CLI command
cannot be hidden by a successful last process.

### Batch and special output

Batch control output uses `summary` and `results` rather than a single-camera
`data` envelope:

```bash
reolink-cli --tag outdoor info | jq '.summary'
reolink-cli --tag outdoor info | jq '.results[] | {camera, ok, error}'
```

`events stream` is NDJSON. Media commands with `--file -` write binary bytes.
Help, installation, and upgrade prompts are also outside the normal JSON
envelope. Do not send every CLI output to one JSON parser. For `doctor`, inspect
`data.summary.failed` and the exit code.

## Troubleshooting

Use this order to narrow down a failure. Fix the gateway before repeatedly
changing a camera password:

```bash
reolink-cli --version
reolink-cli --output text doctor
reolink-cli gateway status
reolink-cli --camera porch device resolve
reolink-cli --camera porch login
reolink-cli --camera porch info
```

| Symptom | Check and fix |
|---|---|
| `reolink-cli` or `reolink-gateway` not found | Confirm both binaries are installed, reopen the terminal, and check `PATH`; do not copy only the CLI |
| `camera already exists` | Use `device show`; update the existing entry. A disabled template entry still reserves its name |
| `camera not found` or no matching target | Check exact case, tags, disabled state, and the registry path from `features` |
| `no gateway address configured` | Run `config init`, set `gateway-addr`, or pass `--gateway-addr 127.0.0.1:9000` |
| `Connection refused` or gateway down | Start the gateway in another terminal and match its `--addr` to the CLI setting |
| `address already in use` | Find the existing gateway; if another instance is needed, choose a different port and update the CLI address |
| Camera timeout or unreachable | Check the address, port, UID, LAN, power, firewall, and whether the camera IP changed |
| Connection succeeds but login fails | Check the camera-local account, lockout state, and permissions; preserve the failing phase and raw error code |
| Stored password cannot be decrypted | Restore the matching `credentials.key` or re-enter the password; never use ciphertext as the camera password |
| Hub child is asleep or not logged in | Check the channel, wake the child, and retry; a live Hub does not mean every child is awake |
| `unsupported` or device code 405 | Check `capabilities`, model, and firmware; a CLI command is not proof of device support |
| Device code 400 | The request was rejected; inspect parameters, state, and channel before concluding that the model lacks support |
| `unexpected argument` or `unrecognized subcommand` | Check the current binary's `--help`; remove placeholders, comments, or flags from another release |
| Permission error | Fix the actual path, normally to `0600` for Unix config and key files; avoid using `sudo` to create a second profile |
| No player or no video | Install `ffplay`, start with `--stream sub`, and do not use a non-zero `--view` with preview |
| Empty recording or event query | Check time range, timezone, storage, recording/detection settings, and filters; the recent buffer is not full device history |

The gateway normally runs in the foreground. Closing its terminal can make later
device commands fail. It owns connection reuse; there is no separate `session`
command or `--session-mode` option. `gateway status` checks gateway reachability,
not every live camera session.

For latency measurements:

```bash
reolink-cli --camera porch benchmark --phases connect,login,info --iterations 5
reolink-cli --camera porch benchmark --phases connect,login,info --iterations 5 --reuse-session
```

The first form reconnects for each iteration; the second reuses the session.
The `preview` phase measures arrival of the first video bytes, not the first
frame rendered by a player.

When reporting an issue, include CLI/gateway versions, the command, failing
phase, raw error code, and a redacted diagnostic. Do not attach passwords, keys,
credential-bearing stream URLs, or the entire config directory. Review device
and gateway logs for secrets before sharing them.

## Upgrade, uninstall, and data maintenance

### Update the computer software

Back up the config and key files and stop the gateway and monitor first. The
macOS/Linux external distribution can update itself:

```bash
reolink-cli self-update
reolink-cli --version
reolink-gateway --version
```

This downloads and verifies the CLI and gateway binaries. It does not update an
AI skill or guarantee that an already-running gateway restarts. Internal P2P
builds should be updated from their original distribution channel; the current
self-update path selects the external LAN-only asset and may remove UID support.
Windows does not currently replace itself in place; stop the processes, download
the new archive, and run the installer again.

Restart the gateway after updating and run `doctor`, `login`, and `info`. CLI and
gateway should come from the same release archive; checking only the CLI version
does not prove that the gateway was updated.

### Device logs and cache

Errors in the foreground gateway terminal help diagnose connection failures.
Models that support device logs can list and download them:

```bash
reolink-cli --camera porch log calendar --year 2026 --month 10
reolink-cli --camera porch log list --year 2026 --month 10 --start-day 12 --end-day 12
reolink-cli --camera porch log download --name '<log-name-from-list>' --file ./device.log
```

Replace the example date with the actual incident date. These are device logs,
not the gateway terminal output.

```bash
reolink-cli cache status
reolink-cli cache clean --older-than 7d --category captures
```

`cache clean` is a dry run by default. Inspect the candidate list, then add
`--apply` to delete it. It only manages the CLI cache tree; it does not delete
files saved elsewhere with an explicit path.

### Uninstall

The default uninstall keeps configuration, registry, cache, and state:

```bash
reolink-cli setup --uninstall
```

Back up first if you really want to remove those files. `--purge` deletes the
camera registry, credentials, cache, state, and agent drops and cannot be undone:

```bash
reolink-cli setup --uninstall --purge
```

Headless uninstall also requires `--no-interactive`. With multiple gateways,
prefer `Ctrl-C` in each gateway terminal; `gateway stop` stops processes by name
and is not limited to the address in `--gateway-addr`.

## Command map

This map covers the current top-level CLI. Start with `<command> --help`, then
use the [CLI command reference](cli-reference.md). If a release differs, the
installed binary's help output is authoritative.

| Goal | Command entry points |
|---|---|
| Initialize local files | `init`, `config init` |
| Discover and manage cameras | `discover`, `device list/show/add/update/remove/import/expand/resolve/inventory/analyze` |
| Check connectivity and identity | `ping`, `login`, `info`, `capabilities` |
| Device settings and power mode | `config get/set` |
| Wi-Fi | `wifi get/set` |
| Live video and snapshots | `preview play/capture/start/stop`, `snapshot` |
| Video-software URLs | `stream url` |
| PTZ, zoom, and tracking | `ptz move/stop/preset/zoom/focus/patrol/guard/autotrack` |
| Lights | `light ir/statusled/spotlight/whiteled` |
| Volume, siren, replies, and talkback | `audio config/volume/mute/siren/replies/talk` |
| Image, encoder, mask, and OSD | `image flip/tune`, `encode get/set/capability`, `privacy mask`, `osd get/set` |
| Motion and AI detection | `detect motion/ai` |
| Mobile push | `notify push get/set` |
| Recordings and storage | `record config/schedule`, `storage status`, `vod search/download` |
| Events and automation | `events query/history/stream/monitor` |
| Hub device binding | `hub add/remove` (real devices); `device expand` (local aliases) |
| Hub scene mode | `scene show/list/status/set/edit/schedule/alarm/options` |
| Device logs | `log calendar/list/download` |
| Reboot and firmware | `system reboot/upgrade` |
| Device accounts | `users list/add/remove/passwd` |
| Local gateway | `gateway start/status/stop/traffic` |
| Local diagnostics and performance | `doctor`, `features`, `status`, `benchmark` |
| Cache and software maintenance | `cache status/clean`, `self-update`, `setup` |
| Shell completion | `completions` |
| Optional AI integration | `mcp-server`, `plugin refresh` |
| Advanced protocol investigation | `raw`; ordinary use does not need raw requests |
| Help | `help` and every command's `--help` |

Examples:

```bash
reolink-cli device --help
reolink-cli system upgrade --help
reolink-cli notify push set --help
reolink-cli completions powershell
```

The gateway dashboard (`gateway start --open`) also provides a searchable
command directory. If you want AI operation, use the [README AI integration
section](../README.md#ai-agents--mcp) to install the optional Skill or configure
MCP; the direct CLI workflow is complete without either.
