# Container and Agent deployments

Determine where the command executes before operating a camera. Use the
deployment the user selected; never install a second native gateway to repair
a container connection.

## Agent on the Docker host or desktop

Use the Docker-backed `reolink-cli` entry installed by
`scripts/setup-container-cli.py`, or the packaged launcher with
`REOLINK_CONTAINER` and optionally `REOLINK_DOCKER_CONTEXT` for a NAS.
The CLI, registry and gateway live in the selected container. Run `features`,
`device list`, `gateway status`, then `--camera ALIAS info` to check the real
device path. Gateway health alone does not establish camera access.

Snapshot files returned by the CLI are container paths. Save under
`/data/cache/reolink-cli/snapshots/`, then use the selected Docker context and
`docker cp CONTAINER:/data/cache/reolink-cli/snapshots/FILE LOCAL_FILE` before
opening or attaching that authorized image. Never copy the entire config
directory or credential key into the agent workspace.

## Agent inside a separate container

The repository's `container/agent.Dockerfile` adds the verified CLI and this
skill to a version-pinned agent image. The OpenClaw Compose overlay connects
it to the existing gateway network without a Docker socket. The CLI wrapper
uses `/data/config` read-only, `/data/cache` for media and
`/tmp/reolink-agent-state` for temporary CLI state; these XDG overrides affect
only the camera CLI process.

`REOLINK_GATEWAY_ADDR` points to `reolink:9000`. Do not replace it with
`127.0.0.1`, which would address the agent container itself. Run normal
`reolink-cli` commands; do not invoke Docker inside the agent container and do
not start a second gateway. Camera registration and image upgrades belong in
the operator's deployment terminal.

The gateway and agent must use the same non-root UID/GID, so encrypted
credentials remain mode 0600. A permission error is not a reason to make
credential files world-readable. This is a trusted personal-agent deployment:
the agent can read/decrypt credentials for the cameras registered in its shared
configuration. Use a dedicated deployment/registry for each trust boundary.

For OpenClaw, save a requested snapshot under
`/data/cache/reolink-cli/snapshots/FILE.jpg`. The default overlay also exposes
that cache as a read-only workspace directory at
`/home/node/.openclaw/workspace/reolink-media/`. The same image is available at
`reolink-media/reolink-cli/snapshots/FILE.jpg` relative to the workspace; use that
workspace path when opening/attaching the requested image. If the workspace is
customized, use its configured `REOLINK_AGENT_MEDIA_DIR` mapping.

A nested agent sandbox is another execution environment. The binary, skill,
gateway network and data mounts must exist there too. Do not disable a user's
sandbox globally or claim a Gateway-container installation covers the sandbox.

## Network and lifecycle

Public external images are LAN-only. Prefer the camera's known IP across
routers/subnets; broadcast discovery can fail even when IP login succeeds.
UID wake/discovery does not provide remote connectivity. Verify the build's `features` output
before offering remote UID access.

Keep registry and key together when backing up. Use the deployment's Compose
files/project for upgrades and retain its volume. Do not run `self-update`,
native `setup --uninstall`, or `gateway stop` from an agent to manage the image.
Before any purge, identify the exact volume and obtain the user's explicit
authorization. Physical actions and device mutations retain the main skill's
normal confirmation requirements.
