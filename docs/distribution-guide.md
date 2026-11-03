# Container deployment


The root Dockerfile packages the published **external, LAN-only** Linux musl
release for `amd64` or `arm64`. It downloads no source or internal SDK, verifies
the archive against the checksum committed to the canonical public repository,
checks for Song P2P fingerprints, and retains the binary EULA and third-party
notices. `REOLINK_VERSION` selects the published binary version, not this
checkout's unbuilt Rust changes. The Compose image name is a local build tag;
no public container registry is assumed.

### Prebuilt images and publication

The manual `Publish external container` GitHub Actions workflow prepares a
versioned multi-platform image at
`ghcr.io/reolink/reolink-cli:VERSION-external`. This is a publication recipe,
not a claim that an image is already available. It must first reach the public
repository through its normal pull-request process. Run it from the default
branch with an already published CLI version whose musl archives and canonical
checksums exist. It tests the host launcher and both image architectures before
logging in and pushing with the repository's `GITHUB_TOKEN`.

For the first publication, verify package access/visibility in GHCR and test an
anonymous pull before advertising it as a public installation option. After
the image is published, users need only the Compose file, rather than Rust or
a source build:

```sh
REOLINK_IMAGE=ghcr.io/reolink/reolink-cli:0.21.0-external \
  docker compose up -d --no-build --pull always
```

`REOLINK_IMAGE` also accepts an approved private registry or mirror. Configure
registry authentication through Docker, not camera credentials in Compose.
Until publication is verified, use the local build below.

From a checkout containing `Dockerfile` and `compose.yaml`:

```sh
docker compose up -d --build
docker compose ps
docker compose exec reolink reolink-cli --version
docker compose exec reolink reolink-cli discover
docker compose exec reolink reolink-cli device add front-door --host 192.0.2.30 --user admin
docker compose exec reolink reolink-cli --camera front-door info
```

Replace the documentation address with the actual camera address. Enter the
camera password at the local terminal prompt, never in AI chat or Compose
environment variables. The gateway starts automatically. The container runs as
UID/GID 10001, with a read-only root filesystem, a writable `/tmp`, and one data
volume. Existing host bind directories must be writable by that UID/GID.

| Container path | Purpose |
|---|---|
| `/data/config/reolink-cli/` | Config, encrypted registry, and its `credentials.key`; back up together |
| `/data/state/reolink-cli/` | Automation state and history |
| `/data/cache/reolink-cli/` | Media, downloads, and logs |

The named `reolink-data` volume survives container recreation and ordinary
`docker compose down`. Removing that volume deletes the registry, its key, and
saved media. Back it up before upgrades. To select another published version,
set `REOLINK_VERSION` when running Compose, then rebuild and recreate the service.

### Network modes

Default bridge mode publishes **no host ports**. Use a known camera IP when LAN
broadcast discovery cannot cross the container network. Desktop clients use
`docker exec`, which needs no gateway port exposed. An AI client in another
container can join this Compose network and use `reolink:9000` as its gateway
address; it also needs its own CLI and authorized local device configuration.
Each container's `127.0.0.1` refers to itself.

For LAN broadcast discovery on a Linux host:

```sh
docker compose -f compose.yaml -f compose.host.yaml up -d --build
```

This shares the host network and binds the gateway to `127.0.0.1:9000`. That
port must be free. Docker Desktop/NAS networking varies; validate discovery on
the actual platform rather than assuming Linux host behavior. The gateway's
HTTP API and TCP control port are not public remote MCP endpoints.

### Desktop CLI and skills

The recommended desktop entry is installed once using Python 3 and Docker CLI.
Python is only needed for setup/checks; the installed entry needs Docker alone.
Run this from the checkout after starting the container:

```sh
python3 scripts/setup-container-cli.py install
export PATH="$HOME/.local/reolink-container/bin:$PATH"
reolink-cli --version
reolink-cli device add front-door --host 192.0.2.30 --user admin
reolink-cli --camera front-door info
python3 scripts/setup-container-cli.py check --camera front-door
```

Use `python` instead of `python3` if that is your Windows Python 3 command. The
installer prints the Windows PATH directory and a client-specific MCP JSON.
It never edits shell startup files or overwrites native binaries. Add its
directory to the desired shell/client PATH and reopen the client, or use the
printed absolute path. To return to native use, remove that directory from
PATH and remove only the installed wrapper. Camera credentials remain in the
container's data volume. The entry pins the selected Docker context and stable
container name, so it survives container recreation and later context changes.
Use `--bin-dir` for a different destination; an existing different entry is
rejected rather than replaced.

The check reports Docker/container, CLI, gateway and camera separately. Without
`--camera`, it explicitly reports that camera connectivity was **not** tested.
With a registered alias, it runs the read-only `info` command inside the
container; network, authentication and alias errors retain their own diagnosis.
It does not scan for cameras or change device settings. Use Compose to manage
container upgrades/start/stop, rather than native `self-update` or `gateway stop`.
For a known IP before credential setup, use `check --host 192.0.2.30:9000`.
That checks TCP only and explicitly skips authentication. Gateway readiness
gets a short retry window while Docker still reports the container as starting.

On macOS/Linux, interactive terminal calls allocate a TTY for password prompts;
piped commands and MCP do not. The Windows `.cmd` entry keeps stdin unmodified
without allocating a TTY. For the initial secure password prompt on Windows,
run `docker --context CONTEXT exec -it CONTAINER reolink-cli device add ...`
in your own terminal, or supply a password using an authorized local stdin
workflow. Do not put passwords in command arguments or AI chat.

For a NAS, create an authenticated Docker SSH context once, then install the
same entry on the desktop:

```sh
docker context create reolink-nas --docker host=ssh://USER@NAS
python3 scripts/setup-container-cli.py install --context reolink-nas
```

Replace `USER@NAS` with the real SSH account/address. The account needs Docker
permissions and working non-interactive SSH authentication. On the NAS, Compose
must already be running; `--container` selects its actual stable container name.
This does not switch the desktop's global Docker context or install a second
gateway. Only the NAS needs network access to the cameras. A local Docker
daemon is not needed when Docker CLI can reach that remote context.

If no desktop entry is wanted, select a container directly in the packaged launcher:

```sh
export REOLINK_CONTAINER=reolink-cli-reolink-1
# For a NAS, also set: export REOLINK_DOCKER_CONTEXT=reolink-nas
sh plugins/reolink-cli/scripts/run-cli.sh --camera front-door info
```

On Windows, set `REOLINK_CONTAINER` to the stable container name
and use `plugins\reolink-cli\scripts\run-cli.cmd`. The selected Docker daemon
must be reachable. Use the stable name (normally `reolink-cli-reolink-1`);
a different Compose project name changes it. If using an ID instead, re-select
it after recreating the container.
`REOLINK_CLI_BIN` takes precedence as an explicit executable override; otherwise
`REOLINK_CONTAINER` selects Docker before the native CLI on PATH.

For a NAS, use Docker's authenticated SSH context on the desktop; the same
launcher and `docker cp` then work against the remote Docker host. Keep device
credentials in the NAS volume. Access to a Docker context grants powerful host
control; do not expose an unauthenticated Docker socket or TCP API.

### Desktop MCP

When the desktop entry is installed on the client's PATH, the plugin's existing
`reolink-cli mcp-server` command also reaches that container. No replacement MCP
registration is needed on macOS/Linux when the client inherits that PATH. On
Windows, use the printed direct Docker MCP entry with the same pinned context/name.
The setup command prints an absolute-path MCP entry
for clients that do not inherit the terminal PATH. Use either that entry or
the default plugin entry, rather than registering duplicate Reolink servers.

Use this MCP entry on macOS, Windows, or Linux; replace the container name when
using a different Compose project. No pseudo-TTY is allocated:

```json
{
  "mcpServers": {
    "reolink": {
      "command": "docker",
      "args": ["exec", "-i", "reolink-cli-reolink-1", "reolink-cli", "mcp-server"]
    }
  }
}
```

For standalone Claude Code MCP registration, use:

```sh
claude mcp add reolink-container -- docker exec -i reolink-cli-reolink-1 reolink-cli mcp-server
claude mcp list
```

This registers the container command in the selected Claude configuration.
The full plugin's default MCP entry targets `reolink-cli` on PATH. Without an
installed Docker-backed entry, it still uses the native CLI. For a session
using that plugin with only the supplied MCP configuration, save the JSON as
`reolink-container.mcp.json` outside the plugin and run:

```sh
claude --plugin-dir . --strict-mcp-config --mcp-config ./reolink-container.mcp.json
```

`--strict-mcp-config` selects only that session's supplied MCP entries; include
other desired servers in the JSON too. OpenAI skills-only users select the
container launcher instead; they do not need MCP. These remain local-execution
workflows and do not enable ordinary cloud chat to reach a LAN.

### Retrieve media

Save snapshots and recordings under the persistent cache, then copy only the
requested file to the desktop. Container paths are not host paths:

```sh
docker compose exec reolink reolink-cli --camera front-door snapshot --file /data/cache/reolink-cli/snapshots/front-door.jpg
docker cp reolink-cli-reolink-1:/data/cache/reolink-cli/snapshots/front-door.jpg ./front-door.jpg
```

For a NAS, prefix `docker cp` with the selected `--context NAME`, and use its
actual container name. For MCP `camera_snapshot`, pass that same container path as `filePath`.
Copy it with `docker cp` after the tool returns. A request to analyze that
particular image authorizes sharing that image; it does not authorize uploading
other recordings. Do not expose the data volume through a public file server.
Live `preview play` needs a display and ffplay, which the headless image does
not contain; use file capture and retrieve it, or play an authorized stream in
a desktop player.

### OpenClaw and other containerized agents

There are two supported execution layouts:

| Agent location | Camera entry | Media access |
|---|---|---|
| Docker host/desktop | Installed Docker-backed CLI, or the packaged Docker launcher | Copy the requested file from the selected container |
| Separate agent container on the same Docker engine | Native musl CLI copied into its image; network to the existing gateway | Shared cache plus a read-only workspace media view |

For the second layout, `container/agent.Dockerfile` copies verified released
binaries, licenses and skill instructions into an existing agent image. It
preserves that image's user, entrypoint, command and agent configuration. It
does not install Docker or mount its socket. The CLI wrapper sets camera XDG
paths only for the CLI process; other agent programs retain their own paths.

Use the **same non-root UID/GID** for the gateway and agent. The OpenClaw image
tested here uses `1000:1000`; verify your own image with `id`. The ordinary
Reolink image remains `10001:10001`. For a new OpenClaw deployment, build a
separate tagged gateway image and use a new project/volume:

```sh
docker build --build-arg REOLINK_UID=1000 --build-arg REOLINK_GID=1000 \
  -t reolink-cli:0.21.0-agent .
REOLINK_IMAGE=reolink-cli:0.21.0-agent \
  docker compose -p reolink-agent up -d --no-build
docker compose -p reolink-agent exec reolink reolink-cli device add front-door \
  --host 192.0.2.30 --user admin
docker build -f container/agent.Dockerfile \
  --build-arg REOLINK_IMAGE=reolink-cli:0.21.0-agent \
  --build-arg AGENT_IMAGE=ghcr.io/openclaw/openclaw:2026.10.5-slim \
  -t openclaw-reolink:2026.10.5 .
```

Use your existing, pinned OpenClaw version for `AGENT_IMAGE`; integrating a
camera does not require upgrading OpenClaw. Do not attach the UID-1000 image
to an existing UID-10001 data volume and expect permissions to change. Existing
deployments need a backup and a deliberate ownership migration during planned
downtime; do not weaken mode-0600 credentials or silently chown user data.

`compose.openclaw.yaml` is an overlay for **OpenClaw's own Compose file**. It
keeps OpenClaw's existing startup command, environment and state/workspace
volumes. From that deployment's directory, with its existing `.env` and all
previously used overrides, add the Reolink overlay last:

```sh
export REOLINK_AGENT_IMAGE=openclaw-reolink:2026.10.5
export REOLINK_NETWORK=reolink-agent_default
export REOLINK_DATA_VOLUME=reolink-agent_reolink-data
docker compose -f docker-compose.yml \
  -f /absolute/path/to/reolink-cli/compose.openclaw.yaml config --quiet
docker compose -f docker-compose.yml \
  -f /absolute/path/to/reolink-cli/compose.openclaw.yaml up -d
```

This overlay requires Docker Engine 26+ and Compose 2.35+ for named-volume
subpaths. Older NAS engines can continue using the host/SSH Docker-backed
entry; do not mount a Docker socket in the agent as a workaround. The agent
joins the selected Reolink network and uses `REOLINK_GATEWAY_ADDR=reolink:9000`.
There is no published gateway port. The config/key subdirectory is read-only
in the agent, while only the cache subdirectory is writable. The same cache
is readable at `/home/node/.openclaw/workspace/reolink-media/`; set
`REOLINK_AGENT_MEDIA_DIR` if your OpenClaw workspace is elsewhere.

Merge this skill setting into the existing OpenClaw configuration, retaining
its other values:

```json
{"skills":{"load":{"extraDirs":["/opt/reolink/skills"]}}}
```

Check `openclaw skills info reolink-cli --json` in the actual execution
environment. `eligible: true` verifies skill loading and binary prerequisites,
not a model/tool conversation. The skill uses CLI execution and does not need
an invented `plugins.entries` runtime adapter or an MCP server in OpenClaw.
An optional nested agent sandbox needs its own matching image, network and
mounts; installing these in the OpenClaw Gateway container does not configure
the sandbox. Do not disable a user's sandbox globally to make a test pass.

Save snapshots under `/data/cache/reolink-cli/snapshots/` through the CLI. For
an OpenClaw attachment, the same authorized file appears at workspace-relative
`reolink-media/reolink-cli/snapshots/FILE.jpg`; no Docker command or password in
the prompt is needed. Model/provider and messaging-channel configuration stay
with the user's existing OpenClaw deployment. This trusted agent can decrypt
the registered camera credentials; read-only mounting prevents accidental
edits, not disclosure by an untrusted agent. Use a dedicated registry/stack
for each agent trust boundary.

Verify the actual image and registered camera, optionally capturing one image:

```sh
python3 scripts/check-agent-container.py \
  --agent-image openclaw-reolink:2026.10.5 \
  --gateway-container reolink-agent-reolink-1 \
  --openclaw --camera front-door --snapshot
```

The check creates and removes only its own temporary execution container and
test media. It verifies UID/GID, read-only config, media visible in both
containers/workspace, skill eligibility, real `info` and optionally JPEG
capture. It does not start a model conversation or send messages externally.
The main Compose deployment remains running. Local verification used a Linux image
assembled from the locally installed OpenClaw 2026.9.1 package, with the skill
loaded from the image and real camera info/JPEG capture through the separate
gateway. Overlay merging was also checked against
the official OpenClaw 2026.10.5 Compose file. This does not establish a complete
model conversation, nested sandbox operation, or NAS compatibility. The optional
HTTP tool endpoint is not the agent execution path; do not relax its tool policy
for this integration. If hardening the agent root filesystem as read-only, retain
its own writable state/cache/temp directories as required by that pinned image.
Container images disable duplicate application log files; Compose stdout logs
rotate at 10 MB with three retained files. Media/cache retention remains an explicit operator choice (`cache status`,
then a reviewed cleanup).

### Build and validate architectures

```sh
docker buildx build --platform linux/arm64 --load -t reolink-cli:0.21.0-arm64 .
python3 scripts/check-container.py --image reolink-cli:0.21.0-arm64
docker buildx build --platform linux/amd64 --load -t reolink-cli:0.21.0-amd64 .
python3 scripts/check-container.py --image reolink-cli:0.21.0-amd64
```

The check uses a unique disposable Compose project and removes only that
project's containers, network, and volume. It checks gateway readiness, MCP
initialization and tools, launcher I/O, encrypted configuration/key persistence,
and copying synthetic media after recreation. It never operates a real camera.
Run physical-camera discovery, query, and snapshot checks separately on the
target network. Cross-architecture execution requires engine emulation support.

To publish a multi-platform image after release approval, use Buildx with
`--platform linux/amd64,linux/arm64` and a chosen registry tag with `--push`.
Builders with a classic image store cannot load a manifest list with `--load`;
the separate architecture commands above work for local verification.
