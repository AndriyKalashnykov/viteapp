.DEFAULT_GOAL := help

APP_NAME   := viteapp
CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Tool Versions (pinned) ===
# renovate: datasource=github-releases depName=nvm-sh/nvm extractVersion=^v(?<version>.*)$
NVM_VERSION      := 0.40.4
# NODE_VERSION is derived from .nvmrc (single source of truth — Dockerfile,
# CI, and Makefile all consume it). Cannot be tracked by Renovate (major-only
# values don't match a datasource version pattern).
NODE_VERSION     := $(shell cat .nvmrc 2>/dev/null || echo 24)
# renovate: datasource=npm depName=pnpm
PNPM_VERSION     := 10.33.0
# renovate: datasource=github-releases depName=nektos/act extractVersion=^v(?<version>.*)$
ACT_VERSION      := 0.2.87
# renovate: datasource=github-releases depName=hadolint/hadolint extractVersion=^v(?<version>.*)$
HADOLINT_VERSION := 2.14.0
# renovate: datasource=github-releases depName=aquasecurity/trivy extractVersion=^v(?<version>.*)$
TRIVY_VERSION    := 0.69.3
# renovate: datasource=github-releases depName=zricethezav/gitleaks extractVersion=^v(?<version>.*)$
GITLEAKS_VERSION := 8.30.1
# renovate: datasource=github-releases depName=zaproxy/zaproxy extractVersion=^v(?<version>.*)$
ZAP_VERSION      := 2.17.0

# Ensure tools installed to ~/.local/bin (hadolint, act) are on PATH for all
# recipes — needed inside the act runner container where this path is not
# preconfigured. Exported so every sub-shell the recipes spawn inherits it.
export PATH := $(HOME)/.local/bin:$(PATH)

# CI-safe pnpm install: uses --frozen-lockfile when CI=true (set by GitHub Actions)
PNPM_INSTALL := pnpm install $(if $(CI),--frozen-lockfile,)

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands:"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-30s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install dependencies if not present (node, pnpm, docker, git)
deps:
	@command -v node >/dev/null 2>&1 || { echo "Installing Node.js $(NODE_VERSION) via nvm..."; \
		if command -v nvm >/dev/null 2>&1; then \
			nvm install $(NODE_VERSION); \
		elif [ -s "$$HOME/.nvm/nvm.sh" ]; then \
			. "$$HOME/.nvm/nvm.sh" && nvm install $(NODE_VERSION); \
		else \
			echo "Installing nvm $(NVM_VERSION)..."; \
			curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
			export NVM_DIR="$$HOME/.nvm"; \
			. "$$NVM_DIR/nvm.sh" && nvm install $(NODE_VERSION); \
		fi; \
	}
	@command -v pnpm >/dev/null 2>&1 || { echo "Installing pnpm $(PNPM_VERSION) via corepack..."; \
		command -v corepack >/dev/null 2>&1 || { echo "Error: corepack not found; upgrade Node to >=16.10"; exit 1; }; \
		corepack enable && corepack prepare pnpm@$(PNPM_VERSION) --activate; \
	}
	@command -v docker >/dev/null 2>&1 || echo "WARNING: docker is not installed (needed for 'make image-build'). Install from https://docs.docker.com/get-docker/"
	@command -v git >/dev/null 2>&1 || echo "WARNING: git is not installed (needed for 'make release'). Install from https://git-scm.com/downloads"

#deps-act: @ Install act for local CI runs
deps-act: deps
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b $$HOME/.local/bin v$(ACT_VERSION); \
	}

#deps-hadolint: @ Install hadolint for Dockerfile linting
deps-hadolint:
	@command -v hadolint >/dev/null 2>&1 || { echo "Installing hadolint $(HADOLINT_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL -o /tmp/hadolint https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-Linux-x86_64 && \
		install -m 755 /tmp/hadolint $$HOME/.local/bin/hadolint && \
		rm -f /tmp/hadolint; \
	}

#deps-trivy: @ Install trivy for filesystem vulnerability scanning
deps-trivy:
	@command -v trivy >/dev/null 2>&1 || { echo "Installing trivy $(TRIVY_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL https://github.com/aquasecurity/trivy/releases/download/v$(TRIVY_VERSION)/trivy_$(TRIVY_VERSION)_Linux-64bit.tar.gz | \
			tar -xz -C $$HOME/.local/bin trivy; \
	}

#deps-gitleaks: @ Install gitleaks for secret scanning
deps-gitleaks:
	@command -v gitleaks >/dev/null 2>&1 || { echo "Installing gitleaks $(GITLEAKS_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL https://github.com/gitleaks/gitleaks/releases/download/v$(GITLEAKS_VERSION)/gitleaks_$(GITLEAKS_VERSION)_linux_x64.tar.gz | \
			tar -xz -C $$HOME/.local/bin gitleaks; \
	}

#clean: @ Remove node_modules/, dist/, coverage/, and zap-output/
clean:
	@rm -rf node_modules/ dist/ coverage/ zap-output/

#install: @ Install project dependencies via pnpm
install: deps
	@$(PNPM_INSTALL)

#lint: @ Run ESLint and hadolint on source files
lint: install deps-hadolint
	@pnpm lint
	@hadolint Dockerfile

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
trivy-fs: deps-trivy
	@trivy fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH --exit-code 1 --ignore-unfixed .

#secrets: @ Scan repository for leaked secrets via gitleaks
secrets: deps-gitleaks
	@gitleaks detect --source . --verbose --redact --no-banner

#static-check: @ Composite quality gate (format-check, lint, vulncheck, trivy-fs, secrets)
static-check: format-check lint vulncheck trivy-fs secrets
	@echo "static-check passed."

#deps-update: @ Update dependencies to latest compatible versions (pnpm update)
deps-update: install
	@pnpm update

#deps-prune: @ Check for unused dependencies
deps-prune: install
	@echo "=== Dependency Pruning ==="
	@npx --yes depcheck --ignores="@types/*" 2>/dev/null || true
	@echo "=== Pruning complete ==="

#deps-prune-check: @ Verify no prunable dependencies (CI gate)
deps-prune-check: install
	@npx --yes depcheck --ignores="@types/*"

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

#image-stop: @ Stop Docker container
image-stop:
	@docker stop $(APP_NAME) 2>/dev/null || true
	@docker rm -f viteapp-test 2>/dev/null || true

#dast: @ ZAP baseline DAST scan against the built image (mirrors CI gate)
dast: image-build
	@docker rm -f viteapp-test 2>/dev/null || true
	@docker run -d --name=viteapp-test -p 8080:8080 $(APP_NAME):$(CURRENTTAG) >/dev/null
	@echo "Waiting for nginx to become healthy..."
	@end=$$(( $$(date +%s) + 30 )); \
		while [ $$(date +%s) -lt $$end ]; do \
			curl -fsS http://localhost:8080/internal/isalive >/dev/null 2>&1 && break; \
			sleep 1; \
		done
	@mkdir -p zap-output && chmod 777 zap-output
	@docker run --rm --network host \
		-v "$(PWD)/zap-output:/zap/wrk:rw" \
		ghcr.io/zaproxy/zaproxy:$(ZAP_VERSION) \
		zap-baseline.py \
			-t http://localhost:8080 \
			-I \
			-r zap-report.html \
			-J zap-report.json \
			-w zap-report.md \
		|| EXIT=$$?; \
		docker rm -f viteapp-test >/dev/null; \
		exit $${EXIT:-0}
	@echo "DAST report: $(PWD)/zap-output/zap-report.html"

#release: @ Create and push a new tag (interactive prompt for vX.Y.Z)
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		git tag $$newtag && \
		git push origin $$newtag && \
		echo "Done."'

#ci-run: @ Run GitHub Actions workflow locally using act (simulates push to main)
ci-run: deps-act
	@docker container prune -f 2>/dev/null || true
	@act push --container-architecture linux/amd64 --artifact-server-path /tmp/act-artifacts

#ci-run-tag: @ Run GitHub Actions workflow locally with a tag event (exercises docker job + DAST)
ci-run-tag: deps-act
	@docker container prune -f 2>/dev/null || true
	@TAG="$$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"; \
		echo '{"ref":"refs/tags/'"$$TAG"'","ref_type":"tag","repository":{"full_name":"andriykalashnykov/viteapp","name":"viteapp","owner":{"login":"andriykalashnykov"}}}' > /tmp/act-tag-event.json
	@echo "Simulating tag push event from /tmp/act-tag-event.json"
	@act push \
		--eventpath /tmp/act-tag-event.json \
		--container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts || true
	@echo "Note: cosign signing will fail under act because OIDC tokens are not available locally — expected."

#renovate: @ Run Renovate locally in dry-run mode (requires GITHUB_TOKEN)
# Token is passed via env var (RENOVATE_TOKEN) so it never appears in the
# command line — `make -n`, `set -x`, `ps aux`, and shell history would all
# leak it if it were interpolated as `--token=$(GITHUB_TOKEN)` here.
renovate: install
	@if [ -z "$$GITHUB_TOKEN" ]; then \
		echo "Error: GITHUB_TOKEN env var not set"; exit 1; \
	fi
	@RENOVATE_TOKEN="$$GITHUB_TOKEN" LOG_LEVEL=debug \
		npx --yes renovate --dry-run=full --platform=local --repository-cache=reset

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@npx --yes --package renovate -- renovate-config-validator --strict renovate.json

.PHONY: help deps deps-act deps-hadolint deps-trivy deps-gitleaks clean \
	install lint build test coverage-check vulncheck trivy-fs secrets \
	static-check deps-update deps-prune deps-prune-check run format \
	format-check ci image-build image-run image-stop dast release \
	ci-run ci-run-tag renovate renovate-validate
