#!/bin/sh
# reolink-cli one-line installer (macOS / Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/reolink/reolink-cli/main/install.sh | sh
#
# Downloads the latest release binary for your platform, installs it to
# ~/.local/bin, and initializes config. No AI agent needed — for agents, use
# `npx skills add reolink/reolink-cli` instead (it fetches the binary for you).
#
# Env overrides: REOLINK_REPO=owner/repo, REOLINK_PREFIX=/install/root.
set -eu

REPO="${REOLINK_REPO:-reolink/reolink-cli}"
PREFIX="${REOLINK_PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"

os=$(uname -s); arch=$(uname -m)
case "$os" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *) die "unsupported OS '$os' — see https://github.com/$REPO/releases" ;;
esac
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64)  arch=x86_64 ;;
  *) die "unsupported arch '$arch' — see https://github.com/$REPO/releases" ;;
esac

# macOS ships Apple Silicon only; Intel Macs are not supported.
if [ "$os" = darwin ] && [ "$arch" = x86_64 ]; then
  die "macOS Intel (x86_64) is not supported — Apple Silicon (arm64) only. See https://github.com/$REPO/releases"
fi

# Optional bearer token (private repo only); public access is anonymous.
AUTH=""
[ -n "${GITHUB_TOKEN:-}" ] && AUTH="Authorization: Bearer $GITHUB_TOKEN"

say "==> resolving latest release of $REPO"
tag=$(curl -fsSL -A reolink-cli-install ${AUTH:+-H "$AUTH"} \
  "https://api.github.com/repos/$REPO/releases/latest" \
  | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
[ -n "$tag" ] || die "could not resolve the latest release (is the repo public? set GITHUB_TOKEN if it is private)"
ver="${tag#v}"
# Release archives carry the build flavour in the name so internal (Song P2P)
# and customer (LAN-only) builds can never be mistaken for one another. Only
# the external flavour is published here.
asset="reolink-cli-${ver}-external-${os}-${arch}.tar.gz"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

say "==> downloading $asset ($tag)"
curl -fSL -A reolink-cli-install ${AUTH:+-H "$AUTH"} \
  -o "$tmp/pkg.tar.gz" "https://github.com/$REPO/releases/download/$tag/$asset" \
  || die "download failed — see https://github.com/$REPO/releases"

# Verify the download against the release's published SHA256SUMS before running
# anything out of it. This script installs executables fetched over the network,
# so an unverified archive is the weakest link in the chain — every release ships
# SHA256SUMS for exactly this purpose.
say "==> verifying checksum"
if curl -fsSL -A reolink-cli-install ${AUTH:+-H "$AUTH"} \
     -o "$tmp/SHA256SUMS" "https://github.com/$REPO/releases/download/$tag/SHA256SUMS" 2>/dev/null; then
  expected=$(sed -n "s/^\([0-9a-f]\{64\}\)[[:space:]]*[*]\{0,1\}$asset$/\1/p" "$tmp/SHA256SUMS" | head -n1)
  [ -n "$expected" ] || die "SHA256SUMS has no entry for $asset — refusing to install"

  if command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$tmp/pkg.tar.gz" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$tmp/pkg.tar.gz" | awk '{print $1}')
  else
    die "no shasum/sha256sum available to verify the download — install one, or download and verify manually from https://github.com/$REPO/releases"
  fi

  [ "$actual" = "$expected" ] || die "checksum mismatch for $asset
  expected $expected
  actual   $actual
The download is corrupt or tampered with. Nothing was installed."
  say "    ok ($expected)"
else
  die "could not fetch SHA256SUMS for $tag — refusing to install an unverified binary"
fi

tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
mkdir -p "$BIN"

# Stop a running reolink-gateway installed under $BIN before overwriting, so the
# upgrade takes effect (and the overwrite can't fail on a locked binary).
if command -v pgrep >/dev/null 2>&1; then
  for _pid in $(pgrep -x reolink-gateway 2>/dev/null || true); do
    _exe=""
    [ -L "/proc/$_pid/exe" ] && _exe=$(readlink "/proc/$_pid/exe" 2>/dev/null || true)
    [ -z "$_exe" ] && command -v lsof >/dev/null 2>&1 && _exe=$(lsof -p "$_pid" 2>/dev/null | awk '$4=="txt"{print $NF; exit}')
    case "$_exe" in "$BIN"/*) say "==> stopping running reolink-gateway (pid $_pid)"; kill "$_pid" 2>/dev/null || true ;; esac
  done
fi

for b in reolink-cli reolink-gateway; do
  src=$(find "$tmp" -type f -name "$b" | head -n1)
  [ -n "$src" ] || die "$b not found in the archive"
  cp "$src" "$BIN/$b" && chmod 0755 "$BIN/$b"
done

"$BIN/reolink-cli" config init >/dev/null 2>&1 || true

say ""
say "installed reolink-cli + reolink-gateway to $BIN"
"$BIN/reolink-cli" --version 2>/dev/null | sed 's/^/  /' || true
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say ""; say "$BIN is not on your PATH yet — add it:"
     say "  echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.profile && export PATH=\"$BIN:\$PATH\"" ;;
esac
say ""
say "next steps:"
say "  reolink-cli gateway start --addr 127.0.0.1:9000 &"
say "  reolink-cli device add front-door --host <camera-ip> --user admin"
say "  reolink-cli --camera front-door info"
say ""
say "using an AI agent (Claude Code / Codex / Cursor / …)? install the skill:"
say "  npx skills@latest add $REPO"
