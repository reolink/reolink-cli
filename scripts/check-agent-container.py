#!/usr/bin/env python3
"""Validate a separate agent client against an existing Reolink Compose deployment."""
import argparse
import json
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-image", required=True)
    parser.add_argument("--gateway-container", required=True)
    parser.add_argument("--camera", help="Optional registered camera for a real info request")
    parser.add_argument("--snapshot", action="store_true", help="Capture one authorized camera image")
    parser.add_argument("--openclaw", action="store_true", help="Also check OpenClaw skill eligibility")
    args = parser.parse_args()
    if args.snapshot and not args.camera:
        parser.error("--snapshot requires --camera")
    docker = ["docker"]

    def run(command, **kwargs):
        return subprocess.run(command, check=True, capture_output=True, timeout=90, **kwargs)

    gateway = json.loads(run(docker + ["inspect", args.gateway_container]).stdout)[0]
    assert gateway["State"]["Running"], "start the gateway first"
    volumes = [item for item in gateway["Mounts"] if item["Destination"] == "/data"]
    assert len(volumes) == 1 and volumes[0]["Type"] == "volume", "check requires the Compose named data volume"
    network = gateway["HostConfig"]["NetworkMode"]
    assert network in gateway["NetworkSettings"]["Networks"] and network not in ("host", "none"), "use bridge mode for this agent example"
    volume = volumes[0]["Name"]
    agent = "reolink-agent-check-" + uuid.uuid4().hex[:10]
    fixture = "/data/cache/reolink-cli/." + agent

    def client(*command, **kwargs):
        return run(docker + ["exec", "-i", agent, *command], **kwargs)

    try:
        run(docker + ["run", "-d", "--name", agent, "--network", network,
                      "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
                      "--tmpfs", "/tmp:mode=1777",
                      "--mount", f"type=volume,src={volume},dst=/data/config,readonly,volume-subpath=config",
                      "--mount", f"type=volume,src={volume},dst=/data/cache,volume-subpath=cache",
                      "--mount", f"type=volume,src={volume},dst=/tmp/reolink-media,readonly,volume-subpath=cache",
                      "-e", "REOLINK_GATEWAY_ADDR=reolink:9000",
                      "-e", "OPENCLAW_STATE_DIR=/tmp/openclaw-state",
                      "-e", "OPENCLAW_CONFIG_PATH=/tmp/openclaw.json",
                      "--entrypoint", "sh", args.agent_image, "-c", "while :; do sleep 3600; done"])
        uid = client("id", "-u").stdout.strip()
        assert uid != b"0", "agent must not run as root"
        gateway_uid = run(docker + ["exec", args.gateway_container, "id", "-u"]).stdout.strip()
        assert uid == gateway_uid, "build the gateway with the agent UID; do not loosen credential permissions"
        gid = client("id", "-g").stdout.strip()
        assert gid == run(docker + ["exec", args.gateway_container, "id", "-g"]).stdout.strip(), "gateway and agent GIDs must match"
        client("sh", "-c", "test ! -e /var/run/docker.sock")
        denied = subprocess.run(docker + ["exec", agent, "touch", "/data/config/.agent-write-check"], capture_output=True)
        assert denied.returncode != 0, "agent configuration must be read-only"
        assert json.loads(client("reolink-cli", "device", "list").stdout)["ok"]
        permissions = client("sh", "-c",
                             'for file in /data/config/reolink-cli/aliases.toml /data/config/reolink-cli/credentials.key; do '
                             'if [ -f "$file" ]; then stat -c %a "$file"; fi; done').stdout.splitlines()
        assert permissions and all(mode == b"600" for mode in permissions), "keep camera credentials mode 0600"
        client("sh", "-c", 'umask 077; mkdir -p /data/cache/reolink-cli; cat > "$1"',
               "sh", fixture, input=b"agent-cache-fixture\n")
        assert run(docker + ["exec", args.gateway_container, "cat", fixture]).stdout == b"agent-cache-fixture\n"
        assert client("cat", fixture.replace("/data/cache", "/tmp/reolink-media", 1)).stdout == b"agent-cache-fixture\n"
        print("PASS agent: non-root UID/GID match, read-only credentials, shared cache, no Docker socket")
        if args.openclaw:
            config = {"agents": {"defaults": {"workspace": "/tmp"}},
                      "skills": {"load": {"extraDirs": ["/opt/reolink/skills"]}}}
            client("sh", "-c", "cat > /tmp/openclaw.json", input=json.dumps(config).encode())
            response = client("node", "/app/openclaw.mjs", "skills", "info", "reolink-cli", "--json")
            skill = json.loads(response.stdout)
            assert skill["eligible"] is True, "OpenClaw did not admit the skill"
            assert skill["name"] == "reolink-cli"
            assert skill["baseDir"] == "/opt/reolink/skills/reolink-cli", "another skill is shadowing this image's skill"
            print("PASS OpenClaw: reolink-cli skill loaded and eligible in the actual agent image")
        if args.camera:
            info = json.loads(client("reolink-cli", "--camera", args.camera, "info").stdout)
            assert info["ok"] is True
            print("PASS real camera: agent CLI -> separate gateway -> camera info")
        else:
            print("SKIP real camera: supply --camera ALIAS to verify device access")
        if args.snapshot:
            snapshot = fixture + ".jpg"
            response = json.loads(client("reolink-cli", "--camera", args.camera,
                                         "snapshot", "--file", snapshot).stdout)
            assert response["ok"] is True
            data = client("cat", snapshot).stdout
            assert data[:2] == b"\xff\xd8" and data[-2:] == b"\xff\xd9", "invalid JPEG"
            assert run(docker + ["exec", args.gateway_container, "cat", snapshot]).stdout == data
            assert client("cat", snapshot.replace("/data/cache", "/tmp/reolink-media", 1)).stdout == data
            print(f"PASS real snapshot: {len(data)} JPEG bytes readable in both containers")
    finally:
        inspection = subprocess.run(docker + ["inspect", agent], capture_output=True)
        if inspection.returncode == 0:
            subprocess.run(docker + ["exec", agent, "rm", "-f", fixture, fixture + ".jpg"], capture_output=True)
            run(docker + ["rm", "-f", agent])


if __name__ == "__main__":
    main()
