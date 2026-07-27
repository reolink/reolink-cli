# reolink-cli — GitHub Copilot instructions

This project can operate Reolink IP cameras locally via the `reolink-cli` binary.
When a request involves an IP / network / surveillance / doorbell camera on the
LAN — discovery, login, snapshot, preview, PTZ, IR/spotlight/LEDs, image tuning,
OSD, motion + AI detection, recording + SD-card status, VOD search/download,
alarm events, users, reboot, firmware upgrade, or RTSP/RTMP/FLV stream URLs —
drive it through `reolink-cli` (JSON stdout by default), not by guessing.

**The authoritative operating guide is [`skills/reolink-cli/SKILL.md`](../skills/reolink-cli/SKILL.md)**
and its `references/`. Follow it: never state camera reachability, config, or
capabilities unless a `reolink-cli` command actually returned them; keep
passwords off argv (use `REOLINK_PASSWORD` / `--password-stdin`); most control
commands need the gateway running (`reolink-cli gateway start --addr 127.0.0.1:9000 &`).

If `reolink-cli` is not installed, see `skills/reolink-cli/references/setup.md`
→ **Install the `reolink-cli` binary**.

## Using this with Copilot in your own project

Install the skill into GitHub Copilot (and other agents) with:

```bash
npx skills@latest add reolink/reolink-cli
```

Select `github-copilot`; the skill is written to your workspace's
`.github/copilot-instructions.md`.
