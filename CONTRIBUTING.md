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
- `install.sh` / `install.ps1`
- the plugin manifests (`.claude-plugin/`, `.codex-plugin/`, …)

Anything that needs a code change in the binaries — a new subcommand, a
protocol fix, different JSON output — should be filed as an
[issue](https://github.com/reolink/reolink-cli/issues) describing the behaviour
you want. We implement it upstream and it arrives in the next release.

## Before you open a PR

- **Run what you document.** Most defects we have fixed here were commands in
  the docs that had never been executed — a flag that did not exist, a
  subcommand that had been renamed. If you touch an example, run it and paste
  the output in the PR.
- **Keep manifests in step.** The version appears in several manifests; they
  must agree. Do not hand-edit a version to something no release uses.
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
