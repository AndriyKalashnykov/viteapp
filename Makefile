.DEFAULT_GOAL := help

APP_NAME   := viteapp
CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Sources of truth ===
# Node:     .nvmrc (mise reads it natively)
# pnpm:     package.json `packageManager` field (corepack reads it natively)
# Binary tools (act, hadolint, trivy, gitleaks): .mise.toml (aqua backend)
# Docker images below: pinned here with `# renovate:` annotations.
NODE_VERSION := $(shell cat .nvmrc 2>/dev/null || echo 24)
# renovate: datasource=github-releases depName=zaproxy/zaproxy extractVersion=^v(?<version>.*)$
ZAP_VERSION         := 2.17.0
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.16.0
# renovate: datasource=docker depName=plantuml/plantuml
PLANTUML_VERSION    := 1.2026.6
# renovate: datasource=npm depName=renovate
RENOVATE_VERSION    := 43.243.2
# renovate: datasource=npm depName=depcheck
DEPCHECK_VERSION    := 1.4.7
# renovate: datasource=npm depName=@lhci/cli
LHCI_VERSION        := 0.15.1

# Ensure tools installed by mise (~/.local/share/mise/shims) and ~/.local/bin
# (corepack-managed pnpm) are on PATH for every recipe — needed inside the act
# runner container where these paths are not preconfigured.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# CI-safe pnpm install: uses --frozen-lockfile when CI=true (set by GitHub Actions)
PNPM_INSTALL := pnpm install $(if $(CI),--frozen-lockfile,)

# Corepack provisions the pnpm version pinned in package.json `packageManager`
# on first use of an uncached version (e.g. right after a pnpm major bump). The
# first corepack/pnpm call then prints an interactive download-consent prompt
# and BLOCKS on stdin — hanging `make deps` in CI and on cold machines.
# Auto-confirming is safe: the version is already pinned deterministically, so
# this only suppresses the consent step, it does not change what is installed.
export COREPACK_ENABLE_DOWNLOAD_PROMPT := 0

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands:"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-30s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install dev tooling (mise + Node + pnpm + binary tools from .mise.toml)
deps:
	@# Local dev: bootstrap mise if missing (installs to ~/.local/bin, no sudo).
	@# CI uses actions/setup-node + native runners, so skip via CI guard.
	@if [ -z "$$CI" ] && ! command -v mise >/dev/null 2>&1; then \
		echo "Installing mise (portfolio-wide version manager, no root required)..."; \
		curl -fsSL https://mise.run | sh; \
		echo "mise installed at ~/.local/bin/mise. Activate in your shell:"; \
		echo '  bash: echo '"'"'eval "$$(~/.local/bin/mise activate bash)"'"'"' >> ~/.bashrc'; \
		echo '  zsh:  echo '"'"'eval "$$(~/.local/bin/mise activate zsh)"'"'"'  >> ~/.zshrc'; \
		echo "Then re-run 'make deps' to install the rest of the toolchain."; \
		exit 0; \
	fi
	@# mise install reads .mise.toml + .nvmrc and installs every pinned tool
	@# (Node from .nvmrc, plus act / hadolint / trivy / gitleaks via aqua).
	@if [ -z "$$CI" ] && command -v mise >/dev/null 2>&1; then \
		mise install --yes; \
	fi
	@command -v node >/dev/null 2>&1 || { echo "Error: node not found. Install mise (https://mise.run) or Node $(NODE_VERSION) manually."; exit 1; }
	@command -v pnpm >/dev/null 2>&1 || { \
		command -v corepack >/dev/null 2>&1 || { echo "Error: corepack not found; upgrade Node to >=16.10"; exit 1; }; \
		echo "Activating pnpm via corepack (version pin lives in package.json)..."; \
		corepack enable pnpm; \
	}
	@command -v docker >/dev/null 2>&1 || echo "WARNING: docker is not installed (needed for 'make image-build'). Install from https://docs.docker.com/get-docker/"
	@command -v git >/dev/null 2>&1 || echo "WARNING: git is not installed (needed for 'make release'). Install from https://git-scm.com/downloads"

#clean: @ Remove node_modules/, dist/, coverage/, and zap-output/
clean:
	@rm -rf node_modules/ dist/ coverage/ zap-output/ playwright-report/ test-results/ .lighthouseci/

#install: @ Install project dependencies via pnpm
install: deps
	@$(PNPM_INSTALL)

#lint: @ Run ESLint, hadolint, and shell-script executable-bit guard
lint: install
	@pnpm lint
	@hadolint Dockerfile
	@# Guard against subagent-created scripts landing without +x bit
	@# (Write tool defaults to 0644). Real incident: kind-cluster 2026-04-17.
	@find scripts -type f -name '*.sh' -not -executable -print -exec false {} + 2>/dev/null \
		|| { echo "Error: shell scripts above are missing executable bit. Run: chmod +x <file>"; exit 1; }

#build: @ Type-check with tsc and build for production via Vite
build: install
	@pnpm build

#test: @ Run Vitest tests
test: install
	@pnpm test

#coverage-check: @ Run Vitest with coverage thresholds (CI gate, 80%)
coverage-check: install
	@pnpm exec vitest run --coverage

#vulncheck: @ Check for known vulnerabilities in dependencies (moderate+)
vulncheck: install
	@pnpm audit --audit-level=moderate

#trivy-fs: @ Trivy filesystem scan (vuln, secret, misconfig)
trivy-fs: deps
	@trivy fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH --exit-code 1 --ignore-unfixed .

#secrets: @ Scan repository for leaked secrets via gitleaks
secrets: deps
	@gitleaks detect --source . --verbose --redact --no-banner

#mermaid-lint: @ Parse every ```mermaid fenced block in README.md / CLAUDE.md via pinned mermaid-cli
mermaid-lint:
	@./scripts/mermaid-lint.sh $(MERMAID_CLI_VERSION)

# === Architecture diagrams (PlantUML C4) ===
# Source .puml committed under docs/diagrams/; rendered PNG committed under
# docs/diagrams/out/ so github.com shows them with no build step. Rendered via
# the pinned plantuml/plantuml Docker image for byte-reproducibility.
DIAGRAM_DIR   := docs/diagrams
DIAGRAM_SRC   := $(wildcard $(DIAGRAM_DIR)/*.puml)
DIAGRAM_OUT   := $(patsubst $(DIAGRAM_DIR)/%.puml,$(DIAGRAM_DIR)/out/%.png,$(DIAGRAM_SRC))
# Version-stamped sentinel: a PLANTUML_VERSION bump changes the stamp's NAME, so
# the old stamp no longer satisfies the prereq and every PNG re-renders — catches
# the "renderer bumped but PNG not regenerated" drift the .puml mtime check misses.
DIAGRAM_STAMP := $(DIAGRAM_DIR)/out/.plantuml-$(PLANTUML_VERSION).stamp

#diagrams: @ Render PlantUML architecture diagrams (docs/diagrams/*.puml) to PNG
diagrams: $(DIAGRAM_OUT)

$(DIAGRAM_DIR)/out/%.png: $(DIAGRAM_DIR)/%.puml $(DIAGRAM_STAMP)
	@PLANTUML_VERSION=$(PLANTUML_VERSION) ./scripts/render-diagrams.sh $<

$(DIAGRAM_STAMP):
	@mkdir -p $(DIAGRAM_DIR)/out
	@rm -f $(DIAGRAM_DIR)/out/.plantuml-*.stamp
	@touch $@

#diagrams-clean: @ Remove rendered diagram artefacts
diagrams-clean:
	@rm -rf $(DIAGRAM_DIR)/out

#diagrams-check: @ Verify committed diagrams match current PlantUML source (CI drift gate)
diagrams-check: diagrams
	@git diff --exit-code -- $(DIAGRAM_DIR)/out || \
		{ echo "ERROR: diagram source changed but rendered PNG not updated. Run 'make diagrams' and commit."; exit 1; }

#check-minifier-deps: @ Verify every minifier named in vite.config.ts is a declared dependency (guards the esbuild/terser optional-peer trap)
check-minifier-deps:
	@node scripts/check-minifier-deps.mjs

#check-node-alignment: @ Verify the Node version matches across .nvmrc and Dockerfile (fails fast on Renovate split drift)
check-node-alignment:
	@nvmrc=$$(tr -d '[:space:]' < .nvmrc); \
		dockerfile=$$(grep -oE 'node:[0-9]+\.[0-9]+\.[0-9]+' Dockerfile | head -1 | cut -d: -f2); \
		if [ "$$nvmrc" != "$$dockerfile" ]; then \
			echo "ERROR: Node version disagrees across files:"; \
			printf "  %-12s %s\n" .nvmrc "$$nvmrc" Dockerfile "$$dockerfile"; \
			echo "  Bump both together (Renovate groups them via the 'Node toolchain' rule)."; \
			exit 1; \
		fi

#static-check: @ Composite quality gate (check-node-alignment, check-minifier-deps, format-check, lint, vulncheck, trivy-fs, secrets, mermaid-lint, diagrams-check)
static-check: check-node-alignment check-minifier-deps format-check lint vulncheck trivy-fs secrets mermaid-lint diagrams-check
	@echo "static-check passed."

#deps-update: @ Update dependencies to latest compatible versions (pnpm update)
deps-update: install
	@pnpm update

#deps-prune: @ Check for unused dependencies
deps-prune: install
	@echo "=== Dependency Pruning ==="
	@npx --yes depcheck@$(DEPCHECK_VERSION) --ignores="@types/*" 2>/dev/null || true
	@echo "=== Pruning complete ==="

#deps-prune-check: @ Verify no prunable dependencies (CI gate)
deps-prune-check: install
	@npx --yes depcheck@$(DEPCHECK_VERSION) --ignores="@types/*"

#run: @ Start Vite dev server with HMR
run: install
	@pnpm dev

#format: @ Format source files with Prettier
format: install
	@pnpm prettier

#format-check: @ Check formatting without writing
format-check: install
	@pnpm prettier:diff

#ci: @ Run full local CI pipeline (install, static-check, coverage-check, build, deps-prune-check)
ci: install static-check coverage-check build deps-prune-check
	@echo "CI pipeline passed."

#image-build: @ Build Docker image
image-build: build
	@docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) .

#image-run: @ Run Docker container on port 8080
image-run: image-stop
	@docker run --rm -p 8080:8080 --name $(APP_NAME) $(APP_NAME):$(CURRENTTAG)

#image-stop: @ Stop the production Docker container (test container is owned by e2e/dast targets)
image-stop:
	@docker stop $(APP_NAME) 2>/dev/null || true

#image-cst: @ Container-structure-test against the built image (USER, EXPOSE, file presence)
image-cst: image-build deps
	@container-structure-test test --image $(APP_NAME):$(CURRENTTAG) --config container-structure-test.yaml

#e2e: @ End-to-end tests against the built container (health, SPA fallback, security headers)
e2e: image-build
	@docker rm -f viteapp-test 2>/dev/null || true
	@docker run -d --name=viteapp-test -p 8080:8080 $(APP_NAME):$(CURRENTTAG) >/dev/null
	@echo "Waiting for nginx to become healthy..."
	@end=$$(( $$(date +%s) + 30 )); \
		while [ $$(date +%s) -lt $$end ]; do \
			curl -fsS http://localhost:8080/internal/isalive >/dev/null 2>&1 && break; \
			sleep 1; \
		done
	@./e2e/e2e-test.sh; EXIT=$$?; \
		docker rm -f viteapp-test >/dev/null; \
		exit $$EXIT

#e2e-browser: @ Playwright Chromium smoke against the built container (counter, theme toggle, CSP)
e2e-browser: install image-build
	@npx playwright install chromium
	@docker rm -f viteapp-pw 2>/dev/null || true
	@docker run -d --name=viteapp-pw -p 8080:8080 $(APP_NAME):$(CURRENTTAG) >/dev/null
	@echo "Waiting for nginx to become healthy..."
	@end=$$(( $$(date +%s) + 30 )); \
		while [ $$(date +%s) -lt $$end ]; do \
			curl -fsS http://localhost:8080/internal/isalive >/dev/null 2>&1 && break; \
			sleep 1; \
		done
	@BASE_URL=http://localhost:8080 npx playwright test; EXIT=$$?; \
		docker rm -f viteapp-pw >/dev/null; \
		exit $$EXIT

#lighthouse: @ Lighthouse CI budgets (perf/a11y/best-practices/SEO) against the built container
lighthouse: install image-build
	@docker rm -f viteapp-lh 2>/dev/null || true
	@docker run -d --name=viteapp-lh -p 8080:8080 $(APP_NAME):$(CURRENTTAG) >/dev/null
	@echo "Waiting for nginx to become healthy..."
	@end=$$(( $$(date +%s) + 30 )); \
		while [ $$(date +%s) -lt $$end ]; do \
			curl -fsS http://localhost:8080/internal/isalive >/dev/null 2>&1 && break; \
			sleep 1; \
		done
	@npx --yes @lhci/cli@$(LHCI_VERSION) autorun --config=lighthouserc.json; EXIT=$$?; \
		docker rm -f viteapp-lh >/dev/null; \
		exit $$EXIT

#dast: @ ZAP baseline DAST scan against the built image (mirrors CI gate, fail-on-warn)
dast: image-build
	@docker rm -f viteapp-test 2>/dev/null || true
	@docker run -d --name=viteapp-test -p 8080:8080 $(APP_NAME):$(CURRENTTAG) >/dev/null
	@echo "Waiting for nginx to become healthy..."
	@end=$$(( $$(date +%s) + 30 )); \
		while [ $$(date +%s) -lt $$end ]; do \
			curl -fsS http://localhost:8080/internal/isalive >/dev/null 2>&1 && break; \
			sleep 1; \
		done
	@rm -rf zap-output 2>/dev/null || docker run --rm --user 0 -v "$(PWD):/work" -w /work --entrypoint rm ghcr.io/zaproxy/zaproxy:$(ZAP_VERSION) -rf zap-output
	@mkdir -p zap-output && chmod 777 zap-output
	@echo "DAST report will be written to: $(PWD)/zap-output/zap-report.html"
	@docker run --rm --network host \
		-v "$(PWD)/zap-output:/zap/wrk:rw" \
		-v "$(PWD)/.zap/baseline-rules.tsv:/zap/wrk/baseline-rules.tsv:ro" \
		ghcr.io/zaproxy/zaproxy:$(ZAP_VERSION) \
		zap-baseline.py \
			-t http://localhost:8080 \
			-c baseline-rules.tsv \
			-r zap-report.html \
			-J zap-report.json \
			-w zap-report.md; EXIT=$$?; \
		docker rm -f viteapp-test >/dev/null; \
		exit $${EXIT:-0}

#release: @ Create and push a new tag (interactive prompt for vX.Y.Z)
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		git tag $$newtag && \
		git push origin $$newtag && \
		echo "Done."'

#ci-run: @ Run GitHub Actions workflow locally using act (simulates push to main)
# Use bash-array `--secret KEY` env-only form when secrets are eventually
# needed — never `--secret KEY=$$VAR` (value would land in `ps -ef` argv).
# `--var ACT=true` powers `if: ${{ vars.ACT != 'true' }}` job/step gates
# (dast skip, etc.). Real GitHub Actions runs see `vars.ACT` unset.
ci-run: deps
	@docker container prune -f 2>/dev/null || true
	@docker rm -f viteapp-test viteapp-smoke viteapp-dast 2>/dev/null || true
	@act push --container-architecture linux/amd64 --artifact-server-path /tmp/act-artifacts --var ACT=true

#ci-run-tag: @ Run GitHub Actions workflow locally with a tag event (exercises docker job + DAST)
ci-run-tag: deps
	@docker container prune -f 2>/dev/null || true
	@TAG="$$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"; \
		echo '{"ref":"refs/tags/'"$$TAG"'","ref_type":"tag","repository":{"full_name":"andriykalashnykov/viteapp","name":"viteapp","owner":{"login":"andriykalashnykov"}}}' > /tmp/act-tag-event.json
	@echo "Simulating tag push event from /tmp/act-tag-event.json"
	@# cosign signing is the only step that legitimately fails under act (no
	@# OIDC issuer locally). The act-runner exits 0 by ignoring exit code 137
	@# from sigstore/cosign-installer's keyless-OIDC mint step; every other
	@# job/step failure still propagates. Do NOT add a blanket `|| true`.
	@docker rm -f viteapp-test viteapp-smoke viteapp-dast 2>/dev/null || true
	@act push \
		--eventpath /tmp/act-tag-event.json \
		--container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts \
		--var ACT=true \
		--env ACT_FAIL_ON_NO_JOBS=false

#renovate: @ Run Renovate locally in dry-run mode (requires GITHUB_TOKEN)
# Token is passed via env var (RENOVATE_TOKEN) so it never appears in the
# command line — `make -n`, `set -x`, `ps aux`, and shell history would all
# leak it if it were interpolated as `--token=$(GITHUB_TOKEN)` here.
renovate: install
	@if [ -z "$$GITHUB_TOKEN" ]; then \
		echo "Error: GITHUB_TOKEN env var not set"; exit 1; \
	fi
	@RENOVATE_TOKEN="$$GITHUB_TOKEN" LOG_LEVEL=debug \
		npx --yes renovate@$(RENOVATE_VERSION) --dry-run=full --platform=local --repository-cache=reset

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@npx --yes --package renovate@$(RENOVATE_VERSION) -- renovate-config-validator --strict renovate.json

.PHONY: help deps clean install lint build test coverage-check vulncheck \
	trivy-fs secrets check-node-alignment check-minifier-deps static-check deps-update deps-prune \
	deps-prune-check run format format-check ci image-build image-run \
	image-stop image-cst e2e e2e-browser lighthouse dast release ci-run ci-run-tag renovate \
	renovate-validate mermaid-lint diagrams diagrams-clean diagrams-check
