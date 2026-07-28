#!/bin/sh
# Check that every version string in this repository agrees with the latest
# published GitHub release.
#
#   ./scripts/check-version-sync.sh            # compare against the latest release
#   ./scripts/check-version-sync.sh 0.10.1     # compare against a version you name
#
# Exits non-zero and lists every file that disagrees.
#
# Why this exists: the version appears in nine places, and keeping them in step
# by hand failed twice in a row — once leaving the plugin manifests behind, once
# leaving this entire repository on the previous version while the release was
# already published. Readers saw a 0.10.0 badge over a 0.10.1 download. Checking
# is cheap; remembering is not.
set -eu

cd "$(dirname "$0")/.."

want="${1:-}"
if [ -z "$want" ]; then
  want=$(curl -fsSL -A version-sync-check \
    "https://api.github.com/repos/reolink/reolink-cli/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$want" ] || { echo "could not resolve the latest release; pass a version explicitly" >&2; exit 2; }
  echo "latest published release: $want"
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

# The JSON manifests each carry a "version" field. marketplace.json nests it
# inside a plugin entry, so take the first match in every file rather than
# assuming a fixed depth.
for f in package.json openclaw.plugin.json gemini-extension.json \
         .claude-plugin/plugin.json .claude-plugin/marketplace.json \
         .codex-plugin/plugin.json .cursor-plugin/plugin.json; do
  [ -f "$f" ] || continue
  report "$f" "$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][^"]*\)".*/\1/p' "$f" | head -n1)"
done

report "README.md (badge)" \
  "$(sed -n 's/.*version-\([0-9][0-9.]*\)-blue.*/\1/p' README.md | head -n1)"

report "skills/reolink-cli/references/setup.md" \
  "$(sed -n 's/.*reolink-cli --version.*# *→ *\([0-9][0-9.]*\).*/\1/p' \
     skills/reolink-cli/references/setup.md | head -n1)"

# The changelog is the one place the version must appear as a heading. A release
# published without its entry is how a user ends up reading last version's notes.
# Anchor the closing bracket: a prefix match would accept "## [0.10.1-rc]"
# as the entry for 0.10.1.
if grep -qE "^## \[?${want}\]? " CHANGELOG.md || grep -qE "^## \[?${want}\]?$" CHANGELOG.md; then
  printf '  ok        %-46s has an entry\n' "CHANGELOG.md"
else
  printf '  MISMATCH  %-46s no "## [%s]" heading\n' "CHANGELOG.md" "$want"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "Version strings disagree with the published release."
  exit 1
fi
echo
echo "All version strings agree with $want."
