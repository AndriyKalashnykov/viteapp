#!/usr/bin/env bash
#
# Make `no-cache-filters` FAIL CLOSED.
#
# WHY: `docker/build-push-action`'s `no-cache-filters` takes a build STAGE NAME.
# A stale or typo'd value is NOT an error — measured 2026-07-20, building with
# `--no-cache-filter serverr` against a populated cache exits 0, emits no
# warning, and silently replays the stale layer. The whole security value of the
# filter therefore hangs on a magic string in ci.yml agreeing with `AS <name>`
# in the Dockerfile, and it fails toward *vulnerable*.
#
# This gate asserts two invariants, both DERIVED from the files rather than
# re-typed here (a second hardcoded copy of the stage name would be the very
# drift this is meant to prevent):
#
#   1. Every `no-cache-filters:` value in ci.yml equals the Dockerfile's final
#      stage name. Catches a stage rename.
#   2. The number of builds importing the gha cache equals the number carrying
#      the filter. Catches a NEW cached build being added without it — which is
#      the more likely regression, and the one that re-opens the hole silently.
#
# RED-proof (both directions):
#   sed -i 's/ AS server$/ AS runtime/' Dockerfile && ./scripts/check-dockerfile-stage.sh   # must FAIL
#   git checkout Dockerfile
#   # then delete one `no-cache-filters: server` line from ci.yml -> must FAIL on the count
#
set -euo pipefail

DOCKERFILE="${DOCKERFILE:-Dockerfile}"
WORKFLOW="${WORKFLOW:-.github/workflows/ci.yml}"

for f in "$DOCKERFILE" "$WORKFLOW"; do
  [ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }
done

# The final `FROM ... AS <name>` is the stage that produces the shipped image.
stage="$(grep -oE '^FROM .* [Aa][Ss] [A-Za-z0-9_.-]+$' "$DOCKERFILE" | tail -1 | awk '{print $NF}')"
if [ -z "$stage" ]; then
  echo "ERROR: could not determine the final build stage from $DOCKERFILE" >&2
  echo "       (expected a trailing 'FROM ... AS <name>' line)" >&2
  exit 1
fi

# `grep -c` exits 1 on zero matches; `|| true` keeps `set -e` from firing on the
# very case we want to report ourselves.
cached_builds="$(grep -cE '^[[:space:]]*cache-from:[[:space:]]*type=gha' "$WORKFLOW" || true)"
filtered_builds="$(grep -cE '^[[:space:]]*no-cache-filters:' "$WORKFLOW" || true)"

rc=0

# Invariant 1 — every filter value names the real final stage.
while IFS= read -r value; do
  [ -z "$value" ] && continue
  if [ "$value" != "$stage" ]; then
    echo "FAIL: ci.yml has 'no-cache-filters: $value' but $DOCKERFILE's final stage is '$stage'." >&2
    echo "      A non-matching filter silently NO-OPS: the apk upgrade layer would be replayed" >&2
    echo "      from cache and the image would ship unpatched packages behind a green build." >&2
    rc=1
  fi
done < <(grep -E '^[[:space:]]*no-cache-filters:' "$WORKFLOW" | sed -E 's/.*no-cache-filters:[[:space:]]*//' | tr -d '"' || true)

# Invariant 2 — no cache-importing build may lack the filter.
if [ "$cached_builds" -ne "$filtered_builds" ]; then
  echo "FAIL: $cached_builds build step(s) import the gha cache but only $filtered_builds carry 'no-cache-filters'." >&2
  echo "      Every build importing that cache must set it, or it re-seeds a stale '$stage'" >&2
  echo "      layer for the others. Add 'no-cache-filters: $stage' to the build(s) missing it." >&2
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "PASS: final stage '$stage'; $filtered_builds/$cached_builds gha-cached build(s) carry a matching no-cache-filters."
fi
exit "$rc"
