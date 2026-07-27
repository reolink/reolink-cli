# Support

## Which channel?

| Your question | Where to go |
|---|---|
| A bug in `reolink-cli`, the gateway, the skill or the installers | [GitHub issues](https://github.com/reolink/reolink-cli/issues) |
| A suspected security vulnerability | **Not an issue** — see [SECURITY.md](SECURITY.md) |
| Camera hardware, firmware, warranty, RMA, or your Reolink account | [Reolink support](https://support.reolink.com) — this repository cannot help |
| Camera firmware behaviour this CLI merely reports | Reolink support, same as above |

This repository is the CLI, not a general Reolink help desk. Firmware and
hardware questions filed here will be redirected, which only delays you.

## Before opening an issue

Include:

- `reolink-cli --version`
- your OS and CPU architecture
- the exact command and its JSON output (every command takes `--output json`)
- `reolink-cli doctor --output json`, which reports config, permission and
  gateway health

**Redact first.** Never paste camera passwords, tokens, UIDs, or recordings.
