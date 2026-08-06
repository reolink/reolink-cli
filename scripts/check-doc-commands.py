#!/usr/bin/env python3
"""Run every `reolink-cli …` command that appears in the docs through the real
binary's argument parser, and report the ones it rejects.

    ./scripts/check-doc-commands.py [--cli path/to/reolink-cli] [docs-root ...]

Why this exists: the reference docs assert what the CLI accepts, and nothing
verified those assertions. An outside contributor read them against the binary
and filed six defects in one day — one of which (`detect motion set
--sensitivity 60`, valid range 1–50) this script now catches on its own. Code
has a compiler and a test suite; prose had neither.

What it can and cannot see. clap validates subcommands, flag names, and value
ranges during parsing, before any command runs — so those are checkable, and
this script checks them. It cannot see whether a documented *meaning* is right:
a bit order, a deprecation note, a claim about Windows. Those need a reader.
Reducing that second class is a docs-design job (point at `--help` instead of
restating it), not something a checker can do.

Safety: every command is passed to the binary with `--parse-only`, which makes
it validate the argument vector and exit before dispatch. Nothing a doc contains
can run.

That is not how this started, and the first version did real damage. It executed
each documented line for real and leaned on redirected config paths to make them
fail harmlessly. Two holes: explicit flags beat environment variables in clap, so
anything documented with its own `--gateway-addr` or `--camera` sailed past the
redirect; and anything needing no config at all never went near it. The docs
contain `setup --uninstall --purge`, `self-update --yes` and `gateway start
--open`. In one nineteen-minute run it uninstalled the developer's own copy,
deleted the camera registry, left a gateway listening on 0.0.0.0, and opened
thirty-nine browser tabs. The env vars below are kept as a second layer, but the
guarantee now comes from `--parse-only` — a checker must not be able to perform
what it is checking.
"""
import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

# Values a doc writes for the reader to substitute. A parse error caused by one
# of these is the doc working as intended, not a defect.
PLACEHOLDER = re.compile(r"[<>${}\[\]]|^[A-Z][A-Z0-9_-]*$|\.\.\.|…|^[~/]")

# PowerShell wrappers (`Start-Process reolink-cli -ArgumentList "…"`). A
# -CapitalWord parameter is PowerShell convention and never a Unix CLI flag, so
# it is a reliable marker that this line is not a shell command to parse.
POWERSHELL = re.compile(r"^-[A-Z]")

# Shell that lives on the same line as the command and is not part of it,
# plus the prose a doc puts after a command to explain it — a trailing
# "(recent fires)" is an annotation, not an argument.
TRAILING_SHELL = re.compile(r"\s+(?:#|&&|\|\||[&;|>]|\().*$")

FAILURE = re.compile(
    r"error: (invalid value '[^']*' for '[^']*'[^\n]*"
    r"|unexpected argument [^\n]*"
    r"|unrecognized subcommand [^\n]*"
    r"|the following required arguments[^\n]*)"
)


def commands_in(path: Path):
    """Yield commands from fenced code blocks only.

    Prose mentions a command the way it mentions anything else — inside a
    sentence, sometimes with the surrounding words attached ("Remove
    reolink-cli + reolink-gateway"). Only a fenced block is a claim that this
    exact line runs, so only a fenced block is worth checking. Scanning prose
    produced four findings, all of them the checker misreading English.
    """
    fenced = False
    for lineno, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            continue
        for m in re.finditer(r"\breolink-cli\s+([^\n|`]*)", line):
            raw = TRAILING_SHELL.sub("", m.group(1)).strip().rstrip("\\").strip()
            if raw and not raw.startswith("#"):
                yield lineno, raw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", default="reolink-cli")
    ap.add_argument("roots", nargs="*", default=["."])
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        # Second layer only. `--parse-only` is what actually keeps these
        # commands from running; see the module docstring for what happened when
        # this was the whole defence.
        env = dict(
            os.environ,
            REOLINK_CAMERAS_FILE=f"{tmp}/aliases.toml",
            REOLINK_CONFIG_FILE=f"{tmp}/config.toml",
            REOLINK_GATEWAY_ADDR="127.0.0.1:1",
            REOLINK_PASSWORD="placeholder",
        )

        # Refuse to start against a binary that predates `--parse-only`. Such a
        # binary rejects the flag, so nothing would execute — but every one of
        # the thousands of documented commands would be reported as a defect,
        # and a wall of false findings is how a checker gets switched off.
        #
        # The test is the exit status, not the wording of an error. A binary
        # that understands the flag parses `device list` and exits 0 before
        # dispatch; one that does not fails argument parsing and exits non-zero.
        # Matching on the message instead would fail *open* the moment clap
        # rephrased it — and failing open here means executing every command in
        # the documentation, which is the accident this whole change exists to
        # prevent.
        try:
            probe = subprocess.run(
                [args.cli, "--parse-only", "device", "list"],
                capture_output=True,
                text=True,
                env=env,
            )
        except (FileNotFoundError, PermissionError) as e:
            # A traceback here reads as "the checker is broken"; it usually just
            # means the tree has not been built. Say which.
            print(f"cannot run {args.cli!r}: {e}", file=sys.stderr)
            return 2
        if probe.returncode != 0:
            detail = (probe.stderr or probe.stdout or "").strip().splitlines()
            print(
                f"{args.cli} does not accept --parse-only (exit "
                f"{probe.returncode}: {detail[0] if detail else 'no output'}).\n"
                "Build the current tree first. Refusing to run: without that "
                "flag this script executes every command it finds.",
                file=sys.stderr,
            )
            return 2
        checked = skipped = 0
        findings = []
        for root in args.roots:
            for md in sorted(Path(root).rglob("*.md")):
                if "node_modules" in md.parts:
                    continue
                for lineno, cmd in commands_in(md):
                    try:
                        toks = shlex.split(cmd)
                    except ValueError:
                        skipped += 1
                        continue
                    if not toks or any(
                        PLACEHOLDER.search(t) or POWERSHELL.match(t) for t in toks
                    ):
                        skipped += 1
                        continue
                    checked += 1
                    try:
                        r = subprocess.run(
                            [args.cli, "--parse-only", *toks],
                            capture_output=True,
                            text=True,
                            timeout=20,
                            env=env,
                        )
                    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
                        if isinstance(e, FileNotFoundError):
                            print(f"cannot run {args.cli!r}", file=sys.stderr)
                            return 2
                        continue
                    hit = FAILURE.search((r.stderr or "") + (r.stdout or ""))
                    if hit:
                        findings.append((md, lineno, cmd, hit.group(1)))

    print(f"checked {checked} documented commands ({skipped} skipped as placeholders)")
    if not findings:
        print("all of them parse.")
        return 0
    print()
    for md, lineno, cmd, err in findings:
        print(f"  {md}:{lineno}")
        print(f"      {cmd}")
        print(f"      -> {err}")
    print(f"\n{len(findings)} documented command(s) the CLI rejects.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
