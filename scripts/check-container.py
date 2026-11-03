#!/usr/bin/env python3
"""Exercise a built image in a disposable Compose project; never contact cameras."""
import argparse
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, help="Locally built image to test")
    parser.add_argument("--agent-image", help="Optional separate CLI client image for agent mount/network checks")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent

    def run(command, **kwargs):
        return subprocess.run(command, check=True, capture_output=True, timeout=60, **kwargs)

    image = json.loads(run(["docker", "image", "inspect", args.image]).stdout)[0]
    assert image["Config"]["User"].split(":")[0] not in ("", "0", "root"), "image must run without root"
    with tempfile.TemporaryDirectory(prefix="reolink-container-") as scratch:
        override = Path(scratch) / "compose.json"
        override.write_text(json.dumps({"services": {"reolink": {
            "image": args.image, "platform": "linux/" + image["Architecture"],
        }}}))
        compose = ["docker", "compose", "-p", "reolink-smoke-" + uuid.uuid4().hex[:10],
                   "-f", str(root / "compose.yaml"), "-f", str(override)]
        container = ""
        wrapper = Path(scratch) / "bin/reolink-cli"

        def cli(*arguments, **kwargs):
            return run([str(wrapper), *arguments], **kwargs).stdout

        def ready():
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                result = subprocess.run(
                    ["docker", "exec", container, "wget", "-qO-",
                     "http://127.0.0.1:9000/api/health"], capture_output=True)
                if result.returncode == 0:
                    assert json.loads(result.stdout)["data"]["ok"] is True
                    return
                time.sleep(0.5)
            raise AssertionError("gateway did not become ready")

        try:
            run(compose + ["config", "--quiet"])
            run(compose + ["up", "-d", "--no-build", "reolink"])
            container = run(compose + ["ps", "-q", "reolink"]).stdout.decode().strip()
            ready()
            name = run(["docker", "inspect", "--format", "{{.Name}}", container]).stdout.decode().strip().lstrip("/")
            setup = [sys.executable, str(root / "scripts/setup-container-cli.py"),
                     "--container", name, "--bin-dir", str(wrapper.parent)]
            run(setup + ["install"])
            assert "external" in cli("--version").decode()
            inspection = json.loads(run(["docker", "inspect", container]).stdout)[0]
            assert not inspection["HostConfig"]["PortBindings"], "no host ports by default"
            assert inspection["HostConfig"]["ReadonlyRootfs"] is True

            cli("device", "add", "container-smoke", "--host", "192.0.2.123:9000",
                "--user", "admin", "--password-stdin", input=b"fixture-password\n")
            registry = run(["docker", "exec", container, "cat",
                            "/data/config/reolink-cli/aliases.toml"]).stdout
            assert b"fixture-password" not in registry
            key = run(["docker", "exec", container, "sha256sum",
                       "/data/config/reolink-cli/credentials.key"]).stdout
            permissions = run(["docker", "exec", container, "stat", "-c", "%a",
                               "/data/config/reolink-cli/aliases.toml",
                               "/data/config/reolink-cli/credentials.key"]).stdout
            assert permissions.splitlines() == [b"600", b"600"]
            if args.agent_image:
                result = run([sys.executable, str(root / "scripts/check-agent-container.py"),
                              "--agent-image", args.agent_image, "--gateway-container", container])
                print(result.stdout.decode(), end="")
            # Synthetic media proves file transfer without capturing private camera footage.
            fixture = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=")
            media = "/data/cache/reolink-cli/snapshots/container-smoke.png"
            run(["docker", "exec", "-i", container, "sh", "-c",
                 'umask 077; mkdir -p /data/cache/reolink-cli/snapshots; cat > "$1"',
                 "sh", media], input=fixture)
            requests = [
                {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                    "protocolVersion": "2025-11-25", "capabilities": {},
                    "clientInfo": {"name": "container-smoke", "version": "1"}}},
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
            ]
            output = cli("mcp-server", input=("\n".join(map(json.dumps, requests)) + "\n").encode())
            responses = [json.loads(line) for line in output.splitlines()]
            assert "error" not in responses[0]
            tools = responses[1]["result"]["tools"]
            assert any(tool["name"] == "camera_snapshot" for tool in tools)

            run(compose + ["up", "-d", "--force-recreate", "--no-build", "reolink"])
            container = run(compose + ["ps", "-q", "reolink"]).stdout.decode().strip()
            ready()
            assert b"container-smoke" in cli("device", "list")
            assert key == run(["docker", "exec", container, "sha256sum",
                               "/data/config/reolink-cli/credentials.key"]).stdout
            copied = Path(scratch) / "copied.png"
            run(["docker", "cp", container + ":" + media, str(copied)])
            assert copied.read_bytes() == fixture
            print(f"PASS {image['Architecture']}: gateway, external flavor, container launcher, "
                  f"MCP ({len(tools)} tools), encrypted registry/key persistence, media copy")
        except Exception:
            logs = subprocess.run(compose + ["logs", "--tail", "30"], capture_output=True)
            print(logs.stdout.decode(errors="replace"))
            raise
        finally:
            subprocess.run(compose + ["down", "--volumes", "--remove-orphans"],
                           capture_output=True, check=True)


if __name__ == "__main__":
    main()
