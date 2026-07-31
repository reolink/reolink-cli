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

Safety: commands run against TEST-NET-1 (192.0.2.0/24, unroutable by RFC 5737)
with the gateway pointed at a closed port and config/registry paths redirected
into a temp dir, so a command that parses cleanly fails at the first connection
attempt without touching a device or the real config.
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
        env = dict(
            os.environ,
            REOLINK_CAMERAS_FILE=f"{tmp}/aliases.toml",
            REOLINK_CONFIG_FILE=f"{tmp}/config.toml",
            REOLINK_GATEWAY_ADDR="127.0.0.1:1",
            REOLINK_PASSWORD="placeholder",
        )
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
                            [args.cli, *toks],
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
