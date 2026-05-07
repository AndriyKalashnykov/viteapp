#!/usr/bin/env bash
# Parse every ```mermaid fenced block in README.md / CLAUDE.md via the pinned
# minlag/mermaid-cli Docker image. Same engine GitHub uses to render Mermaid,
# so a parse pass here means the README will render on github.com.
#
# Invocation: scripts/mermaid-lint.sh <mermaid-cli-version>
# Called from Makefile so the version pin lives in one place.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <mermaid-cli-version>" >&2
  exit 2
fi
version="$1"

shopt -s nullglob
files=()
for f in README.md CLAUDE.md; do
  [[ -f "$f" ]] && grep -qF '```mermaid' "$f" && files+=("$f")
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "mermaid-lint: no mermaid blocks found"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

idx=0
for f in "${files[@]}"; do
  awk -v dir="$tmp" '
    /^```mermaid$/ { inblk=1; idx++; out=sprintf("%s/%d.mmd", dir, idx); next }
    /^```$/        { if (inblk) { close(out); inblk=0 } next }
    inblk          { print > out }
  ' "$f"
done

for mmd in "$tmp"/*.mmd; do
  [[ -f "$mmd" ]] || continue
  echo "mermaid-lint: parsing $mmd"
  docker run --rm -u "$(id -u):$(id -g)" -v "$tmp":/data \
    "minlag/mermaid-cli:${version}" \
    -i "/data/$(basename "$mmd")" \
    -o "/data/$(basename "$mmd" .mmd).svg" >/dev/null
done

echo "mermaid-lint passed."
