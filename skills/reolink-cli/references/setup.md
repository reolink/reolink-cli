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
powershell -NoProfile -Command "iwr https://raw.githubusercontent.com/reolink/reolink-cli/main/install.ps1 | iex"
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
reolink-cli --tag nvr-lobby stream url --with-auth    # RTSP URLs for every channel

# Device-global ops (system / users / storage) still work on any child:
reolink-cli --camera porch system reboot              # reboots the whole NVR
```

Children share the parent's `host`/`user`/`password`; they differ only in `channel` and `tags`. `--drop-parent` removes the standalone NVR entry after expansion if you want to avoid confusion between "the NVR as a whole" and "camera 0". Re-running `device expand` on an already-expanded NVR errors on the first name collision — remove the prior children first.

## Identity

```bash
reolink-cli --camera front-door ping           # transport reachability
reolink-cli --camera front-door login          # auth + DeviceInfo
reolink-cli --camera front-door info           # model / firmware / serial
reolink-cli --camera front-door capabilities   # capability tree
```

Run both `ping` and `login` before any other command on an unfamiliar device.

## Generic Config Paths

`config set` reads the current value, merges the patch, then writes — safe partial updates.

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
