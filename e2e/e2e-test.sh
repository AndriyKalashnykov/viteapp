#!/usr/bin/env bash
# E2E tests for the built viteapp container.
# Exercises nginx health endpoints, SPA fallback, and security headers
# against a locally running image.

set -euo pipefail

BASE="${BASE_URL:-http://localhost:8080}"
PASS=0
FAIL=0

log_pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
log_fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_status() {
  local method="$1" path="$2" expected="$3"
  local status
  status=$(curl -s -o /dev/null -w '%{http_code}' -X "$method" "$BASE$path")
  if [[ "$status" == "$expected" ]]; then
    log_pass "$method $path -> $status"
  else
    log_fail "$method $path -> $status (expected $expected)"
  fi
}

assert_body_contains() {
  local path="$1" needle="$2"
  local body
  body=$(curl -sf "$BASE$path")
  if echo "$body" | grep -qF "$needle"; then
    log_pass "GET $path contains '$needle'"
  else
    log_fail "GET $path missing '$needle'"
  fi
}

assert_header() {
  local path="$1" header="$2" expected_regex="$3"
  local value
  value=$(curl -sI "$BASE$path" | awk -v h="$header" 'tolower($1) == tolower(h":") { sub(/^[^:]+:[ \t]*/, ""); sub(/\r$/, ""); print; exit }')
  if [[ -n "$value" ]] && echo "$value" | grep -Eq "$expected_regex"; then
    log_pass "$path $header: $value"
  else
    log_fail "$path $header: got '$value', expected match '$expected_regex'"
  fi
}

assert_header_absent() {
  local path="$1" header="$2"
  if curl -sI "$BASE$path" | awk -v h="$header" 'tolower($1) == tolower(h":") { found=1 } END { exit !found }'; then
    log_fail "$path should not expose header '$header'"
  else
    log_pass "$path does not expose '$header'"
  fi
}

echo "=== E2E tests against $BASE ==="

# Health endpoints
assert_status GET /internal/isalive 200
assert_status GET /internal/isready 200
# Health endpoints declare text/plain Content-Type and no-store caching (a probe
# must never be cached, and the body must not be sniffed as HTML).
assert_header /internal/isalive Content-Type 'text/plain'
assert_header /internal/isready Content-Type 'text/plain'
assert_header /internal/isalive Cache-Control 'no-store'
assert_header /internal/isready Cache-Control 'no-store'

# SPA fallback: unknown deep links must return index.html (200) so client-side routing works.
assert_status GET /some/spa/route 200
assert_body_contains /some/spa/route '<div id="root"'

# Asset serving: index.html itself. The index must NOT be cached (no-store) so a
# deploy of a new hashed bundle is picked up immediately rather than served stale.
assert_status GET / 200
assert_body_contains / '<div id="root"'
assert_header / Cache-Control 'no-store'

# Hashed bundle URL: discover the JS bundle from index.html and verify it serves correctly.
# Catches Rolldown/terser regressions producing 404 on the bundle.
bundle_path=$(curl -sf "$BASE/" | grep -oE '/assets/[^"]+\.js' | head -1)
if [[ -n "$bundle_path" ]]; then
  assert_status GET "$bundle_path" 200
  assert_header "$bundle_path" Content-Type 'javascript'
  # Hashed assets are immutable + long-lived; a regression dropping this header
  # defeats the content-hash caching strategy.
  assert_header "$bundle_path" Cache-Control 'immutable'
else
  log_fail "GET / did not reference any /assets/*.js bundle"
fi

# 404 negative path: a file-extension URL not in dist/ falls through to the SPA
# catch-all (try_files $uri /index.html), which is intentional. Pin the contract.
assert_status GET /nonexistent.png 200
assert_body_contains /nonexistent.png '<div id="root"'

# Server-level security headers (set globally in nginx.conf, must inherit
# everywhere — test on root, SPA fallback, and BOTH health endpoints to lock
# the inheritance contract. nginx silently shadows all parent add_header
# directives if any location block defines its own add_header.
for path in / /some/spa/route /internal/isalive /internal/isready; do
  assert_header "$path" X-Content-Type-Options 'nosniff'
  assert_header "$path" X-Frame-Options '(SAMEORIGIN|DENY)'
  assert_header "$path" Referrer-Policy '.+'
  assert_header "$path" Permissions-Policy '.+'
  assert_header "$path" Content-Security-Policy "default-src 'self'"
  assert_header "$path" Cross-Origin-Embedder-Policy 'require-corp'
  assert_header "$path" Cross-Origin-Opener-Policy 'same-origin'
  assert_header "$path" Cross-Origin-Resource-Policy 'same-origin'
done

# server_tokens off -> Server header should not leak an nginx version.
assert_header_absent / X-Powered-By

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
