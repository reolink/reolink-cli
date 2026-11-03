# Privacy and data handling

This notice describes the local Reolink CLI plugin. Reolink's general
[Privacy Policy](https://reolink.com/privacy-policy/) provides company privacy
information and contact details. Your AI provider and any destination you
configure have separate policies. Local execution does not mean that information
shown to an AI assistant stays on your computer.

## Data and purposes

Camera addresses, UIDs, names, models, firmware, settings, event timestamps,
and diagnostics are used to select devices and carry out requested operations.
Snapshots, video, and audio may contain people, voices, locations, or activity;
access only the media needed for the authorized task.

The native CLI authenticates to cameras using locally configured credentials.
Saved passwords are encrypted; the adjacent `credentials.key` must also be
protected. Passwords must be entered in a local terminal prompt, not AI chat.
Default stream URL output omits passwords. Explicit `--with-auth` output
contains credentials and must remain outside AI tool output and shared reports.

## Recipients and network access

The plugin has no separate hosted camera backend or analytics collector.
The local CLI and gateway communicate with the devices you select. Public
binaries are LAN-only; the public plugin uses those local device connections.

Command output returned to an AI tool, and images or recordings you authorize
the assistant to inspect, may be sent to your AI provider and processed under
your account or organization's settings. Share only selected material, with
authorization, and redact identifying details from support reports.

Installing or updating software contacts the distribution host. Optional
automation, webhooks, notification services, or other integrations can send
events or media to destinations you configure. Enable them only deliberately;
their recipients and retention are governed by those destinations. This plugin
does not authorize changing the camera's own cloud or notification settings.

## Storage, retention, and controls

The CLI stores configuration and encrypted credentials under
`~/.config/reolink-cli/`, runtime state and history under
`~/.local/state/reolink-cli/`, and disposable media under
`~/.cache/reolink-cli/`, unless you choose other paths. These local files remain
until removed or cleaned by the operator; this plugin adds no retention timer.
Container deployments store the equivalent directories under `/data/config/`, `/data/state/`, and `/data/cache/` in the selected Docker volume on its host (which may be a NAS). Back up the registry together with its adjacent key. Copying media to a desktop creates another copy with its own retention. Camera-side recordings follow the device's settings. AI conversation, uploaded
media, and integration retention follow the respective provider's controls.

You can decline media sharing, stop the gateway or automation, remove the
plugin, remove saved camera entries, and delete local artifacts. Uninstalling
the plugin alone does not erase the CLI registry, recordings, or copies already
shared elsewhere. Preview `cache clean` before applying deletion, and use the
AI provider's own deletion controls for conversations or uploaded files.
Use Reolink's privacy-policy contact details for privacy questions; never
include passwords or authentication tokens in a support request.
