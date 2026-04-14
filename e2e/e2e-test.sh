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
  value=$(curl -sI "$BASE$path" | awk -v h="$header" 'BEGIN{IGNORECASE=1} tolower($1) == tolower(h":") { sub(/^[^:]+:[ \t]*/, ""); sub(/\r$/, ""); print; exit }')
  if [[ -n "$value" ]] && echo "$value" | grep -Eq "$expected_regex"; then
    log_pass "$path $header: $value"
  else
    log_fail "$path $header: got '$value', expected match '$expected_regex'"
  fi
}

assert_header_absent() {
  local path="$1" header="$2"
  if curl -sI "$BASE$path" | awk -v h="$header" 'BEGIN{IGNORECASE=1} tolower($1) == tolower(h":") { found=1 } END { exit !found }'; then
    log_fail "$path should not expose header '$header'"
  else
    log_pass "$path does not expose '$header'"
  fi
}

echo "=== E2E tests against $BASE ==="

# Health endpoints
assert_status GET /internal/isalive 200
assert_status GET /internal/isready 200

# SPA fallback: unknown deep links must return index.html (200) so client-side routing works.
assert_status GET /some/spa/route 200
assert_body_contains /some/spa/route '<div id="root"'

# Asset serving: index.html itself.
assert_status GET / 200
assert_body_contains / '<div id="root"'

# Security headers (configured in nginx/nginx.conf).
assert_header / X-Content-Type-Options 'nosniff'
assert_header / X-Frame-Options '(SAMEORIGIN|DENY)'
assert_header / Referrer-Policy '.+'
assert_header / Permissions-Policy '.+'

# server_tokens off -> Server header should not leak an nginx version.
assert_header_absent / X-Powered-By

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
