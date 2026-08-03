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

## Download verification: what it proves, and what it does not

Stated plainly because the distinction is easy to overstate, and we did overstate
it once.

Every download path — `install.sh`, `install.ps1`, and `reolink-cli
self-update` — verifies the archive against `checksums/<tag>.sha256` committed to
this repository's default branch, and fails closed if that file is missing, has
no entry for the archive, or does not match. The checksum source is **pinned** to
`reolink/reolink-cli`; `REOLINK_REPO` and `REOLINK_UPDATE_REPO` change where the
archive is fetched from, never where it is checked against. A mirror serving
identical bytes passes; a fork serving its own build does not.

**This is integrity, not authenticity.** It proves the archive is the one whose
hash was committed. It does not prove who built it. The checksum is written by
the same release process that produces the archive, so both share one trust root:

| threat | covered |
|---|---|
| release asset replaced after publication | yes — the anchor is not in the release |
| `REOLINK_REPO` pointed at an attacker's repository | yes — the checksum is pinned |
| archive corrupted in transit | yes |
| compromised maintainer account committing a matching archive + checksum | **no** |
| compromised build machine | **no** |

Closing the last two requires a signature or attestation anchored outside the
release pipeline. We do not have one yet, and we would rather say so here than
imply a guarantee the code does not make. GitHub build attestation is not
currently available to this project because releases are not built in GitHub
Actions — one workspace dependency lives outside this repository, so an Actions
runner cannot build it.

If you verify downloads by hand, use the committed checksum file, not the
`SHA256SUMS` attached to the release — see
[Verifying a download](README.md#verifying-a-download).

### If verification fails

The installers refuse and change nothing. A truncated or proxy-mangled download
is the ordinary cause, so one retry is reasonable.

If it fails again, **report it rather than working around it**. Pointing
`REOLINK_REPO` at another repository or downloading the archive by hand both
skip the check that just fired, which is the opposite of what a failed integrity
check should lead you to do. Please include the expected and actual hashes, the
tag, and the asset name — that is enough for us to tell a bad mirror from
something worse.

A missing-checksum failure (`no committed checksum file for <tag>`) usually
means a release was published before its checksums were synced, which is our
bug, not an attack. It is still worth reporting: with the installers failing
closed, that window breaks every one-line install until we fix it.

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
