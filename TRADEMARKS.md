# Trademarks

"Reolink" and the Reolink logo are trademarks of Reolink Innovation Limited.

The [Apache 2.0 licence](LICENSE) on this repository grants rights to the
**code and documentation**. It does **not** grant any right to use Reolink's
name, logo, or product images — Apache 2.0 says so explicitly in section 6.

## Forks and derivative builds

You may fork this repository and publish your own builds. If you do:

- **Rename it.** Do not call your build `reolink-cli`, and do not present it as
  an official or Reolink-endorsed distribution.
- **Drop the marks.** Remove the Reolink logo and banner from your fork's
  README, installers and any published artefact.
- Plain factual statements are fine — "compatible with Reolink cameras",
  "a fork of reolink-cli" — as long as they do not imply endorsement.
- Do not reuse the release-asset names or the installer URLs in this
  repository, so users can always tell an official download from a fork.

## Identifying an official build

Everything official comes from **this repository's GitHub Releases** and
nowhere else:

- assets are listed at `https://github.com/reolink/reolink-cli/releases`
- every release ships `SHA256SUMS`; the installers verify the download against
  it and abort on a mismatch
- `reolink-cli --version` prints the build flavour, e.g. `(external · LAN-only)`

A binary from any other source is not an official Reolink build, whatever it
calls itself.
