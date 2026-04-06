.DEFAULT_GOAL := help

APP_NAME   := viteapp
CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Tool Versions (pinned) ===
# renovate: datasource=github-releases depName=nvm-sh/nvm extractVersion=^v(?<version>.*)$
NVM_VERSION      := 0.40.4
NODE_VERSION     := 24
# renovate: datasource=npm depName=pnpm
PNPM_VERSION     := 10.33.0
# renovate: datasource=github-releases depName=nektos/act extractVersion=^v(?<version>.*)$
ACT_VERSION      := 0.2.87
# renovate: datasource=github-releases depName=hadolint/hadolint extractVersion=^v(?<version>.*)$
HADOLINT_VERSION := 2.14.0

# CI-safe pnpm install: uses --frozen-lockfile when CI=true (set by GitHub Actions)
PNPM_INSTALL := pnpm install $(if $(CI),--frozen-lockfile,)

# Helper: source nvm in a subshell (nvm is a shell function, not a binary)
define nvm-exec
bash -c 'export NVM_DIR="$$HOME/.nvm"; [ -s "$$NVM_DIR/nvm.sh" ] && . "$$NVM_DIR/nvm.sh" && $(1)'
endef

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands:"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-30s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install dependencies if not present (node, pnpm, docker, git)
deps:
	@echo "Checking dependencies..."
	@command -v node >/dev/null 2>&1 || { echo "Installing Node.js via nvm..."; \
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
	@command -v pnpm >/dev/null 2>&1 || { echo "Installing pnpm $(PNPM_VERSION)..."; \
		if command -v corepack >/dev/null 2>&1; then \
			corepack enable && corepack prepare pnpm@$(PNPM_VERSION) --activate; \
		else \
			npm install -g pnpm@$(PNPM_VERSION); \
		fi; \
	}
	@command -v docker >/dev/null 2>&1 || echo "WARNING: docker is not installed (needed for 'make image-build'). Install from https://docs.docker.com/get-docker/"
	@command -v git >/dev/null 2>&1 || echo "WARNING: git is not installed (needed for 'make release'). Install from https://git-scm.com/downloads"
	@echo "All dependencies checked."

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

#clean: @ Remove node_modules/ and dist/
clean:
	@rm -rf node_modules/ dist/

#setup: @ Setup environment and git hooks (husky)
setup: install
	@pnpm exec husky init

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

#vulncheck: @ Check for known vulnerabilities in dependencies
vulncheck: install
	@pnpm audit

#deps-update: @ Update dependencies to latest compatible versions (pnpm update)
deps-update: install
	@pnpm update

#deps-upgrade: @ Upgrade dependencies including major version bumps (pnpm upgrade)
deps-upgrade: install
	@pnpm upgrade

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

#ci: @ Run full local CI pipeline (install, format-check, lint, test, build)
ci: install format-check lint test build
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

#release: @ Create and push a new tag (VERSION=vX.Y.Z)
release:
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		git tag $$newtag && \
		git push origin $$newtag && \
		echo "Done."'

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64

#renovate: @ Run Renovate locally in dry-run mode (requires GITHUB_TOKEN)
renovate: install
	@LOG_LEVEL=debug npx --yes renovate --dry-run=full --platform=local --repository-cache=reset --token=$(GITHUB_TOKEN)

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@npx --yes renovate-config-validator

.PHONY: help deps deps-act deps-hadolint clean setup install lint build test \
	vulncheck deps-update deps-upgrade deps-prune deps-prune-check \
	run format format-check ci image-build image-run image-stop \
	release ci-run renovate renovate-validate
