#!/usr/bin/env bash
#
# Assert that the image's `apk upgrade` layer ACTUALLY RAN.
#
# WHY THIS EXISTS (a mechanism gate, not an outcome gate)
# ------------------------------------------------------
# The Dockerfile's `server` stage runs `apk upgrade --no-cache`. Its BuildKit
# cache key is (command string + parent layer digest); the parent is a PINNED
# digest, so neither input encodes the Alpine package index. The layer therefore
# stays cache-valid indefinitely while the index moves daily — the patch step is
# replayed rather than executed, and the image silently ships the base image's
# unpatched packages. Measured 2026-07-20: the layer logged `#14 CACHED` in CI
# while Trivy reported 8 fixable HIGHs (c-ares, libexpat x3, curl/libcurl).
#
# The workflow's `no-cache-filters: server` is the fix. This is the ASSERTION
# that the fix is working, and it is deliberately a check on the MECHANISM
# ("did the patch run?") rather than on the OUTCOME ("are there scored CVEs?"):
#
#   * Its RED is cheap and always available — it goes red on any un-upgraded
#     Alpine base right now. A Trivy RED requires a scored CVE to exist in a
#     vulnerability DB, so you cannot demonstrate that gate on demand, which is
#     why nobody had ever proven it fires.
#   * It is strictly more sensitive: a package can be upgradable before anyone
#     scores a CVE against it (freetype/tzdata were upgradable on the old base
#     while carrying no HIGH).
#   * It has no vulnerability-DB freshness dependency and is unaffected by
#     Trivy's `--ignore-unfixed`.
#
# It does NOT replace the Trivy scan: Trivy catches vulnerabilities in artifacts
# `apk` cannot fix (e.g. the nginx binary itself when upstream has not rebuilt).
# Mechanism gate = "did the patch run"; outcome gate = "does it matter".
# Neither subsumes the other — run both.
#
# REQUIREMENTS: `--user 0` (the image is USER 101 and cannot write
# /var/cache/apk) and network egress to the Alpine mirror.
#
# RED-proof (re-run this any time you doubt the gate):
#   docker build -q -t apkgate:red - <<'EOF'
#   FROM nginx:1.31.2-alpine@sha256:35cd77497979abe70dc8d26f5ae60811eea233a2eb5dc03c2ee30972caeb303e
#   EOF
#   ./scripts/check-apk-upgraded.sh apkgate:red   # MUST exit non-zero
#
set -euo pipefail

IMAGE="${1:-}"
if [ -z "$IMAGE" ]; then
  echo "usage: $0 <image-ref>" >&2
  exit 2
fi

# Fail if the image is not present locally. Without this, a typo'd ref would
# make `docker run` PULL a same-named image from a registry and cheerfully
# assert something about an artifact this build never produced.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "ERROR: image '$IMAGE' is not present locally — refusing to scan a pulled substitute." >&2
  exit 1
fi

echo "Checking that the apk upgrade layer ran in '$IMAGE'..."

# `apk list --upgradable` prints one line per upgradable package, each
# containing 'upgradable from:'. Anchoring on that string (rather than counting
# non-empty lines) keeps stray warnings from being miscounted as findings.
#
# NOTE the `|| true`: `grep -c` exits 1 when the count is zero, which under
# `set -e` would kill this script on exactly the success path.
upgradable="$(
  docker run --rm --user 0 --entrypoint sh "$IMAGE" -c '
    apk update >/dev/null 2>&1 || { echo "APK_UPDATE_FAILED"; exit 0; }
    apk list --upgradable 2>/dev/null || true
  ' | grep 'upgradable from:' || true
)"

if printf '%s' "$upgradable" | grep -q 'APK_UPDATE_FAILED'; then
  echo "ERROR: 'apk update' failed inside the image (no network egress to the Alpine mirror?)." >&2
  echo "       Refusing to report success — this gate cannot verify anything without the index." >&2
  exit 1
fi

count="$(printf '%s' "$upgradable" | grep -c 'upgradable from:' || true)"

if [ "$count" -ne 0 ]; then
  echo "FAIL: $count package(s) still upgradable — the apk upgrade layer did not run." >&2
  echo "      Most likely a BuildKit cache hit replayed the layer. Confirm that every" >&2
  echo "      build importing this cache sets 'no-cache-filters: server'." >&2
  printf '%s\n' "$upgradable" >&2
  exit 1
fi

echo "PASS: 0 packages upgradable — the apk upgrade layer genuinely executed."
