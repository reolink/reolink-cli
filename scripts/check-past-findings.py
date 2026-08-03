#!/usr/bin/env python3
"""Assert that defects reported against this project stay fixed.

    ./scripts/check-past-findings.py

Why this exists: one contributor (@ch-bas) has reported fifteen documentation
defects and two security findings, and a release sync silently reverted one of
his merged pull requests within an hour of it landing. Every one of these was
found by a person reading carefully. A person reading carefully does not scale,
and does not owe us a second pass.

So each finding becomes an assertion here. The rule for writing one: assert the
*property* that was wrong, never the wording of the fix. A check pinned to
today's phrasing fails the next time someone edits a sentence, and a checker
that cries wolf gets ignored — which is worse than not having it.

CHANGELOG.md is excluded from the text checks on purpose. It documents what the
bugs were, quoting the broken strings, and matching those is not a regression.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILL = ROOT / "skills" / "reolink-cli"

failures: list[tuple[str, str]] = []
checked = 0


def docs(*, include_changelog: bool = False) -> list[Path]:
    out = []
    for p in ROOT.rglob("*.md"):
        if ".git" in p.parts:
            continue
        if not include_changelog and p.name == "CHANGELOG.md":
            continue
        out.append(p)
    return out


def check(ref: str, desc: str, ok: bool, detail: str = "") -> None:
    global checked
    checked += 1
    if not ok:
        failures.append((ref, f"{desc}{(' — ' + detail) if detail else ''}"))


def absent(ref: str, desc: str, pattern: str, files=None, flags=re.I) -> None:
    """No file may contain `pattern`."""
    rx = re.compile(pattern, flags)
    hits = []
    for p in files if files is not None else docs():
        try:
            for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
                if rx.search(line):
                    hits.append(f"{p.relative_to(ROOT)}:{i}")
        except (UnicodeDecodeError, OSError):
            continue
    check(ref, desc, not hits, ", ".join(hits[:3]))


def present(ref: str, desc: str, pattern: str, path: Path, flags=re.I) -> None:
    """`path` must contain `pattern`."""
    try:
        body = path.read_text(encoding="utf-8")
    except OSError:
        check(ref, desc, False, f"{path.relative_to(ROOT)} unreadable")
        return
    check(ref, desc, bool(re.search(pattern, body, flags)), f"missing from {path.relative_to(ROOT)}")


# ---------------------------------------------------------------- documentation
absent("#4", "no 'while this repository is private' install notes",
       r"while this repository is private")

# The fix was removing the *instruction*. AGENTS.md still names the variable in
# a sentence saying it does not exist, which is the fix, not the bug — so match
# an assignment, not the bare name.
absent("#12", "uninstall docs never tell anyone to set REOLINK_PURGE",
       r"(\$env:)?REOLINK_PURGE\s*=")

# `~/.cache/reolink/` was wrong; `~/.cache/reolink-cli/` is right. The negative
# lookahead is what keeps this from matching the correct path.
absent("#13", "no reference to the non-existent ~/.cache/reolink/ directory",
       r"\.cache/reolink(?!-cli)\b")

absent("#14", "agents are not sent to a version: frontmatter SKILL.md lacks",
       r"version:\s*frontmatter|frontmatter.*\bversion:")

absent("#29", "no unqualified pkill that would kill every install's gateway",
       r"pkill\s+-f\s+[\"']?reolink-gateway[\"']?\s*$")

absent("#30", "no dangling '--version should match --version'",
       r"--version should match --version")

absent("#43", "no 'macos' asset token — published archives say 'darwin'",
       r"reolink-cli-[^\s`]*-macos-")

# Match an instruction, not co-occurrence: the README now explains at length
# that Windows does NOT self-update, and a proximity match flags that as the bug
# it describes.
absent("#41", "the quick start does not tell Windows users to run self-update",
       r"on windows[^\n]{0,40}(run|use)\s+`?reolink-cli self-update",
       files=[ROOT / "README.md"])

# #44 — the bitmap is Sunday-first. Documenting it Monday-first silently shifts
# every schedule by a day, which is why this one mattered more than it looked.
present("#44", "week-table documented Sunday-first", r"sun\s*=\s*bit\s*0",
        SKILL / "references" / "recording.md")
absent("#44", "week-table not documented Monday-first as current guidance",
       r"^(?![^\n]*\b(until|carried|previously|used to|was)\b)[^\n]*mon\s*=\s*bit\s*0",
       files=[SKILL / "references" / "recording.md"])

present("#45", "sensitivity range cited from --help rather than restated",
        r"read\s+the\s+accepted\s+range\s+from\s+`?--help", SKILL / "references" / "detection.md")
absent("#45", "motion sensitivity never documented as 0-100",
       r"sensitivity[^\n]{0,40}0\s*[-–]\s*100|0\s*[-–]\s*100[^\n]{0,40}sensitivity",
       files=[SKILL / "references" / "detection.md"])

present("#46", "gateway-http documents /api/preview/video",
        r"/api/preview/video", SKILL / "references" / "gateway-http.md")

# The fix was removing a deprecated flag from an example whose own comment said
# it was deprecated. Assert the pair never reappears on adjacent lines.
def duration_next_to_deprecated() -> bool:
    for p in docs():
        try:
            lines = p.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        for i, line in enumerate(lines):
            if "deprecated" in line.lower() and "spotlight" in "\n".join(
                lines[max(0, i - 3): i + 4]
            ).lower():
                window = "\n".join(lines[max(0, i - 3): i + 4])
                if re.search(r"--duration\s+\d", window):
                    return True
    return False


check("#46", "no --duration in a spotlight example calling it deprecated",
      not duration_next_to_deprecated())

absent("#7", "no stale 'nine locations' version-copy count",
       r"nine (locations|files|places)[^\n]{0,40}version|version[^\n]{0,40}nine (locations|files|places)")

# ------------------------------------------------------------------- installers
sh = (ROOT / "install.sh").read_text(encoding="utf-8")
ps = (ROOT / "install.ps1").read_text(encoding="utf-8")

# GHSA-2r89 — the anchor lives on the default branch, not in the release.
check("GHSA-2r89", "install.sh verifies against a committed checksum file",
      "checksums/$tag.sha256" in sh)
check("GHSA-2r89", "install.ps1 verifies against a committed checksum file",
      "checksums/$tag.sha256" in ps)
# Mentioning SHA256SUMS in a comment that explains why it is not trusted is the
# fix documenting itself. Only a fetch of it is a regression.
check("GHSA-2r89", "install.sh never fetches the release-attached sums",
      not re.search(r"(-o|OutFile)[^\n]*SHA256SUMS|releases/download[^\n]*SHA256SUMS", sh))
check("GHSA-2r89", "install.ps1 never fetches the release-attached sums",
      not re.search(r"(-o|OutFile)[^\n]*SHA256SUMS|releases/download[^\n]*SHA256SUMS", ps))

# GHSA-65x2 finding 2 — the checksum source must not follow the repo override.
check("GHSA-65x2-2", "install.sh checksum URL does not interpolate $REPO",
      not re.search(r"raw\.githubusercontent\.com/\$REPO\b", sh))
check("GHSA-65x2-2", "install.ps1 checksum URL does not interpolate $Repo",
      not re.search(r"raw\.githubusercontent\.com/\$Repo\b", ps))
check("GHSA-65x2-2", "install.sh pins the checksum repo",
      re.search(r'CHECKSUM_REPO="[^"$]+/[^"$]+"', sh) is not None)
check("GHSA-65x2-2", "install.ps1 pins the checksum repo",
      re.search(r"ChecksumRepo\s*=\s*'[^'$]+/[^'$]+'", ps) is not None)

# GHSA-65x2 finding 3 — never pick the binary by searching the extracted tree.
check("GHSA-65x2-3", "install.sh does not search the tree for the binary",
      not re.search(r'^\s*src=\$\(find\s', sh, re.M))
check("GHSA-65x2-3", "install.ps1 does not search the tree for the binary",
      not re.search(r"Get-ChildItem[^\n]*-Recurse[^\n]*-Filter\s+\$exe", ps))
check("GHSA-65x2-3", "install.sh refuses absolute/.. archive members",
      "absolute or parent-directory" in sh)
check("GHSA-65x2-3", "install.ps1 refuses absolute/.. archive members",
      "absolute or parent-directory" in ps)

# The Windows hardening needs this assembly loaded on PowerShell 5.1, or the
# installer aborts before doing anything. Shipped broken once; never again.
check("GHSA-65x2-3", "install.ps1 loads System.IO.Compression.FileSystem for PS 5.1",
      "Add-Type -AssemblyName System.IO.Compression.FileSystem" in ps)

# Windows PowerShell 5.1 routes Invoke-WebRequest through the IE engine without
# this, which stalls the install before it starts (#60).
for call in re.finditer(r"Invoke-(WebRequest|RestMethod)[^\n]*", ps):
    check("#60", "every Invoke-WebRequest/RestMethod uses -UseBasicParsing",
          "-UseBasicParsing" in call.group(0), call.group(0)[:60])

# GHSA-65x2 finding 4 — do not send manual verifiers to the discredited anchor.
readme = (ROOT / "README.md").read_text(encoding="utf-8")
check("GHSA-65x2-4", "README does not recommend verifying with release SHA256SUMS",
      not re.search(r"shasum[^\n]*-c\s+SHA256SUMS", readme))

# GHSA-65x2 finding 5 / #43 — the skill's install path must not roll its own
# unverified download.
setup_md = (SKILL / "references" / "setup.md").read_text(encoding="utf-8")
check("GHSA-65x2-5", "skill setup uses install.sh rather than its own download",
      "install.sh" in setup_md and not re.search(r"tar -xzf[^\n]*\$tmp", setup_md))

# ------------------------------------------------------------------------ report
print(f"checked {checked} assertions from past reports")
if failures:
    print()
    for ref, msg in failures:
        print(f"  REGRESSED  [{ref}] {msg}")
    print()
    print(f"{len(failures)} previously-reported defect(s) are back.")
    sys.exit(1)
print("all previously-reported defects are still fixed.")
