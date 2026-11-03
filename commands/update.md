---
description: Upgrade reolink-cli + reolink-gateway to the latest release
---

**Container deployments (Docker-backed entry or `REOLINK_CONTAINER`):** update the selected published image version and recreate the Compose service with its existing data volume. Use the container recipe in the repository distribution guide; report the old/new container CLI versions. Do not run `self-update` or kill host gateways for a container deployment. Stop here after the container workflow; the steps below are for native installations.

Upgrade the installed binaries to the latest release.

1. Run the built-in updater:

   ```bash
   reolink-cli self-update --yes
   ```

   It checks the latest GitHub release, compares against the installed version,
   and — if newer — downloads the archive for this platform and replaces both
   `reolink-cli` and `reolink-gateway` in place. If already current it prints
   `already up to date` and does nothing. Stop a running gateway first
   (`pkill reolink-gateway` on Unix; `Stop-Process -Name reolink-gateway` on
   Windows) so the binary file isn't locked.

2. Report the pre- and post-upgrade version (`reolink-cli --version`).

Notes:
- `self-update` targets the public GitHub release. Set `REOLINK_UPDATE_REPO`
  (`owner/repo`) to point at a fork/mirror, or `GITHUB_TOKEN` for a private repo.
- Windows self-update is not wired (it fetches `.tar.gz`); on Windows, download
  the latest `...-windows-x86_64.zip` from the Releases page and extract `bin\`
  over the installed copy, or re-run `install.ps1` from a fresh tarball.
- Re-run `reolink-cli completions …` after upgrading if you use shell completion.
