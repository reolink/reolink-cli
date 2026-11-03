# Setup: Discovery / Registry / Identity / Generic Config

## Install the `reolink-cli` binary (first run)

Installing this skill does **not** install the binary. If `reolink-cli` is not
on PATH (you'll see `command not found`), run the installer once:

```bash
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh | sh
reolink-cli --version   # → <version> (external · LAN-only)
```

If your environment will not pipe a download into a shell, fetch and run it in
two steps instead:

```bash
curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh -o /tmp/reolink-install.sh
sh /tmp/reolink-install.sh
```

Use the installer rather than downloading a release archive by hand. It picks
the right archive for the platform — including the musl build on Alpine and
Home Assistant OS, where the glibc archive cannot load at all — and it verifies
the download against the checksum committed to the repository, refusing to
install anything that does not match. A hand-rolled `curl | tar` skips that
check entirely. It installs both binaries to `~/.local/bin`, runs
`config init`, and prints the PATH line if the directory is not on PATH yet.

**If it refuses with a checksum mismatch**, retry once — a truncated download is
the ordinary cause. If it fails again, report it and stop; do not point
`REOLINK_REPO` at another repository or fetch the archive by hand to get past
it. There is deliberately no flag to skip verification.

**On Home Assistant OS**, install inside the `homeassistant` core container
rather than on the host: that is where `shell_command` runs, and it is aarch64
Alpine, so it needs the musl build the installer selects automatically. Which
build you have is not in `--version`; read it with
`file "$(command -v reolink-cli)"`, where "statically linked" means musl.

**Windows** — this form works from PowerShell *and* from the Command Prompt:

```
powershell -NoProfile -Command "iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 -UseBasicParsing | iex"
```

`iwr` and `iex` are PowerShell aliases, so the bare `iwr … | iex` fails in
cmd.exe with `'iwr' is not recognized` — an error that names the alias rather
than the cause. Use the form above and it does not matter which shell you are
in. It installs to `%USERPROFILE%\.local\bin`, adds it to PATH, runs
`config init`, and verifies the download against the committed checksum, which
downloading the `.zip` by hand does not.

## Discovery

```bash
# Bootstrap sample config + cameras registry files (one-time)
reolink-cli config init

# Discover LAN hosts (ONVIF + TCP) and remote UIDs
reolink-cli discover --timeout-secs 3

# Probe a known target, no login
reolink-cli --host 192.168.1.43 --user admin ping       # REOLINK_PASSWORD env
reolink-cli --uid 952700EXAMPLE001 --user admin ping
```

First remote (UID) probe warms up the connection; 10–15s is normal. Bump `--timeout-secs` if needed.

LAN discovery sends the native Reolink UDP probe on every active IPv4 interface
broadcast domain plus `255.255.255.255`, so dual-NIC hosts should now see
cameras on each directly attached subnet in one scan.

**What each field means (and why two machines can bucket devices differently).**
`discover` runs several probes in parallel and merges the answers per device:

- The **Reolink UDP broadcast** (`lanUdp`) supplies the UID, the `mac`, the
  friendly name (`reolink-lan://name/…` scope), the hardware model
  (`reolink-lan://hardware/…` scope), the device kind, and the port-qualified
  host (`<ip>:9000` — the form `device add --host` wants). This probe answers
  regardless of the ONVIF setting, so these fields are the ones you can count
  on for every device.
- **ONVIF WS-Discovery** (`lan`) supplies the ONVIF endpoint, `xaddrs`, and the
  hardware model in `onvif://…` scopes — **only for devices with ONVIF enabled**
  in the camera/NVR settings (Network → Advanced → Port/server settings; it is
  off by default on many models). Toggling ONVIF on a device adds or removes
  this extra metadata in its entry; UID, name and MAC are unaffected.

`mac` is the field to join on when matching `discover` output against DHCP
leases or a router's client list — it is stable across the address changes that
make `host` unreliable as an identity.

One device found by both probes yields ONE entry carrying the union of fields;
the `discovery` label only records which probe answered. The `counts` split is
therefore environmental, not meaningful: a firewall that eats WS-Discovery
responses (common on Windows) moves devices from `lan` to `lanUdp` without
changing what you learn about them. Do not treat `counts` differences across
machines as a fault — compare the per-device fields instead.

**When `discover` returns empty:**
1. First run `reolink-cli device list` — user may already have cameras registered; if the target camera exists, verify with `ping` + `login` and report to the user. Don't invent data.
2. If no matching camera is registered, ask the user whether they want to enter a known IP/UID manually (use `device add CAMERA --host IP:PORT --user admin`) or extend the timeout (`--timeout-secs 10`).
3. Don't call `device import` with empty results — it would no-op silently and confuse follow-up.

## Device Registry

```bash
# List / show / resolve
reolink-cli device list
reolink-cli --camera front-door device show front-door
reolink-cli --camera front-door device resolve
reolink-cli --tag outdoor device resolve

# Add (prompts for password interactively — do NOT pass --password on argv)
reolink-cli device add front-door --host 192.168.1.43 --user admin --tags outdoor,entrance
reolink-cli device add "front door" --host 192.168.1.41 --user admin --password-stdin
```

A name with a space needs quotes, like any shell argument — without them the
shell splits it and the second word arrives as an unexpected argument. Names
match exactly, so `Front Door` and `front door` are two different cameras. The
hyphen in `front-door` is only there to save the quotes later.

```bash

# Update / remove
reolink-cli device update front-door --description "Front door camera"
reolink-cli device remove front-door

# Discover + auto-import
reolink-cli device import --timeout-secs 3 --alias-prefix cam --tags indoor

# Summarize / capability-check selected devices
reolink-cli --tag outdoor device inventory --capabilities
reolink-cli --camera front-door device analyze --capabilities
```

## NVR (RLN series) — multi-channel

RLN-series NVRs multiplex N sub-cameras behind one `host:9000` endpoint, addressed by a `channel` index (0..N-1). After `device add`, expand the parent into one flat camera entry per channel:

```bash
# 1. Register the NVR itself (one entry, treats it as a single device)
reolink-cli device add nvr-lobby --host 192.168.1.50:9000 --user admin

# 2. Expand — probes channelNum via GetSupport, registers N children
reolink-cli --gateway-addr 127.0.0.1:9000 device expand nvr-lobby
# Interactive prompts per channel; press Enter to accept `nvr-lobby-ch<i>` defaults.

# Or non-interactively:
reolink-cli --gateway-addr 127.0.0.1:9000 device expand nvr-lobby --yes
reolink-cli --gateway-addr 127.0.0.1:9000 device expand nvr-lobby --names porch,backyard,garage,attic

# 3. Each child is now a first-class camera; the parent tag fans out
reolink-cli --camera porch snapshot                   # one channel
reolink-cli --tag nvr-lobby snapshot                  # fan-out across all children
reolink-cli --tag nvr-lobby stream url    # Credential-free RTSP URLs for every channel

# Device-global ops (system / users / storage) still work on any child:
reolink-cli --camera porch system reboot              # reboots the whole NVR
```

Children share the parent's `host`/`user`/`password`; they differ only in `channel` and `tags`. `--drop-parent` removes the standalone NVR entry after expansion if you want to avoid confusion between "the NVR as a whole" and "camera 0". Re-running `device expand` on an already-expanded NVR errors on the first name collision — remove the prior children first.

## Real Hub child binding and unbinding

`device add/remove/expand` only manage local aliases. `hub add/remove` change
actual Hub bindings. Check `features` includes `hub` before using these commands.
They require the gateway, a parent Hub reachable over LAN, firmware support,
and an explicit global `--channel N` from 0 to 63. Select the **parent alias**,
never an expanded child or batch selector. Confirm intent and inspect Hub
channels via `info` before a change; use a free channel for an addition.

```bash
# Prompt securely for the child's current password, separate from Hub credentials.
reolink-cli --camera home-hub --channel 0 hub add --device-host 192.0.2.30:9000
# Or send the child's UID to the Hub for pairing.
reolink-cli --camera home-hub --channel 0 hub add --device-uid EXAMPLECHILD001
# Inspect channels, then register local aliases for new children.
reolink-cli --camera home-hub info
reolink-cli device expand home-hub --yes
# Real unbind: confirm, then prompt for a new nonempty standalone child password.
reolink-cli --camera home-hub --channel 0 hub remove
```

`--device-user` and `--restore-user` default to `admin`. Global credentials are
for the Hub. `--device-empty-password` explicitly permits a factory-default
empty child password on add. In scripts, keep Hub credentials in the parent
alias and use `--device-password-stdin` or `--restore-password-stdin`; removal
also requires `--yes`. Never combine either with global `--password-stdin`.
No child plaintext password flag exists.

The Hub performs pairing; the child must be reachable and ready to pair. This
version does not reset devices, configure Wi-Fi on unbind, pair via ONVIF, or
exchange channels. Unbinding can interrupt Hub recording/access and does not
delete local aliases. Remove stale aliases only after checking device state.

A management operation may wait 64s; the CLI waits up to 120s for its gateway
response. There are no automatic mutation retries. A timeout or disconnect means
unknown outcome: inspect channels before another attempt. Device errors identify
child password rejection (401, with attempt counters when supplied), connection
failure (406), unsupported firmware (411), pairing failure (412), channel/device/
powered-camera capacity (413/414/415), or unsupported command (405). Verify
model and firmware compatibility on actual hardware.

## Identity

```bash
reolink-cli --camera front-door ping           # transport reachability
reolink-cli --camera front-door login          # auth + DeviceInfo
reolink-cli --camera front-door info           # model / firmware / serial
reolink-cli --camera front-door capabilities   # capability tree
```

Run both `ping` and `login` before any other command on an unfamiliar device.

## Generic Config Paths

`config set network` and `config set osd` merge partial patches with the current value. Other paths validate their own fields; `power-mode` performs the requested switch and reads back supply status.

Working paths only (no stubs):

```bash
reolink-cli --camera front-door config get led
reolink-cli --camera front-door config get device-name
reolink-cli --camera front-door config get language
reolink-cli --camera front-door config get time-zone
reolink-cli --camera front-door config get time-format
reolink-cli --camera front-door config get network
reolink-cli --camera front-door config get osd
reolink-cli --camera front-door config get osd-format
reolink-cli --camera front-door config get system-general   # get-only
reolink-cli --camera front-door config get performance      # get-only: live CPU / encoder / network load
reolink-cli --camera doorbell config get power-mode        # battery / external supply status
```

```bash
reolink-cli --camera front-door config set device-name --value '{"deviceName":"Front Door"}'
reolink-cli --camera front-door config set language    --value '{"language":"English"}'
reolink-cli --camera front-door config set time-zone   --value '{"timeZone":28800}'
reolink-cli --camera front-door config set time-format --value '{"timeFormat":0}'
reolink-cli --camera front-door config set osd         --value '{"osdChannel":{"enable":1,"name":"Front"}}'
reolink-cli --camera front-door config set led         --value '{"state":"auto"}'
```

For brightness/contrast, use `image tune` (see `controls.md`). For volume use `audio volume` / `audio config` (see `controls.md`). For AI/motion detection use `detect ai` / `detect motion` (see `detection.md`). The old stub paths `image` / `audio` / `alarm` / `alarm-policy` / `ai` have been removed — if you see them in older notes, they never worked.

### Battery doorbell external power mode

Run `features` first to ensure the installed CLI supports `power-mode`, and run a gateway built with the same feature. Read `capabilities`: `batteryMode` bit8 (`value & 256`) enables manual battery/adapter switching; bit6 alone is insufficient. Read `config get power-mode` before a switch. Use the same camera/channel throughout; Hub/NVR children need `--channel N` or a registered child alias.

```bash
# Check external wired power without changing the mode
reolink-cli --camera doorbell config set power-mode --value '{"mode":"adapter","dryRun":1}'
# Switch only when the user requests the device mode change
reolink-cli --camera doorbell config set power-mode --value '{"mode":"adapter"}'
reolink-cli --camera doorbell config set power-mode --value '{"mode":"battery"}'
```

`dryRun` is integer `0`/`1`; omitted/0 changes the mode. A dry run only checks prerequisites and returns `accepted`; it does not establish the requested mode. Unknown fields are rejected to catch misspelled check flags.

An actual switch returns `data.value.requestedMode`, `accepted`, and `status` (automatic cmd 253 readback). **Do not claim a mode change from ACK / `accepted` alone.** `status.powerSupplyStatus=normal` confirms adapter mode. `lowChargeOnly` means the external source can only charge; `disconnected`/`tooLow`/`tooHigh`/`unknown`, or an omitted field, do not confirm it. `adapterStatus=adapter` alone is insufficient: a DBB3 connected to Type-C without terminal wiring may report `disconnected`. A status readback failure explicitly says the switch was accepted; do not assume it was rolled back.

Preserve device error codes: **426** insufficient external power, **427** wired power disconnected, **428** empty battery. Address the reported physical condition before retrying. Cmd 805 switches supply modes; `record schedule` and cmd 451/452/626 configure other behavior.
