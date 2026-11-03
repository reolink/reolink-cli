# Reolink CLI MCP Guide

This guide explains how to connect an MCP client to the local
`reolink-cli` server. MCP is optional: the terminal CLI and the local gateway
work without an AI client or an MCP server.

The public release is a LAN-only build. It connects to cameras through their
local address and does not provide a remote relay transport. Use it only with
cameras you own or are authorised to administer.

## How the pieces fit together

The integration has three processes or layers:

| Component | Role | Lifetime |
|---|---|---|
| `reolink-cli` | Starts the MCP server and provides the command line surface | Started by the MCP host |
| MCP server | Speaks JSON-RPC over standard input and output and exposes typed tools | One process per MCP host session |
| `reolink-gateway` | Keeps local camera sessions and performs device operations | Started separately and kept running |

The MCP server is a thin adapter over the same control runtime as the CLI. It
does not replace the gateway, and it does not create a second device registry.

## Requirements

Install the same release that you use for direct CLI operations, then verify
both binaries:

```bash
reolink-cli --version
reolink-gateway --version
reolink-cli features
```

The version output for the public package identifies the external LAN-only
build. Keep the CLI, gateway, and MCP server from the same release so their
tool schemas and gateway actions agree.

Register a camera before starting the MCP host. The alias registry keeps the
camera address and encrypted credentials on the local machine:

```bash
reolink-cli config init
reolink-cli device add porch --host 192.0.2.10:9000 --user admin --password-stdin
reolink-cli --camera porch info
```

`192.0.2.10` is a documentation address; replace it with the camera's local
address. The password is read from standard input. Never put a real password in
the command line or in an MCP client configuration file.

## Start the gateway

Start the gateway once for the session. The default address is local to the
computer running the MCP server:

```bash
reolink-cli gateway start --addr 127.0.0.1:9000
```

Check it from another terminal:

```bash
reolink-cli gateway status
```

If the gateway uses another address, set `REOLINK_GATEWAY_ADDR` to that address
in the MCP server environment. The MCP host and the gateway must be able to
reach one another; the camera itself must also be reachable from the gateway
host.

## Configure an MCP client

MCP hosts generally accept a JSON object containing a command, arguments, and
environment variables. Use an absolute path when the host does not inherit the
same `PATH` as your terminal:

```json
{
  "mcpServers": {
    "reolink-cli": {
      "command": "/absolute/path/to/reolink-cli",
      "args": ["mcp-server"],
      "env": {
        "REOLINK_GATEWAY_ADDR": "127.0.0.1:9000"
      }
    }
  }
}
```

Replace `/absolute/path/to/reolink-cli` with the result of
`command -v reolink-cli` on macOS/Linux, or the full path to
`reolink-cli.exe` on Windows. Client configuration files do not expand shell
variables consistently, so an absolute path is safer than `$HOME` or `%USERPROFILE%`.

The exact file location differs by host. Open the host's MCP server settings,
add the entry above, and restart or reload the host. Do not add a second gateway
command to the MCP entry: the gateway is a separate long-running process.

When the repository is installed as a Claude Code plugin, its plugin manifest
registers the MCP server automatically. The `reolink-cli` binary must still be
available on the plugin host's `PATH`, and the gateway must still be running.
If Claude Code reports that the command cannot be found, use the absolute-path
configuration above or fix the host process's `PATH` before reloading the
plugin.

## Protocol lifecycle

The server uses JSON-RPC 2.0 over stdio. An MCP host normally performs this
sequence automatically:

1. Start `reolink-cli mcp-server`.
2. Send `initialize` with a supported MCP protocol version.
3. Send `notifications/initialized`.
4. Call `tools/list` and cache the returned schemas.
5. Send `tools/call` requests as the user works.
6. Close the stdio process when the client session ends.

For a protocol-level smoke test, the first request has this shape. Let the MCP
host generate the request IDs and framing in normal use:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": {"name": "example-client", "version": "1.0"}
  }
}
```

After initialization, `tools/list` is the authority for the installed binary's
tool names and JSON schemas. Documentation may lag a binary from another
release; do not dispatch a tool that is absent from `tools/list`.

## Available tool groups

The server exposes the stable, typed operations supported by the public build.
The exact set is returned by `tools/list`; names can grow between releases.

| Group | Typical tools | Purpose |
|---|---|---|
| Identity | `camera_ping`, `camera_login`, `camera_info`, `camera_capabilities`, `camera_discover` | Reachability, authentication, device identity, and discovery |
| PTZ | `camera_ptz_move`, `camera_ptz_stop`, `camera_ptz_presets`, `camera_ptz_preset_goto`, `camera_ptz_preset_set`, `camera_ptz_preset_delete` | Movement and preset management |
| Lighting | `camera_light_ir_get`, `camera_light_ir_set`, `camera_light_statusled_get`, `camera_light_statusled_set`, `camera_light_spotlight_set` | Read and change supported lights |
| Audio | `camera_audio_volume_get`, `camera_audio_volume_set`, `camera_audio_mute`, `camera_siren_play`, `camera_siren_stop` | Volume, mute, and supported sound actions |
| Scenes and encoding | `camera_scene_show`, `camera_scene_list`, `camera_scene_schedule_get`, `camera_scene_set`, `camera_encode_get`, `camera_encode_capability`, `camera_encode_set` | Hub scenes and stream encoder settings |
| Detection | `camera_detect_motion_get`, `camera_detect_motion_set`, `camera_detect_ai_get`, `camera_detect_ai_set` | Motion and supported AI detection settings |
| Media | `camera_preview_capture`, `camera_snapshot` | Save a bounded preview or JPEG snapshot |
| Recording and events | `camera_record_config_get`, `camera_storage_status`, `camera_vod_search`, `camera_events_query`, `camera_events_history` | Read storage, recordings, and recent events |
| Image and OSD | `camera_image_flip_get`, `camera_image_flip_set`, `camera_image_tune_get`, `camera_osd_get`, `camera_osd_set` | Image orientation, tuning, and on-screen display |
| Accounts and system | `camera_users_list`, `camera_system_reboot` | Read device accounts and reboot when supported |
| Generic configuration | `camera_config_get`, `camera_config_set` | Access documented configuration paths |

The public MCP surface does not expose an untyped protocol escape hatch. Use a
typed tool and its schema, and check `camera_capabilities` before a
model-specific setting.

## Select a camera for each call

The server accepts a default target from the process environment or CLI
startup, and accepts a per-call target override. Prefer a registered alias:

```json
{
  "name": "camera_info",
  "arguments": {
    "alias": "porch"
  }
}
```

For a one-off local target, pass `host` instead:

```json
{
  "name": "camera_info",
  "arguments": {
    "host": "192.0.2.10:9000",
    "user": "admin"
  }
}
```

Use only one of `alias` or `host` in a call. Hub and NVR child cameras use the
parent address plus a channel number:

```json
{
  "name": "camera_info",
  "arguments": {
    "alias": "lobby",
    "channel": 0
  }
}
```

Channel `0` is a valid child channel. Use the same alias and channel when
checking capabilities and performing a later operation. Batch selectors such as
tags and all-device selection are not accepted as MCP server startup options;
make one explicit tool call per target.

Do not send a `password` field in a tool call. Credentials in tool arguments
would be written into an agent transcript. Register the camera with
`device add`, or provide the server's credential environment through the host
when a one-off target is required.

## Common workflows

### Read device state

Use the alias registered above and call these tools in the MCP host:

1. `camera_info` for model and firmware.
2. `camera_capabilities` for supported features.
3. The relevant read-only tool, such as `camera_storage_status` or
   `camera_events_query`.

The tool result is the source of truth. Do not infer reachability or a setting
from the MCP connection alone.

### Change a setting

Read the current value first, confirm that the capability is present, then call
the matching typed setter. For an idempotent operation, prefer a CLI `apply`
command from the terminal; MCP setters expose the device operation directly and
may require a follow-up read to confirm the result.

### Capture media

`camera_snapshot` and `camera_preview_capture` write to a path available to the
MCP server process. Use a dedicated directory, make the path absolute when the
host may change its working directory, and treat the resulting image or video
as personal data.

### Hub or NVR child

Call `camera_info` with the child alias or explicit `channel`, then use that same
target for the operation. The parent model and firmware do not necessarily
describe the child camera.

## Security and privacy

- Keep the gateway bound to `127.0.0.1` unless another local network client
  needs access. If it must listen on a LAN address, restrict the firewall and
  understand that device control is then exposed to that network.
- Keep MCP configuration files private. They may contain paths and gateway
  addresses even when they do not contain passwords.
- Use a registered alias whenever possible. Stored credentials are encrypted
  locally; keep the registry and its `credentials.key` together when backing up.
- Never put passwords in tool arguments, shell history, JSON examples, issue
  reports, or screenshots.
- Redact addresses, serial numbers, account names, event data, and media before
  sharing tool results.
- Use the integration only on devices you own or are authorised to administer.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| The host shows no MCP tools | The command path and host logs | Use an absolute binary path and reload the MCP configuration |
| The server starts but calls fail with connection refused | `reolink-cli gateway status` | Start the gateway or correct `REOLINK_GATEWAY_ADDR` |
| `tools/list` does not contain a documented tool | `reolink-cli --version` and `tools/list` | Use the tool set returned by the installed binary; update the CLI and gateway together |
| No target is available | `reolink-cli device list` | Register an alias, or pass a local `host` and `user` per call |
| Authentication fails | `reolink-cli --camera <alias> login` | Re-enter the local camera account through `device update`; do not add a password to a tool call |
| A Hub/NVR child fails | `camera_info` with the child alias and `channel` | Confirm the channel, parent address, and child availability |
| A write is rejected | `camera_capabilities` and the tool result's error | The model or firmware may not support that operation; do not retry blindly |
| A snapshot cannot be opened | The output path from the MCP server's point of view | Use an absolute writable path and check the host process permissions |

When reporting a failure, include the CLI version, gateway address class (local
or LAN), tool name, target alias, exact error code, and a redacted result. Do
not include passwords, credential files, or complete configuration directories.

## Related references

- [Operator Guide](operator-guide.md) — installation, camera registration,
  gateway operation, Hub/NVR workflows, and troubleshooting
- [CLI Reference](cli-reference.md) — command-oriented CLI index
- [Security Policy](../SECURITY.md) — reporting and data-handling guidance
- `reolink-cli mcp-server --help` — release-specific startup options

## Classified alarm-video intervals

`camera_vod_alarms` is a read-only tool for the separate device alarm-video
index. Required `from` and `to` values use the device's local wall clock;
optional inputs include `camera`, `channel`, `recordType`, `streamType` and
`limit`. Results are alarm intervals, not rewritten ordinary recording metadata.
A firmware-specific unsupported response remains an error, not an empty success.
