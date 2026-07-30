#!/bin/sh
# Check — or set — every version string in this repository.
#
#   ./scripts/check-version-sync.sh              # compare against the latest release
#   ./scripts/check-version-sync.sh 0.10.1       # compare against a version you name
#   ./scripts/check-version-sync.sh --self       # only: do the nine agree with each other?
#   ./scripts/check-version-sync.sh --set 0.11.0 # rewrite all of them, then check
#
# Exits non-zero and lists every file that disagrees.
#
# Why this exists: the version appears in nine places, and keeping them in step
# by hand has failed three times — once leaving the plugin manifests behind, once
# leaving this entire repository on the previous version while the release was
# already published, and once more while cutting 0.10.3. Readers saw a 0.10.0
# badge over a 0.10.1 download. Checking is cheap; remembering is not.
#
# --set writes the files, then falls through to the check, so the check is the
# verdict on its own work: a location whose pattern no longer matches shows up as
# a MISMATCH rather than being silently skipped. That is the whole point — the
# failure this script exists to prevent is a location quietly left behind.
#
# --set deliberately does NOT touch CHANGELOG.md. The entry needs release notes a
# script cannot write; the check only asserts the heading exists.
set -eu

cd "$(dirname "$0")/.."

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

mode=check
want=""
self=0
for arg in "$@"; do
  case "$arg" in
    --set)     mode=set ;;
    --self)    self=1 ;;
    -h|--help) usage 0 ;;
    -*)        echo "unknown option: $arg" >&2; usage 2 ;;
    *)         want="$arg" ;;
  esac
done

# --self asks only "do these nine agree with each other?", taking package.json as
# the reference. It exists for pull requests: a branch may legitimately carry a
# version no release uses yet, but a hand-edit that updates eight of nine files
# is never legitimate. Comparing against the published release is the separate
# check, and it belongs on `release: published` and a schedule.
if [ "$self" -eq 1 ]; then
  [ -z "$want" ] || { echo "--self takes no version argument" >&2; exit 2; }
  [ "$mode" = check ] || { echo "--self cannot be combined with --set" >&2; exit 2; }
  want=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][^"]*\)".*/\1/p' package.json | head -n1)
  [ -n "$want" ] || { echo "could not read a version from package.json" >&2; exit 2; }
  echo "checking internal agreement against package.json: $want"
fi

# --set never resolves the version from the published release: you run it while
# preparing a version that is not published yet, and silently stamping whatever
# is currently latest is how you ship the previous version's number.
if [ "$mode" = set ]; then
  [ -n "$want" ] || { echo "--set needs the version to write, e.g. --set 0.11.0" >&2; exit 2; }
fi

# Exactly three numeric segments. A looser test accepts a typo like "0.10.3.1"
# and --set would then stamp it into all nine files without complaint.
if [ -n "$want" ]; then
  _rest=${want#*.}
  # Two dots exactly. Without this, "1.2" parses as major=1 minor=2 patch=2 —
  # every segment numeric, silently accepted, and stamped everywhere as "1.2".
  case "$_rest" in *.*) ;; *) echo "not a version: $want (expected X.Y.Z)" >&2; exit 2 ;; esac
  _major=${want%%.*} _minor=${_rest%%.*} _patch=${_rest#*.}
  for _seg in "$_major" "$_minor" "$_patch"; do
    case "$_seg" in
      ''|*[!0-9]*) echo "not a version: $want (expected X.Y.Z)" >&2; exit 2 ;;
    esac
  done
fi

if [ -z "$want" ]; then
  want=$(curl -fsSL -A version-sync-check \
    "https://api.github.com/repos/reolink/reolink-cli/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$want" ] || { echo "could not resolve the latest release; pass a version explicitly" >&2; exit 2; }
  echo "latest published release: $want"
fi

# The single list of locations. Adding a tenth is one line here, and both the
# check and the rewrite pick it up — two lists that must agree is the same class
# of bug this script exists to catch.
#
# Kinds: json   — a manifest with a "version" field (marketplace.json nests it
#                 inside a plugin entry, so take the first match rather than
#                 assuming a fixed depth)
#        badge  — the README shields.io version badge
#        setup  — the `--version` example output in the skill's setup notes
LOCATIONS='
package.json:json
openclaw.plugin.json:json
gemini-extension.json:json
.claude-plugin/plugin.json:json
.claude-plugin/marketplace.json:json
.codex-plugin/plugin.json:json
.cursor-plugin/plugin.json:json
README.md:badge
skills/reolink-cli/references/setup.md:setup
'

extract() { # file kind
  case "$2" in
    json)  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][^"]*\)".*/\1/p' "$1" | head -n1 ;;
    badge) sed -n 's/.*version-\([0-9][0-9.]*\)-blue.*/\1/p'                      "$1" | head -n1 ;;
    setup) sed -n 's/.*reolink-cli --version.*# *→ *\([0-9][0-9.]*\).*/\1/p'      "$1" | head -n1 ;;
  esac
}

# Rewrite the FIRST match only. `1,/pat/s///` is the POSIX idiom for that: a bare
# s/// would also rewrite a pinned dependency that happens to share the version.
rewrite() { # file kind version
  case "$2" in
    json)  sed "1,/\"version\"/s/\"version\"\([[:space:]]*\):\([[:space:]]*\)\"[0-9][^\"]*\"/\"version\"\1:\2\"$3\"/" "$1" > "$1.tmp" ;;
    badge) sed "1,/version-[0-9]/s/version-[0-9][0-9.]*-blue/version-$3-blue/"                                        "$1" > "$1.tmp" ;;
    setup) sed "1,/reolink-cli --version/s/\(reolink-cli --version.*# *→ *\)[0-9][0-9.]*/\1$3/"                        "$1" > "$1.tmp" ;;
  esac
  mv "$1.tmp" "$1"
}

if [ "$mode" = set ]; then
  echo "setting every version string to $want"
  for entry in $LOCATIONS; do
    f=${entry%:*}; kind=${entry#*:}
    [ -f "$f" ] || { printf '  skip      %-46s not in this checkout\n' "$f"; continue; }
    rewrite "$f" "$kind" "$want"
  done
  echo
fi

fail=0
report() {
  found="$2"
  if [ "$found" != "$want" ]; then
    printf '  MISMATCH  %-46s %s (want %s)\n' "$1" "${found:-<not found>}" "$want"
    fail=1
  else
    printf '  ok        %-46s %s\n' "$1" "$found"
  fi
}

for entry in $LOCATIONS; do
  f=${entry%:*}; kind=${entry#*:}
  [ -f "$f" ] || continue
  report "$f" "$(extract "$f" "$kind")"
done

# The installers verify downloads against checksums/v<version>.sha256 on the
# default branch and fail closed — so a release synced without its checksum file
# does not have a stale badge, it has a broken `curl | sh` for every user until
# someone notices. This check is how someone notices within a day.
if [ -s "checksums/v${want}.sha256" ]; then
  printf '  ok        %-46s exists\n' "checksums/v${want}.sha256"
else
  printf '  MISMATCH  %-46s missing — one-line installs FAIL CLOSED without it\n' "checksums/v${want}.sha256"
  fail=1
fi

# The changelog is the one place the version must appear as a heading. A release
# published without its entry is how a user ends up reading last version's notes.
# Anchor the closing bracket: a prefix match would accept "## [0.10.1-rc]"
# as the entry for 0.10.1.
if grep -qE "^## \[?${want}\]? " CHANGELOG.md || grep -qE "^## \[?${want}\]?$" CHANGELOG.md; then
  printf '  ok        %-46s has an entry\n' "CHANGELOG.md"
else
  printf '  MISMATCH  %-46s no "## [%s]" heading (write it by hand)\n' "CHANGELOG.md" "$want"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Version strings disagree with $want."
  exit 1
fi
echo
echo "All version strings agree with $want."
