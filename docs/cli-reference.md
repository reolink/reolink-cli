# Reolink CLI Reference

This is the public command index for the local-network reolink-cli package. It
gives each command group a stable starting point and links to the detailed
skill reference where one exists. The installed binary is authoritative for
release-specific flags:

```bash
reolink-cli --help
reolink-cli <command> --help
reolink-cli features
```

For a guided workflow, see the [Operator Guide](operator-guide.md).

## Quick start

Start the local gateway in one terminal:

```bash
reolink-cli gateway start --addr localhost:9000
```

Then target a registered camera from another terminal:

```bash
reolink-cli --camera porch info
```

If the camera is not registered yet:

```bash
reolink-cli config init
reolink-cli discover
reolink-cli device add porch --host 192.0.2.10:9000 --user admin
```

The add command prompts for the local camera password. For scripts, use
--password-stdin; never put a real password in command arguments.

## Global options

Global options select the target and output format. Put them before the command
when possible.

| Option | Environment variable | Description |
|---|---|---|
| --camera <ALIAS> | REOLINK_CAMERA | Registered camera alias |
| --cameras <A,B,...> | - | Comma-separated aliases for a batch |
| --tag <TAG> | - | Select registered cameras by tag |
| --all-devices | - | Select every configured camera |
| --host <HOST:PORT> | REOLINK_HOST | One-shot local camera address |
| --user <USER> | REOLINK_USER | Camera account, usually admin |
| --password-stdin | - | Read a password from standard input |
| --channel <N> | REOLINK_CHANNEL | Child channel on a Hub or NVR |
| --view <N> | REOLINK_VIEW | Physical view on a multi-lens camera |
| --gateway-addr <HOST:PORT> | REOLINK_GATEWAY_ADDR | Local gateway address |
| --config-file <PATH> | REOLINK_CONFIG_FILE | Configuration file |
| --cameras-file <PATH> | REOLINK_CAMERAS_FILE | Camera registry file |
| --output <json or text> | - | Output format, default json |

Target selectors are mutually exclusive. Use one alias, address, tag, list, or
all-device selector for a command. A batch response has summary and results[];
a single-camera response has data.

## Local setup and registry

| Command | Purpose |
|---|---|
| config init | Create local configuration and registry templates |
| init | Compatibility entry point for local initialization |
| discover | Find cameras on the local network |
| device list | List registered cameras |
| device show <ALIAS> | Show one registry entry |
| device add <ALIAS> | Register a local address |
| device update <ALIAS> | Change an existing entry |
| device remove <ALIAS> | Remove an entry |
| device import | Discover and register matching cameras |
| device expand <PARENT> | Create child aliases for a Hub or NVR |
| device resolve | Show the target selected by current options |
| device inventory | Summarize selected cameras and capabilities |
| device analyze | Run a read-only diagnostic |

Examples:

```bash
reolink-cli config init
reolink-cli device list
reolink-cli device add porch --host 192.0.2.10:9000 --user admin
reolink-cli --camera porch device show porch
reolink-cli --camera porch device resolve
```

See [setup and identity](../skills/reolink-cli/references/setup.md) for
registry files, discovery, child channels, and credentials.

## Identity and diagnostics

| Command | Purpose |
|---|---|
| ping | Check target reachability |
| login | Authenticate and return device information |
| info | Read model and firmware information |
| capabilities | Read features reported by the device |
| doctor | Check local installation and gateway health |
| features | Print the installed command manifest |
| status | Print local gateway and device status |
| benchmark | Measure selected read-only phases |

A ping only checks reachability. Use login and info to confirm that the account
and target are correct.

## Generic configuration

```bash
reolink-cli --camera porch config get device-name
reolink-cli --camera porch config set device-name \
  --value '{"deviceName":"Porch"}'
reolink-cli --camera porch config get power-mode
```

Use --value-file for larger JSON values. Read a value before writing it, and
read it back when the command supports verification. Supported paths vary by
device; config get --help and capabilities are authoritative.

The doorbell power path uses:

```bash
reolink-cli --camera porch config set power-mode \
  --value '{"mode":"adapter","dryRun":1}'
reolink-cli --camera porch config set power-mode \
  --value '{"mode":"adapter"}'
```

mode is battery or adapter. A dry run checks acceptance without switching.
Inspect the returned status and follow-up readback after a real change.

## Video and media

| Command | Purpose |
|---|---|
| snapshot | Save a JPEG snapshot |
| preview play | Play live video with ffplay |
| preview capture | Save a bounded preview capture |
| preview start/stop | Manage a preview session |
| stream url | Print RTSP, RTMP, or FLV connection details |
| vod search | Search stored recordings |
| vod download | Download a stored recording |

Examples:

```bash
reolink-cli --camera porch snapshot --file ./porch.jpg
reolink-cli --camera porch preview play --stream sub
reolink-cli --camera porch stream url --kind rtsp --stream sub
reolink-cli --camera porch vod search --since 1d
```

See [media reference](../skills/reolink-cli/references/media.md) for stream
selection, players, snapshots, and recording downloads.

## Camera controls

| Command group | Operations |
|---|---|
| ptz | move, stop, preset, zoom, focus, patrol, guard, autotrack |
| light | ir, statusled, spotlight, whiteled |
| audio | config, volume, mute, siren, replies, talk |
| image | flip, tune |
| encode | get, set, capability |
| osd | get, set |
| privacy mask | get, set |

Typical commands:

```bash
reolink-cli --camera porch ptz move left --speed 16 --duration-ms 500
reolink-cli --camera porch ptz stop
reolink-cli --camera porch light ir set --state auto
reolink-cli --camera porch light spotlight blink --count 3
reolink-cli --camera porch audio config get
reolink-cli --camera porch image flip get
reolink-cli --camera porch privacy mask get
```

Read the current value before a setting change. A siren or talkback command
makes sound at the camera. A privacy-mask change can expose areas that were
previously hidden.

See [controls](../skills/reolink-cli/references/controls.md), [PTZ](../skills/reolink-cli/references/ptz.md),
and [admin](../skills/reolink-cli/references/admin.md) for command-specific
options and safety notes.

## Detection, notifications, and events

| Command | Purpose |
|---|---|
| detect motion get/set | Read or change motion detection |
| detect ai get/set | Read or change supported AI detection |
| notify push get/set | Read or change mobile push settings |
| events query | Read recent in-memory events |
| events history | Read historical event records |
| events stream | Stream events as NDJSON |
| events monitor | Run declarative event-triggered actions |

Examples:

```bash
reolink-cli --camera porch detect motion get
reolink-cli --camera porch notify push get
reolink-cli --camera porch notify push set --interval 30
reolink-cli --camera porch events query --last 20
```

notify push set saves device settings; it does not send a test notification.
Enable push and a matching detection rule in the mobile app before testing
delivery. See [notifications](../skills/reolink-cli/references/notifications.md)
and [event monitoring](../skills/reolink-cli/references/event-monitor.md).

## Recording, storage, and scenes

| Command group | Operations |
|---|---|
| record schedule | get, set |
| record config | get, set |
| storage | status |
| scene | show, list, status, set, edit, schedule, alarm, options |

A schedule or scene write can affect multiple channels. Read the current value,
confirm the selected parent or child, then write and verify.

See [recording](../skills/reolink-cli/references/recording.md), [storage](../skills/reolink-cli/references/storage.md),
and [scene mode](../skills/reolink-cli/references/scene-mode.md).

## Network, users, and system

| Command | Purpose |
|---|---|
| wifi get/set | Read or update camera Wi-Fi settings |
| users list/add/remove/passwd | Manage camera accounts |
| log calendar/list/download | Read and download supported device logs |
| system reboot | Reboot the selected device |
| system upgrade <FILE> | Apply a firmware file |
| gateway start/status/stop | Manage the local gateway |
| cache status/clean | Inspect or clean local cache |
| self-update | Update the local binaries |
| setup --uninstall | Remove installed binaries |

Firmware, account, Wi-Fi, and reboot commands have device-wide side effects.
Confirm the target, scope, and recovery path before running them.

## Output and scripting

The default output is JSON:

```json
{"ok":true,"command":"info","data":{"model":"Example Camera"}}
```

Use --output text for a human-readable result. For scripts, check both the
exit code and ok:

```bash
if reolink-cli --camera porch info >info.json 2>info.error; then
  jq -e '.ok == true' info.json >/dev/null
  jq '.data' info.json
else
  cat info.error >&2
fi
```

Batch commands return summary and results[]. Event streams are NDJSON, and
media commands that write binary data to stdout are not JSON.

## Password and file handling

- Use a registered alias or --password-stdin; do not use a real password in
  --password arguments.
- Keep the registry and its adjacent credentials.key together when backing up.
- Do not share configuration files, credential-bearing URLs, or unredacted logs.
- Use documentation addresses such as 192.0.2.10 in examples and issue reports.
- Redact camera names, addresses, serials, and timestamps when they identify a
  private installation.

## Related references

- [Operator Guide](operator-guide.md)
- [Skill entry point](../skills/reolink-cli/SKILL.md)
- [Reference index](../skills/reolink-cli/references/index.md)
- [Troubleshooting](../skills/reolink-cli/references/troubleshooting.md)
