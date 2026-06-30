#!/usr/bin/env bash
# Render a single PlantUML source file to PNG under docs/diagrams/out/ via the
# pinned plantuml/plantuml Docker image — the same renderer CI uses, so the
# committed PNGs are byte-reproducible across machines.
#
# Usage: scripts/render-diagrams.sh <path/to/file.puml>
# PLANTUML_VERSION must be exported by the caller (Makefile) so the pin lives
# in one place.

set -euo pipefail

src="${1:?usage: render-diagrams.sh <file.puml>}"
version="${PLANTUML_VERSION:?PLANTUML_VERSION must be set}"
dir="docs/diagrams"

# Skip under act (Docker-in-Docker bind-mount limitation, identical to
# scripts/mermaid-lint.sh): the act-runner's filesystem isn't visible to the
# host Docker daemon, so `docker run -v "$PWD/...":/work` lands an empty /work
# and PlantUML errors. Real GitHub Actions runners (no DinD) render fine, and
# `make diagrams` covers it natively on the host. The diagrams-check git-diff
# then sees no change under act, so the gate passes there without rendering.
if [[ "${ACT:-false}" == "true" ]]; then
  echo "render-diagrams: skipped under act (DinD bind-mount; covered by make diagrams on host)"
  exit 0
fi

mkdir -p "$dir/out"

# --user keeps output owned by the host user (the image runs as root by
# default, which would leave root:root PNGs polluting git status).
# HOME=/tmp + _JAVA_OPTIONS=-Duser.home=/tmp avoid the user.home='?' font-cache
# footgun (a UID with no /etc/passwd entry makes the JRE materialise
# docs/diagrams/?/.java/... inside the repo on every render).
docker run --rm -v "$PWD/$dir:/work" -w /work \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e _JAVA_OPTIONS=-Duser.home=/tmp \
  "plantuml/plantuml:${version}" \
  -tpng -o out "$(basename "$src")"
