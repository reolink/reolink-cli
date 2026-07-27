# Admin: Device Accounts / System / Raw Debug

## Device User Accounts

These manage the camera's own admin/operator login accounts — NOT CLI aliases. Name and password are each 1–31 chars.

`users add` / `users passwd` prompt for the new password. In CI, use `--password-stdin`. Never pass `--password PLAIN` on argv.

```bash
# List accounts (admin sees all; non-admin sees only self)
reolink-cli --camera front-door users list

# Add an operator account (interactive prompt)
reolink-cli --camera front-door users add ops --level user

# Add an admin with stdin-fed password (CI-safe)
printf 'StrongPass123\n' | reolink-cli --camera front-door users add backup-admin --level admin --password-stdin

# Change a password (prompt)
reolink-cli --camera front-door users passwd ops

# Remove a user
reolink-cli --camera front-door users remove ops
```

**Device refuses** to delete the last admin. Non-admin users can only change their own password — admin login is required to change someone else's or to add/remove users. Removing or password-changing a user does NOT kick their active session; reboot the device to force re-auth.

## System Reboot

```bash
reolink-cli --camera front-door system reboot
```

Drops the TCP session immediately (the CLI swallows the resulting `Connection reset`). Device takes 30–60 s to come back. Any in-flight capture or preview is aborted.

## Firmware Upgrade

```bash
# Flash a local firmware package (.pak/.paks). Prompts to confirm unless -y.
reolink-cli --camera front-door system upgrade ./RP-PCB8MX.6577_2606041284.IPC_NT17EM118MPB60B.paks

# Factory-reset upgrade (wipes settings) + skip the prompt
reolink-cli --camera front-door system upgrade ./fw.paks --factory-reset -y
```

⚠️ **Bricking risk — get these right before flashing:**

- **Match the package to the device.** Run `info` first and confirm the package's `model` (device_type) AND `hardware_version` (hw_ver) both match the device. Flashing another model's firmware is the classic way to brick. (A package's `.json` / `descriptor.json` sidecars carry `device_type` / `hw_ver`.)
- **The GATEWAY reads the file, not the CLI.** `<path>` must be readable on the gateway host (normally the same machine as the CLI). For a remote gateway, copy the `.paks` there first — 40 MB+ packages can't ride in-band (4 MiB frame cap), which is why it is a local path.
- **Do NOT power off** during the upload or the subsequent flash + reboot (several minutes). The device flashes only *after* receiving the complete file, so interrupting the upload is non-destructive; the dangerous window is after the final chunk.

Transfer pacing auto-selects from `capabilities.upgrade` (bit1 = speed-control): supported → sliding window (`transferMode:"windowed"`, ~10 chunks in flight, much faster over P2P / WAN); otherwise stop-and-wait. The response reports `bytesSent`, `transferMode`, `window`, `rebooting`.

**Verify after:** the device reboots into the new build. Re-query `info` once it is back (30 s – several min) and confirm `firmware` changed to the target build.

Standalone "factory reset" (without a firmware flash) is NOT in the CLI — for that, ask the user to use the Reolink mobile app.

## Raw (Advanced / Debug)

```bash
# Raw command by number
reolink-cli --camera front-door raw 80 --body-xml '<body />'
reolink-cli --camera front-door raw 58 --ext-xml '<Extension><userName>admin</userName></Extension>'
```

Use raw only to validate a new path before proposing a typed CLI surface for it, or to unblock a user hitting an un-mapped cmd. The numeric cmd list lives in the internal v20 protocol documentation.
