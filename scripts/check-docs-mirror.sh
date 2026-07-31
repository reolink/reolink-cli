#!/bin/sh
# The skill docs exist in two repositories and are mirrored by hand. This checks
# they still agree.
#
#   ./scripts/check-docs-mirror.sh [path-to-public-clone]
#
# Why this exists: on 2026-07-31 a contributor's merged pull request was undone
# within the hour. It had landed in the public repository; the release sync then
# copied this repository's older copy over the top, and nothing noticed — not
# review, not CI, not the person doing it. Two files, one fact, no mechanism.
#
# The real fix is one copy, not two. Until the mirror goes away, this at least
# makes divergence loud, and it belongs in the release checklist BEFORE the
# sync copy is made — that is the moment work gets destroyed.
#
# A difference is not automatically wrong: content for an unreleased change
# legitimately sits here first. The point is that you look at it and decide,
# rather than copying over the top and finding out later.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
public=${1:-$here/../reolink-cli-github}

[ -d "$public/skills/reolink-cli" ] || {
  echo "no public clone at $public — pass its path as the first argument" >&2
  exit 2
}

mine="$here/plugins/reolink-cli/skills/reolink-cli"
theirs="$public/skills/reolink-cli"

status=0
for f in $(cd "$mine" && find . -name '*.md' | sort); do
  a="$mine/$f"
  b="$theirs/$f"
  name=${f#./}
  if [ ! -f "$b" ]; then
    printf '  ONLY HERE  %s\n' "$name"
    status=1
  elif ! diff -q "$a" "$b" >/dev/null 2>&1; then
    # Direction matters: lines only in the public copy are the dangerous ones,
    # because a sync copy from here would delete them.
    lost=$(diff "$a" "$b" | grep -c '^>' || true)
    added=$(diff "$a" "$b" | grep -c '^<' || true)
    printf '  DIFFERS    %-46s here-only:%s  public-only:%s\n' "$name" "$added" "$lost"
    [ "$lost" -gt 0 ] && printf '             ^ a sync copy from here would DELETE %s line(s) that exist only in public\n' "$lost"
    status=1
  fi
done

for f in $(cd "$theirs" && find . -name '*.md' | sort); do
  [ -f "$mine/$f" ] || { printf '  ONLY PUBLIC %s\n' "${f#./}"; status=1; }
done

if [ "$status" -eq 0 ]; then
  echo "  skill docs agree in both repositories."
else
  echo
  echo "Review each difference before syncing. Content that landed in the public"
  echo "repository (a merged pull request) must be brought back here first, or"
  echo "the sync will silently revert it."
fi
exit $status
