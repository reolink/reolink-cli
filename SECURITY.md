# Security Policy

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue, and
do not describe the problem in a pull request.

Use GitHub's private reporting:
**[Report a vulnerability](https://github.com/reolink/reolink-cli/security/advisories/new)**
(also reachable from the repository's Security tab). The report is visible only
to maintainers, and the discussion stays on the advisory until a fix ships.

If that page is unavailable to you, contact
[Reolink support](https://support.reolink.com) and state that the report
concerns a **security issue in `reolink-cli`** so it is routed rather than
handled as a normal support ticket. Be aware that this is a consumer support
queue with no category for software vulnerabilities — prefer the link above.

Include the version (`reolink-cli --version`), your platform, and the smallest
steps that reproduce the problem.

Please do not include camera passwords, tokens, recordings, or footage in a
report. A redacted log or a description of the request is enough — see
[Safe credential handling](README.md#safe-credential-handling).

## Scope

In scope: this CLI, the local gateway it starts, the bundled agent skill and
plugin manifests, and the installers in this repository.

Out of scope: camera firmware itself and the Reolink mobile/desktop apps —
report those through [Reolink support](https://support.reolink.com).

## What this tool does by design

Knowing the intended behaviour makes it easier to tell a bug from a feature:

- The gateway listens on `127.0.0.1` by default and **refuses browser
  cross-origin requests**. Binding it to `0.0.0.0` is an explicit opt-in and
  exposes camera control to your whole LAN.
- Camera credentials are stored in the local config file with owner-only
  permissions, and the CLI refuses to read that file if it is group- or
  world-readable.
- Credentials are never placed in a URL. Session tokens carry them server-side
  and expire after 300 s of inactivity.
- `stream url --with-auth` deliberately embeds `user:password@` in the printed
  URL. That is the only command that does, and only when you ask for it.
