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
# Overridable AND existence-checked like the other two: hardcoding it meant a
# renamed/absent Makefile (or running from a subdirectory) made the Makefile
# invariants pass VACUOUSLY — `0 buildx build(s)`, rc=0 — with `2>/dev/null`
# hiding the absence.
MAKEFILE="${MAKEFILE:-Makefile}"

for f in "$DOCKERFILE" "$WORKFLOW" "$MAKEFILE"; do
  [ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }
done

# The final `FROM ... AS <name>` is the stage that produces the shipped image.
#
# Strip comments and CR before matching: a trailing comment
# (`FROM x AS server # keep in sync`) or a CRLF file otherwise made the match
# skip the real final stage and fall back to an EARLIER one, so the gate
# reported the wrong stage — and following its own advice ("make them match")
# would have pointed the filter at a non-shipping stage, i.e. re-created the bug.
# (The `s/#.*//` strip is what fixes that. The `[[:space:]]*$` anchor below is
# retained deliberately — an earlier revision of this comment claimed the anchor
# had been dropped, which was false about its own code.)
# `|| true`: under `set -e` a non-matching pipeline would die AT THE ASSIGNMENT,
# making the diagnostic below unreachable (rc=1 with zero output).
stage="$(sed -e 's/\r$//' -e 's/#.*//' "$DOCKERFILE" \
  | grep -oiE '^FROM[[:space:]]+.*[[:space:]]AS[[:space:]]+[A-Za-z0-9_.-]+[[:space:]]*$' \
  | tail -1 | awk '{print $NF}' || true)"
if [ -z "$stage" ]; then
  echo "ERROR: could not determine the final build stage from $DOCKERFILE" >&2
  echo "       (expected a trailing 'FROM ... AS <name>' line)" >&2
  exit 1
fi

# Count PER BUILD STEP, not per file. A file-wide tally passes whenever an
# unrelated filtered build balances an unfiltered cached one — precisely the
# regression invariant 2 exists to catch. `awk` walks each `- ` list item and
# records whether THAT item both imports the cache and carries the filter.
# `cache-from:` is also matched in BLOCK-SCALAR form (`cache-from: |` then
# `type=gha` on a following line), which the single-line regex missed entirely.
# The step delimiter matches `- name:` / `- uses:` specifically, NOT any `- `
# list item: a plain `- ` also matches entries of a legitimate `tags:` /
# `platforms:` sequence sitting between `no-cache-filters:` and `cache-from:`,
# which reset the state mid-step and produced a FALSE RED on a workflow whose
# builds were all correctly filtered.
read -r cached_builds filtered_builds unfiltered <<EOF
$(sed -e 's/\r$//' "$WORKFLOW" | awk '
  /^[[:space:]]*-[[:space:]]+(name|uses):/ { if (incache) { c++; if (infilter) f++; else u++ } incache=0; infilter=0; inblock=0 }
  /^[[:space:]]*cache-from:[[:space:]]*\|/ { inblock=1; next }
  inblock && /type=gha/ { incache=1 }
  inblock && /^[[:space:]]*[a-z-]+:/ { inblock=0 }
  /^[[:space:]]*cache-from:[[:space:]]*type=gha/ { incache=1 }
  /^[[:space:]]*no-cache-filters:/ { infilter=1 }
  END { if (incache) { c++; if (infilter) f++; else u++ } print c+0, f+0, u+0 }
')
EOF

# The counters must be REAL INTEGERS. If the awk above dies (syntax error, awk
# absent, a future edit breaking it), the heredoc yields empty strings, `set -e`
# does NOT fire (a failing substitution inside a heredoc is not the statement's
# status), and a later `${unfiltered:-0}` would silently turn "the counter never
# ran" into a PASS — with an empty denominator as the only tell. Fail closed.
case "${cached_builds}|${filtered_builds}|${unfiltered}" in
  *[!0-9\|]*|*'||'*|'|'*|*'|')
    echo "ERROR: build-step counters did not compute (got '${cached_builds}|${filtered_builds}|${unfiltered}')." >&2
    echo "       This gate verified NOTHING — refusing to report success." >&2
    exit 1 ;;
esac

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
done < <(sed -e 's/\r$//' -e 's/#.*//' "$WORKFLOW" \
  | grep -E '^[[:space:]]*no-cache-filters:' \
  | sed -E 's/.*no-cache-filters:[[:space:]]*//' | tr -d "\"'" \
  | sed -e 's/[[:space:]]*$//' || true)

# Invariant 2 — no cache-importing build may lack the filter (counted per step).
if [ "${unfiltered:-0}" -ne 0 ]; then
  echo "FAIL: $unfiltered of $cached_builds gha-cache-importing build step(s) lack 'no-cache-filters'." >&2
  echo "      Every build importing that cache must set it, or it re-seeds a stale '$stage'" >&2
  echo "      layer for the others. Add 'no-cache-filters: $stage' to the build(s) missing it." >&2
  rc=1
fi

# Comment-stripped view: full-line AND inline trailing comments. Inline matters —
# a recipe line ending `# was --no-cache-filter old` otherwise false-REDs the
# value check on a pure comment edit; and the recipe's own explanatory comment
# names `--no-cache-filter server`, which inflated the denominator (2 for 1 real
# build) — a gate matching its own prose.
mk_src="$(sed -E '/^[[:space:]]*@?#/d; s/#.*$//' "$MAKEFILE")"

# Invariant 3a (COVERAGE) — every Makefile buildx build that imports the cache
# must CARRY the filter. This is the half that was missing: the value check
# below only iterates lines that ALREADY have `--no-cache-filter`, so it is
# structurally incapable of noticing one that lacks it — a `docker buildx build
# --cache-from type=gha` with no filter PASSED, the same fail-open shape
# invariant 2 exists to catch, one file over, with wording that read as coverage.
mk_unfiltered="$(printf '%s\n' "$mk_src" \
  | grep -E 'buildx[[:space:]]+build' | grep -E 'cache-from' \
  | grep -vcE -- '--no-cache-filter' || true)"
case "$mk_unfiltered" in ''|*[!0-9]*) mk_unfiltered=0 ;; esac
if [ "$mk_unfiltered" -ne 0 ]; then
  echo "FAIL: $mk_unfiltered $MAKEFILE buildx build(s) import the cache but lack '--no-cache-filter'." >&2
  echo "      Add '--no-cache-filter $stage', or the '$stage' layer is replayed from cache there." >&2
  rc=1
fi

# Invariant 3b (VALUE) — those builds name the SAME stage. buildx takes
# `--no-cache-filter` (SINGULAR); the action input is `no-cache-filters`
# (PLURAL). Without this, a consistent rename across Dockerfile + ci.yml passes
# while the Makefile keeps a stale name that silently no-ops for `image-build`
# and everything downstream of it.
while IFS= read -r value; do
  [ -z "$value" ] && continue
  if [ "$value" != "$stage" ]; then
    echo "FAIL: $MAKEFILE has '--no-cache-filter $value' but the final stage is '$stage'." >&2
    rc=1
  fi
done < <(printf '%s\n' "$mk_src" \
  | grep -oE -- '--no-cache-filter[= ][A-Za-z0-9_.-]+' \
  | sed -E 's/--no-cache-filter[= ]//' || true)
mk_count="$(printf '%s\n' "$mk_src" | grep -cE -- '--no-cache-filter[= ]' || true)"
case "$mk_count" in ''|*[!0-9]*) mk_count=0 ;; esac

if [ "$rc" -eq 0 ]; then
  echo "PASS: final stage '$stage'; $filtered_builds/$cached_builds gha-cached workflow build(s) filtered; $mk_count/$((mk_count + mk_unfiltered)) $MAKEFILE buildx build(s) filtered."
  # SCOPE, so the denominators are not read as more than they are: this covers
  # ci.yml build STEPS and Makefile raw-buildx lines. A `docker buildx build
  # --cache-from` inside a workflow `run:` step, or under scripts/, is still NOT
  # counted — tracked in CLAUDE.md's Upgrade Backlog.
fi
exit "$rc"
