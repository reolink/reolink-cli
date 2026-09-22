# Contributing

## What lives here

This repository is the **distribution** for `reolink-cli`: the agent skill,
the plugin manifests, the docs, and the installers. The Rust source for the
`reolink-cli` and `reolink-gateway` binaries is **not** in this repository —
released binaries are attached to
[GitHub Releases](https://github.com/reolink/reolink-cli/releases).

So you can change, and we welcome PRs for:

- `skills/reolink-cli/` — the agent skill and its reference docs
- `commands/`, `mcp/` — slash commands and MCP wiring
- `README.md`, `docs/`, and the other top-level docs
- `examples/` — automations you built, see below
- `install.sh` / `install.ps1`
- the plugin manifests (`.claude-plugin/`, `.codex-plugin/`, …)

Anything that needs a code change in the binaries — a new subcommand, a
protocol fix, different JSON output — should be filed as an
[issue](https://github.com/reolink/reolink-cli/issues) describing the behaviour
you want. We implement it upstream and it arrives in the next release.

## Automation recipes

People automate `reolink-cli` and want to send back what they built.
`examples/` is where that lands and a pull request is the channel — but which
of three things you have decides whether a pull request is the right move at
all.

1. **A rule file** — `events monitor` TOML, no shell. Send it. It runs on the
   engine that already ships with the CLI, so there is nothing to execute and
   nothing for a reader to audit.
2. **A script that works around a missing command.** Open an
   [issue](https://github.com/reolink/reolink-cli/issues) instead, and say which
   primitive you had to hand-roll. This is not a brush-off, it is the faster
   route: the flashing spotlight everyone wanted was a PowerShell loop toggling
   the light on and off, and `light spotlight blink --count 3` exists because
   someone showed us that loop. The script disappeared in the next release. A
   recipe written around a gap outlives the gap, and everybody who copies it
   inherits the workaround.
3. **Glue we cannot build in** — Home Assistant, Frigate, a NAS, cron on your
   own box. That one is genuinely yours. Send it.

A recipe is a directory, `examples/<name>/`, holding the rule file or script and
a `README.md` that says what it does, what you ran it against (camera model and
firmware), and what a real run printed. Nothing under `examples/` is fetched by
the installer, executed by the CLI, or shipped in a release, and none of it is
covered by the compatibility promise the CLI itself makes: the contributor
maintains it, and one that stops working gets fixed by a pull request or
removed.

## Before you open a PR

- **Run what you document.** Most defects we have fixed here were commands in
  the docs that had never been executed — a flag that did not exist, a
  subcommand that had been renamed. If you touch an example, run it and paste
  the output in the PR.
- **Keep manifests in step.** The version appears in seven manifests, plus a
  CHANGELOG heading and the release's `checksums/<tag>.sha256`. (It was nine:
  the README badge is a live shields.io release lookup now, and the skill's
  example output no longer names a version — copies that cannot go stale
  beat copies that are checked.) They must all agree with the published release. Do
  not hand-edit a version to something no release uses.

  ```bash
  ./scripts/check-version-sync.sh              # do they agree with the latest release?
  ./scripts/check-version-sync.sh --self       # do they agree with each other?
  ./scripts/check-version-sync.sh --set 0.11.0 # rewrite all seven, then check
  ```

  CI runs `--self` on every pull request, so a hand-edit that misses one of
  the manifests fails there. It runs the release comparison on `release:
  published` and daily — that one catches what a local script cannot, where a
  release ships and nobody touches this repository at all.

  Doing this by hand has failed three times: once the plugin manifests were left
  behind, once the whole repository stayed a version back while the release was
  already published — readers saw a stale badge over a newer download — and once
  more while cutting 0.10.3. Use `--set`; it writes every location from one list
  and then checks its own work, so a location it could not match is reported
  rather than skipped. That history is also why the badge stopped being a copy
  at all.

  `--set` does not touch `CHANGELOG.md`. That entry needs release notes a script
  cannot write, so the check reports it as missing until you write it.
- **Never commit real data.** No camera passwords, tokens, UIDs, serial
  numbers, private IPs, or footage — in code, docs, examples or screenshots.
  Use placeholders such as `192.168.1.42` and `<camera-password>`.
- **Installers are security-sensitive.** They fetch and run executables. Any
  change there must keep the SHA256 verification, must not add `sudo`, and must
  not widen what gets deleted or overwritten. Say in the PR what you tested.

## Commit and PR style

Conventional-commit subjects (`fix:`, `docs:`, `chore:`) and a body that says
**what was wrong**, not just what you changed. If you fixed something, state how
you verified it.

## Security issues

Do not open a PR or a public issue for a vulnerability — see
[SECURITY.md](SECURITY.md).
