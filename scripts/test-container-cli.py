#!/usr/bin/env python3
"""Host launcher checks using a fake Docker boundary; no daemon or cameras required."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins/reolink-cli" if (ROOT / "plugins/reolink-cli").is_dir() else ROOT
SETUP = ROOT / "scripts/setup-container-cli.py"
spec = importlib.util.spec_from_file_location("container_cli", SETUP)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

DOCKER = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["DOCKER_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args == ["context", "show"]:
    print("nas")
    sys.exit()
assert args[:2] == ["--context", "nas"], args
args = args[2:]
if args[0] == "inspect":
    if os.environ.get("FAIL_DOCKER"):
        print("cannot connect to Docker", file=sys.stderr)
        sys.exit(1)
    if ".State.Health" in args[2]:
        print("starting" if os.environ.get("STARTING") else "healthy")
    else:
        print("false" if os.environ.get("STOPPED") else "true")
elif "wget" in args:
    calls = [json.loads(line) for line in open(os.environ["DOCKER_CALLS"])]
    if os.environ.get("STARTING") and sum("wget" in call for call in calls) == 1:
        sys.exit(1)
    print("[]" if os.environ.get("BAD_GATEWAY") else
          json.dumps({"data": {"ok": not bool(os.environ.get("FAIL_GATEWAY"))}}))
elif args[-1] == "ping":
    print(json.dumps({"ok": True, "data": {"reachable": not bool(os.environ.get("FAIL_TCP"))}}))
elif "--version" in args:
    print("reolink-cli 0.20.0 (external)")
elif args[-1] == "info":
    code = int(os.environ.get("CAMERA_EXIT", "0"))
    print(json.dumps({"ok": code == 0}))
    sys.exit(code)
else:
    data = "" if os.environ.get("NO_READ") else sys.stdin.read()
    print(json.dumps({"args": args, "stdin": data}))
    sys.exit(23)
'''


@unittest.skipIf(os.name == "nt", "POSIX executable stubs and terminal checks")
class ContainerCliTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="container cli ")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        docker = self.root / "docker"
        docker.write_text(DOCKER)
        docker.chmod(0o755)
        self.bin = self.root / "installed bin"
        self.log = self.root / "calls.jsonl"
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
                        DOCKER_CALLS=str(self.log))
        self.env.pop("DOCKER_HOST", None)
        self.env.pop("DOCKER_CONTEXT", None)

    def run_setup(self, action="install", **env):
        return subprocess.run([sys.executable, str(SETUP), action, "--bin-dir", str(self.bin)],
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=30)

    def test_installed_cli_pins_context_preserves_io_and_works_without_checkout(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SKIP Camera", result.stdout)
        self.assertIn('"mcpServers"', result.stdout)
        wrapper = self.bin / "reolink-cli"
        result = subprocess.run([str(wrapper), "--camera", "front door", "mcp-server"],
                                input="fixture input\n", capture_output=True, text=True,
                                cwd="/", env=self.env, timeout=30)
        self.assertEqual(result.returncode, 23)
        self.assertEqual(json.loads(result.stdout), {
            "args": ["exec", "-i", "reolink-cli-reolink-1", "reolink-cli",
                     "--camera", "front door", "mcp-server"], "stdin": "fixture input\n"})
        self.assertEqual(self.run_setup().returncode, 0, "identical install is idempotent")

    def test_preserves_existing_native_file_and_symlink(self):
        self.bin.mkdir()
        native = self.bin / "reolink-cli"
        native.write_text("native binary fixture")
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertEqual(native.read_text(), "native binary fixture")
        native.unlink()
        target = self.root / "native"
        target.write_text("keep")
        native.symlink_to(target)
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertEqual(target.read_text(), "keep")

    def test_diagnostics_fail_before_installing(self):
        for env, message in [({"FAIL_DOCKER": "1"}, "Docker/container"),
                             ({"STOPPED": "1"}, "Container is stopped"),
                             ({"FAIL_GATEWAY": "1"}, "Gateway"),
                             ({"BAD_GATEWAY": "1"}, "Gateway: invalid health response"),
                             ({"DOCKER_HOST": "tcp://example.invalid:2376"}, "pass --context NAME")]:
            with self.subTest(env=env):
                result = self.run_setup(**env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(self.bin.exists())

    def test_camera_check_distinguishes_network_auth_and_success(self):
        command = [sys.executable, str(SETUP), "check", "--camera", "front door"]
        for code, message in [(1, "alias"), (2, "routing"), (3, "authentication failed"), (0, "PASS Camera")]:
            with self.subTest(code=code):
                result = subprocess.run(command, env=dict(self.env, CAMERA_EXIT=str(code)),
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0 if code == 0 else 1)
                self.assertIn(message, result.stdout + result.stderr)
                self.assertNotIn("SKIP Camera", result.stdout)
        self.assertFalse(self.bin.exists(), "check never installs")

    def test_host_probe_does_not_confuse_tcp_with_auth_or_zero_exit_with_success(self):
        command = [sys.executable, str(SETUP), "check", "--host", "192.0.2.123:9000"]
        for failed in [False, True]:
            env = dict(self.env)
            if failed:
                env["FAIL_TCP"] = "1"
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, int(failed))
            if failed:
                self.assertIn("Camera TCP: unreachable", result.stderr)
            else:
                self.assertIn("PASS Camera TCP", result.stdout)
                self.assertIn("SKIP authentication", result.stdout)

    def test_starting_container_waits_for_gateway(self):
        result = self.run_setup("check", STARTING="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS Gateway", result.stdout)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(sum("wget" in call for call in calls), 2)

    def test_terminal_password_prompt_gets_tty_but_mcp_never_does(self):
        import pty
        self.assertEqual(self.run_setup().returncode, 0)
        commands = [[str(self.bin / "reolink-cli")],
                    ["sh", str(PLUGIN / "scripts/run-cli.sh")]]
        for command in commands:
            for argument, expected in [("device", "-it"), ("mcp-server", "-i")]:
                master, slave = pty.openpty()
                try:
                    env = dict(self.env, NO_READ="1", REOLINK_CONTAINER="reolink-cli-reolink-1",
                               REOLINK_DOCKER_CONTEXT="nas")
                    env.pop("REOLINK_CLI_BIN", None)
                    subprocess.run(command + [argument], stdin=slave, stdout=slave,
                                   stderr=subprocess.PIPE, env=env, timeout=30)
                finally:
                    os.close(slave)
                    os.close(master)
                call = json.loads(self.log.read_text().splitlines()[-1])
                self.assertEqual(call[:4], ["--context", "nas", "exec", expected])


class WindowsLauncherTests(unittest.TestCase):
    def test_names_cannot_inject_commands_and_wrapper_preserves_exit_code(self):
        for value in ["x & whoami", "%PATH%", "x\ny", "-x", 'x"y']:
            with self.assertRaises(argparse.ArgumentTypeError):
                setup.docker_name(value)
        body = setup.launcher("nas", "reolink-cli-reolink-1", windows=True)
        self.assertIn("docker --context nas exec -i reolink-cli-reolink-1 reolink-cli %*", body)
        self.assertIn("exit /b %ERRORLEVEL%", body)


@unittest.skipUnless(shutil.which("docker"), "Docker CLI required to validate Compose merging")
class AgentComposeTests(unittest.TestCase):
    def test_openclaw_shared_cli_network_mode_survives_overlay(self):
        base = {"services": {
            "openclaw-gateway": {"image": "openclaw:fixture", "command": ["node", "openclaw.mjs", "gateway"],
                                 "environment": {"HOME": "/home/node"}, "volumes": ["state:/home/node/.openclaw"]},
            "openclaw-cli": {"image": "openclaw:fixture", "network_mode": "service:openclaw-gateway",
                             "entrypoint": ["node", "openclaw.mjs"]}}, "volumes": {"state": {}}}
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp) / "compose.json"
            file.write_text(json.dumps(base))
            result = subprocess.run(["docker", "compose", "-f", str(file), "-f", str(ROOT / "compose.openclaw.yaml"),
                                     "config", "--format", "json"], capture_output=True, text=True,
                                    env=dict(os.environ, REOLINK_AGENT_IMAGE="openclaw-reolink:fixture"), timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            services = json.loads(result.stdout)["services"]
            self.assertEqual(services["openclaw-cli"]["network_mode"], "service:openclaw-gateway")
            self.assertNotIn("networks", services["openclaw-cli"])
            gateway = services["openclaw-gateway"]
            self.assertEqual(gateway["command"], ["node", "openclaw.mjs", "gateway"])
            self.assertEqual(gateway["environment"]["HOME"], "/home/node")
            mounts = {item["target"]: item for item in gateway["volumes"]}
            self.assertTrue(mounts["/data/config"]["read_only"])
            self.assertFalse(mounts["/data/cache"].get("read_only", False))
            self.assertIn("/home/node/.openclaw", mounts)
            self.assertIn("reolink", gateway["networks"])


if __name__ == "__main__":
    unittest.main()
