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

# Where the checksum comes from is NOT overridable, and that is the whole point.
#
# Reported privately (GHSA-65x2-w384-qp7j, finding 2). Both the archive and the
# checksum used to be fetched from $REPO, so pointing REOLINK_REPO at another
# repository meant the archive was checked against *that* repository's own
# committed checksums. Attacker supplies both halves, every check passes, and
# the install reports "ok" with a hash it just accepted from the attacker.
#
# "You need shell access to set the variable, and then you have code execution
# anyway" is not a rebuttal here. The override travels in text people copy: a
# blog snippet, a Dockerfile, a CI job, a web page an AI agent is reading. The
# danger was never that the variable exists; it was that it silently moved the
# anchor along with the download, so a documented, apparently-verified path was
# not verified against anything the project controls.
#
# A genuine mirror still works: mirroring means identical bytes, so the
# canonical checksums match. What no longer works is a fork serving its own
# build — which is exactly the case that must not silently pass.
CHECKSUM_REPO="reolink/reolink-cli"
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

# Alpine and the distributions built on it (Home Assistant OS most visibly) use
# musl rather than glibc. The glibc archives do not merely run badly there, they
# cannot load at all: `Error relocating ./reolink-cli: __res_init: symbol not
# found`. Pick the statically linked musl archive instead.
#
# Two probes because either alone has a blind spot: the loader path is what
# actually decides, but a container can carry musl without the usual filename,
# and `ldd --version` prints "musl libc" on Alpine while exiting non-zero, so it
# is read for its output and not its status. A glibc box that merely has musl
# installed alongside would match and get the static archive, which runs there
# too — the failure this ordering avoids is the one that leaves you unable to
# start the binary at all.
if [ "$os" = linux ]; then
  if [ -n "$(ls /lib/ld-musl-*.so.1 2>/dev/null)" ] ||
     { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; then
    arch="${arch}-musl"
  fi
fi

# Optional bearer token (private repo only); public access is anonymous.
AUTH=""
[ -n "${GITHUB_TOKEN:-}" ] && AUTH="Authorization: Bearer $GITHUB_TOKEN"

if [ "$REPO" != "$CHECKSUM_REPO" ]; then
  say "note: downloading from $REPO, but verifying against checksums committed to"
  say "      $CHECKSUM_REPO. A mirror of the same artifacts passes; a fork serving"
  say "      its own build will not."
fi

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
hint=""
case "$arch" in
  *-musl) hint="
musl archives start at v0.10.7; earlier releases published glibc builds only." ;;
esac
curl -fSL -A reolink-cli-install ${AUTH:+-H "$AUTH"} \
  -o "$tmp/pkg.tar.gz" "https://github.com/$REPO/releases/download/$tag/$asset" \
  || die "download failed — see https://github.com/$REPO/releases$hint"

# Verify the download against the checksums COMMITTED TO THE REPOSITORY, not the
# SHA256SUMS attached to the release. The distinction is the trust boundary:
# replacing a release asset takes one API call by any account with write access
# and leaves no visible trace, and whoever can do that can regenerate a matching
# SHA256SUMS in the same call — a checksum from the same release can therefore
# only ever detect accidental corruption. A file on the default branch is behind
# a reviewed pull request and permanent history. checksums/<tag>.sha256 is
# committed there as part of each release, from the machine that built it.
#
# Fail closed, deliberately:
#   - no fallback to the release-attached SHA256SUMS — a fallback would hand an
#     attacker who controls the release a way to bypass this by making the
#     repository fetch fail;
#   - a tag with no committed checksum file aborts, so a fabricated release
#     (a tag that never went through the release process) does not install.
#
# This is an integrity check, not a signature. It proves the archive is the one
# whose hash was committed to $CHECKSUM_REPO; it does not prove who built it.
# An attacker who can commit to that repository's default branch can publish a
# matching pair. Nothing here defends against that — see SECURITY.md.
say "==> verifying checksum against $CHECKSUM_REPO"
curl -fsSL -A reolink-cli-install ${AUTH:+-H "$AUTH"} \
     -o "$tmp/CHECKSUMS" "https://raw.githubusercontent.com/$CHECKSUM_REPO/main/checksums/$tag.sha256" 2>/dev/null \
  || die "no committed checksum file for $tag (checksums/$tag.sha256 on the default branch of $CHECKSUM_REPO).
Either this release has not been synced yet, or the tag did not come from the
release process. Refusing to install."

expected=$(sed -n "s/^\([0-9a-f]\{64\}\)[[:space:]]*[*]\{0,1\}$asset$/\1/p" "$tmp/CHECKSUMS" | head -n1)
[ -n "$expected" ] || die "checksums/$tag.sha256 has no entry for $asset — refusing to install"

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
The download does not match the checksum committed to the repository.
Nothing was installed."
say "    ok ($expected)"

# Refuse a hostile archive layout before unpacking it (GHSA-65x2-w384-qp7j,
# finding 3). Two separate problems, and only one of them was theoretical.
#
# Absolute and `..` members: current tar implementations already contain these
# — BSD tar refuses `..` outright and exits non-zero, GNU/busybox tar strips the
# prefix and keeps the file inside the destination — so neither escapes today.
# The check is here so that guarantee comes from this script rather than from
# whichever tar happens to be installed, and so the failure is a clear sentence
# instead of "Path contains '..': Unknown error: -1".
#
# The one that was real: the binaries were located with
# `find "$tmp" -type f -name reolink-cli | head -n1`, which searches the whole
# extraction tree and takes whatever the walk reaches first. An archive carrying
# a second `reolink-cli` in a directory sorting before the real one wins, and
# that file is then chmod +x'd and executed. Confirmed by building such an
# archive: the planted copy was selected. Both are fixed below — extract into a
# dedicated subdirectory, and copy from the archive's documented layout instead
# of searching for a name.
say "==> checking archive layout"
bad=$(tar -tzf "$tmp/pkg.tar.gz" | awk '
  /^\// || /(^|\/)\.\.(\/|$)/ { print; count++ }
  END { if (count == 0) exit 0 }' | head -n5)
[ -z "$bad" ] || die "archive contains absolute or parent-directory members — refusing to extract:
$bad"

unpack="$tmp/unpack"
mkdir -p "$unpack"
tar -xzf "$tmp/pkg.tar.gz" -C "$unpack" || die "extraction failed"

# The directory name is not discovered, it is derived: the release archive
# always unpacks to a single directory named after itself, so we know what it
# must be called before looking. Searching for it — even for "the first
# top-level directory" — reintroduces the bug being fixed, because `find`
# returns readdir order and an attacker picks the names. Anything else in the
# archive is now simply never consulted.
root="$unpack/${asset%.tar.gz}"
[ -d "$root" ] || die "archive does not unpack to ${asset%.tar.gz}/ — layout is not what this installer expects"

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
  src="$root/bin/$b"
  [ -f "$src" ] || die "$b is not at bin/$b in the archive — refusing to guess"
  # A symlink here would copy whatever it points at, under a name we then make
  # executable. The archive ships regular files; anything else is not it.
  [ -L "$src" ] && die "bin/$b in the archive is a symlink — refusing to install"
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
