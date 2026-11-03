#!/usr/bin/env python3
"""Check a local/NAS deployment and install a Docker-backed CLI without replacing native binaries."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time


def docker_name(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", value):
        raise argparse.ArgumentTypeError("use a Docker name containing letters, digits, _, . or -")
    return value


def checked(command, label, timeout=20):
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                encoding="utf-8", errors="replace", timeout=timeout)
    except FileNotFoundError:
        raise RuntimeError("Docker CLI is missing; install it on this computer") from None
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"{label}: timed out; check the Docker context/SSH connection") from None
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        hint = ""
        if label == "Camera":
            hint = {1: "Check the camera alias in this container's registry.",
                    2: "Check camera IP, routing, firewall and device availability.",
                    3: "Camera authentication failed; update its saved credentials."}.get(
                        result.returncode, "Check the device/protocol error below.")
        raise RuntimeError(f"{label}: failed. {hint}\n{detail}".strip())
    return result.stdout.strip()


def check(context, container, camera=None, host=None):
    docker = ["docker", "--context", context]
    running = checked(docker + ["inspect", "--format", "{{.State.Running}}", container],
                      "Docker/container")
    if running != "true":
        raise RuntimeError("Container is stopped; start the existing Compose service first")
    print(f"PASS Docker/container: {context} / {container}")
    version = checked(docker + ["exec", container, "reolink-cli", "--version"], "CLI")
    print(f"PASS CLI: {version}")
    state = checked(docker + ["inspect", "--format",
                              "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}",
                              container], "Gateway readiness")
    deadline = time.monotonic() + 15
    while True:
        try:
            health = checked(docker + ["exec", container, "wget", "-qO-", "-T", "5",
                                      "http://127.0.0.1:9000/api/health"], "Gateway")
            break
        except RuntimeError:
            if state != "starting" or time.monotonic() >= deadline:
                raise
            time.sleep(0.5)
    try:
        healthy = json.loads(health)["data"]["ok"] is True
    except (ValueError, KeyError, TypeError):
        raise RuntimeError("Gateway: invalid health response") from None
    if not healthy:
        raise RuntimeError("Gateway: unexpected health response")
    print("PASS Gateway: healthy inside the container")
    if camera:
        checked(docker + ["exec", container, "reolink-cli", "--camera", camera, "info"],
                "Camera", timeout=90)
        print(f"PASS Camera: {camera} info succeeded (network and authentication)")
    elif host:
        result = json.loads(checked(docker + ["exec", container, "reolink-cli", "--host", host, "ping"],
                                    "Camera TCP"))
        if (not isinstance(result, dict) or not result.get("ok")
                or not isinstance(result.get("data"), dict) or result["data"].get("reachable") is not True):
            raise RuntimeError("Camera TCP: unreachable; check IP, port, routing and firewall")
        print(f"PASS Camera TCP: {host} reachable from the container")
        print("SKIP authentication: register the camera, then check --camera ALIAS")
    else:
        print("SKIP Camera: pass --camera ALIAS after registering a camera; LAN is not yet verified")


def launcher(context, container, windows=False):
    docker = ["docker", "--context", context, "exec"]
    if windows:
        # shortcut: no TTY auto-detection in cmd.exe, use docker exec -it for initial password prompts.
        return "@echo off\r\n" + " ".join(docker + ["-i", container, "reolink-cli", "%*"]) + \
            "\r\nexit /b %ERRORLEVEL%\r\n"
    return ("#!/bin/sh\nset -eu\n"
            "tty_flag=-i\n"
            "if [ -t 0 ] && [ -t 1 ]; then tty_flag=-it; fi\n"
            "for arg do\n"
            '  if [ "$arg" = mcp-server ]; then tty_flag=-i; fi\n'
            "done\n"
            f'exec {shlex.join(docker)} "$tty_flag" {shlex.quote(container)} reolink-cli "$@"\n')


def install(context, container, directory):
    directory = directory.expanduser().resolve()
    directory.mkdir(parents=True, exist_ok=True)
    windows = os.name == "nt"
    destination = directory / ("reolink-cli.cmd" if windows else "reolink-cli")
    body = launcher(context, container, windows)
    for name in ("reolink-cli", "reolink-cli.exe", "reolink-cli.cmd", "reolink-cli.bat", "reolink-cli.ps1"):
        candidate = directory / name
        if candidate.exists() or candidate.is_symlink():
            if candidate != destination or candidate.is_symlink() or candidate.read_bytes() != body.encode():
                raise RuntimeError(f"Refusing to replace {candidate}; select a separate --bin-dir")
    if not destination.exists():
        with destination.open("x", encoding="utf-8", newline="") as output:
            output.write(body)
        destination.chmod(0o755)
    print(f"Installed: {destination}")
    if windows:
        print(f'Add this directory to the client PATH: {directory}')
        mcp = {"command": "docker", "args": ["--context", context, "exec", "-i",
                                               container, "reolink-cli", "mcp-server"]}
    else:
        print(f'For this terminal: export PATH={shlex.quote(str(directory))}:"$PATH"')
        mcp = {"command": str(destination), "args": ["mcp-server"]}
    print("Add the directory to your shell/client PATH and reopen the client, or use this absolute MCP entry:")
    print(json.dumps({"mcpServers": {"reolink": mcp}}, indent=2))
    print("Container updates keep working when the name/context stay the same. "
          "Use Compose to upgrade/stop the deployment, not CLI self-update/gateway stop.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "check"))
    parser.add_argument("--context", type=docker_name, help="Existing Docker context; current context if omitted")
    parser.add_argument("--container", type=docker_name, default="reolink-cli-reolink-1",
                        help="Stable container name, not its replaceable ID")
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--camera", help="Registered alias to test with the read-only info command")
    target.add_argument("--host", help="Known camera IP[:port] for a TCP-only check without credentials")
    parser.add_argument("--bin-dir", type=Path, default=Path.home() / ".local/reolink-container/bin")
    args = parser.parse_args()
    try:
        if not args.context and os.environ.get("DOCKER_HOST") and not os.environ.get("DOCKER_CONTEXT"):
            raise RuntimeError("DOCKER_HOST is set; pass --context NAME for a named Docker context "
                               "so the installed entry pins the intended Docker host")
        context = docker_name(args.context or checked(["docker", "context", "show"], "Docker context"))
        check(context, args.container, args.camera, args.host)
        if args.action == "install":
            install(context, args.container, args.bin_dir)
    except (RuntimeError, OSError, ValueError, argparse.ArgumentTypeError) as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
