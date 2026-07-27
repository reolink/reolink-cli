# Setup: Discovery / Registry / Identity / Generic Config

## Install the `reolink-cli` binary (first run)

Installing this skill does **not** install the binary. If `reolink-cli` is not
on PATH (you'll see `command not found`), fetch it from the GitHub Release once —
prefers `gh` when present, else the public download URL:

```bash
set -e
REPO="reolink/reolink-cli"
BIN="$HOME/.local/bin"; mkdir -p "$BIN"
os=$(uname -s); arch=$(uname -m)
case "$os" in Darwin) os=macos;; Linux) os=linux;; esac
case "$arch" in aarch64) arch=arm64;; x86_64|amd64) arch=x86_64;; esac
[ "$os" = macos ] && [ "$arch" = x86_64 ] && { echo "macOS Intel not supported — Apple Silicon (arm64) only"; exit 1; }
asset="reolink-cli-*-${os}-${arch}.tar.gz"
tmp=$(mktemp -d)
if command -v gh >/dev/null 2>&1; then
  gh release download --repo "$REPO" --pattern "$asset" --dir "$tmp"
else
  ver=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  name=$(echo "$asset" | sed "s/\*/${ver#v}/")
  curl -fsSL -o "$tmp/$name" "https://github.com/$REPO/releases/download/$ver/$name"
fi
tar -xzf "$tmp"/*.tar.gz -C "$tmp"
cp "$tmp"/*/bin/reolink-cli "$tmp"/*/bin/reolink-gateway "$BIN/"
chmod +x "$BIN/reolink-cli" "$BIN/reolink-gateway"; rm -rf "$tmp"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "NOTE: add $BIN to your PATH";; esac
reolink-cli --version   # → 0.10.0 (external · LAN-only)
```

Windows: download the `...-windows-x86_64.zip` from the Releases page and put
`bin\` on PATH. Then `reolink-cli config init`.

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
