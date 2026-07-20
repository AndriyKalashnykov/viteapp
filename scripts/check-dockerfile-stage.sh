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
# FOUR checks, all DERIVED from the files rather than re-typed here (a second
# hardcoded copy of the stage name would be the very drift this prevents):
#
#   1  ci.yml: every `no-cache-filters:` value == the Dockerfile's final stage.
#   2  ci.yml: every gha-cache-importing build STEP carries the filter.
#   3a Makefile: every cache-importing build line carries `--no-cache-filter`.
#   3b Makefile: those filter values == the final stage.
#
# WHAT THIS DOES **NOT** COVER — stated positively and narrowly, because an
# earlier revision enumerated the gaps as if the list were exhaustive and a
# reader would have believed a continuation-style recipe was guarded:
#
#   * Makefile scanning handles `\`-continuations (folded below) but CANNOT see
#     a flag supplied through a Make variable — `--cache-from $(DOCKER_CACHE)`
#     or a whole command in `$(BUILD_CMD)` is invisible. No regex can expand it.
#   * A `docker buildx build --cache-from` inside a workflow `run:` step is not
#     counted (only `docker/build-push-action` STEPS are).
#   * Builders under `scripts/`, or in an included `*.mk`, are not scanned.
#   * A `FROM x AS decoy` inside a Dockerfile heredoc can be mis-derived as the
#     final stage (needs heredoc-aware parsing; latent, see CLAUDE.md backlog).
#
# RED-proof (restore with `cp`, NEVER `git checkout --` — that silently eats
# uncommitted work, which happened while writing this):
#   cp Dockerfile /tmp/d.bak; sed -i 's/ AS server$/ AS runtime/' Dockerfile
#   ./scripts/check-dockerfile-stage.sh   # must FAIL; then: cp /tmp/d.bak Dockerfile
#
set -euo pipefail

DOCKERFILE="${DOCKERFILE:-Dockerfile}"
WORKFLOW="${WORKFLOW:-.github/workflows/ci.yml}"
# Overridable AND existence-checked like the other two: hardcoding it meant a
# renamed/absent Makefile made the Makefile checks pass VACUOUSLY, with
# `2>/dev/null` hiding the absence.
MAKEFILE="${MAKEFILE:-Makefile}"

for f in "$DOCKERFILE" "$WORKFLOW" "$MAKEFILE"; do
  [ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }
done

# ---- the shipped stage -------------------------------------------------------
# Strip comments and CR before matching: a trailing comment
# (`FROM x AS server # keep in sync`) or a CRLF file otherwise made the match
# skip the real final stage and fall back to an EARLIER one — and following the
# gate's own advice ("make them match") would then point the filter at a
# non-shipping stage, i.e. re-create the bug. The `s/#.*//` strip is what fixes
# that; the `[[:space:]]*$` anchor below is retained deliberately.
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

# ---- ci.yml: count PER BUILD STEP -------------------------------------------
# A file-wide tally passes whenever an unrelated filtered build balances an
# unfiltered cached one — the regression check 2 exists to catch.
#
# The step delimiter is `- <key>:` — ANY key, not just name/uses. Narrowing it
# to `(name|uses)` merged every step whose first key is something else into its
# predecessor, so a *filtered* predecessor laundered an unfiltered cached build.
# That is reachable here: ci.yml has `- id: filter`. But it must still NOT match
# a bare sequence VALUE (`- linux/amd64` under `platforms:`), which is what
# caused the earlier false RED — hence requiring a trailing `:`.
read -r cached_builds filtered_builds unfiltered <<EOF
$(sed -e 's/\r$//' "$WORKFLOW" | awk '
  /^[[:space:]]*-[[:space:]]+[A-Za-z_-]+:/ { if (incache) { c++; if (infilter) f++; else u++ } incache=0; infilter=0; inblock=0 }
  /^[[:space:]]*cache-from:[[:space:]]*\|/ { inblock=1; next }
  inblock && /type=gha/ { incache=1 }
  inblock && /^[[:space:]]*[a-z-]+:/ { inblock=0 }
  /^[[:space:]]*cache-from:[[:space:]]*type=gha/ { incache=1 }
  /^[[:space:]]*no-cache-filters:/ { infilter=1 }
  END { if (incache) { c++; if (infilter) f++; else u++ } print c+0, f+0, u+0 }
')
EOF

# The counters must be REAL INTEGERS. If the awk dies (syntax error, awk absent,
# a future edit), the heredoc yields empty strings, `set -e` does NOT fire (a
# failing substitution inside a heredoc is not the statement's status), and a
# `${unfiltered:-0}` would silently turn "the counter never ran" into a PASS.
case "${cached_builds}|${filtered_builds}|${unfiltered}" in
  *[!0-9\|]*|*'||'*|'|'*|*'|')
    echo "ERROR: build-step counters did not compute (got '${cached_builds}|${filtered_builds}|${unfiltered}')." >&2
    echo "       This gate verified NOTHING — refusing to report success." >&2
    exit 1 ;;
esac

rc=0

# ---- 1: filter values name the real final stage ------------------------------
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

# ---- 2: no cache-importing STEP may lack the filter --------------------------
if [ "$unfiltered" -ne 0 ]; then
  echo "FAIL: $unfiltered of $cached_builds gha-cache-importing build step(s) lack 'no-cache-filters'." >&2
  echo "      Every build importing that cache must set it, or it re-seeds a stale '$stage'" >&2
  echo "      layer for the others. Add 'no-cache-filters: $stage' to the build(s) missing it." >&2
  rc=1
fi

# ---- Makefile source view ----------------------------------------------------
# 1. Fold `\` continuations FIRST: an idiomatic multi-flag recipe puts
#    `buildx build \` and `--cache-from ... \` on different lines, and a
#    line-scoped grep chain sees neither together — a fail-open.
# 2. Strip `#` comments ONLY on non-recipe lines (recipe lines start with TAB).
#    In a Make RECIPE, `#` is not a Make comment — Make passes it to the shell —
#    so a global strip both dropped real flags after a `#` (false PASS) and
#    truncated a line mid-flag (false RED).
mk_src="$(sed -e 's/\r$//' "$MAKEFILE" \
  | sed -E ':a;/\\$/{N;s/\\\n[[:space:]]*/ /;ta}' \
  | sed -E '/^[^\t]/{s/#.*$//}' \
  | sed -E '/^[[:space:]]*@?#/d')"

# Every line that runs a build AND imports a cache.
mk_cached="$(printf '%s\n' "$mk_src" \
  | grep -E '(buildx[[:space:]]+build|docker[[:space:]]+build)' \
  | grep -E 'cache-from' || true)"
mk_cached_n="$(printf '%s' "$mk_cached" | grep -c . || true)"
mk_unfiltered_n="$(printf '%s' "$mk_cached" | grep -vc -- '--no-cache-filter' || true)"
case "$mk_cached_n" in ''|*[!0-9]*) mk_cached_n=0 ;; esac
case "$mk_unfiltered_n" in ''|*[!0-9]*) mk_unfiltered_n=0 ;; esac
[ "$mk_cached_n" -eq 0 ] && mk_unfiltered_n=0

# ---- 3a: cache-importing Makefile builds carry the filter --------------------
if [ "$mk_unfiltered_n" -ne 0 ]; then
  echo "FAIL: $mk_unfiltered_n of $mk_cached_n $MAKEFILE build line(s) import a cache but lack '--no-cache-filter'." >&2
  echo "      Add '--no-cache-filter $stage', or the '$stage' layer is replayed from cache there." >&2
  rc=1
fi

# ---- 3b: those filter values name the same stage -----------------------------
while IFS= read -r value; do
  [ -z "$value" ] && continue
  if [ "$value" != "$stage" ]; then
    echo "FAIL: $MAKEFILE has '--no-cache-filter $value' but the final stage is '$stage'." >&2
    rc=1
  fi
done < <(printf '%s\n' "$mk_src" \
  | grep -oE -- '--no-cache-filter[= ][A-Za-z0-9_.-]+' \
  | sed -E 's/--no-cache-filter[= ]//' || true)

# ---- vacuity ----------------------------------------------------------------
# A gate that examined nothing must not report success. Emptying ci.yml (or
# moving the docker job to another workflow) previously yielded a green `0/0`.
if [ "$cached_builds" -eq 0 ]; then
  echo "ERROR: found ZERO gha-cache-importing build steps in $WORKFLOW." >&2
  echo "       Either the builds moved to another workflow (point \$WORKFLOW at it)" >&2
  echo "       or the parser stopped matching. Refusing to certify a check that" >&2
  echo "       examined nothing." >&2
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  echo "PASS: final stage '$stage'"
  echo "      ci.yml   $filtered_builds/$cached_builds gha-cache-importing build step(s) filtered"
  if [ "$mk_cached_n" -eq 0 ]; then
    # Honest: today no Makefile line both builds AND imports a cache, so 3a has
    # an empty population. Printing a reassuring ratio here would certify a
    # check that examined nothing.
    echo "      $MAKEFILE 0 cache-importing build line(s) — check 3a examined NOTHING"
  else
    echo "      $MAKEFILE $((mk_cached_n - mk_unfiltered_n))/$mk_cached_n cache-importing build line(s) filtered"
  fi
fi
exit "$rc"
