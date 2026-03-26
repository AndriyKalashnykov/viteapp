.DEFAULT_GOAL := help

APP_NAME   := viteapp
CURRENTTAG := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# === Tool Versions (pinned) ===
NVM_VERSION  := 0.40.3
PNPM_VERSION := 10.32.1
ACT_VERSION  := 0.2.86

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-16s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install dependencies if not present (node, pnpm, docker, git)
deps:
	@echo "Checking dependencies..."
	@command -v node >/dev/null 2>&1 || { echo "Installing Node.js via nvm..."; \
		if command -v nvm >/dev/null 2>&1; then \
			nvm install; \
		elif [ -s "$$HOME/.nvm/nvm.sh" ]; then \
			. "$$HOME/.nvm/nvm.sh" && nvm install; \
		else \
			echo "Installing nvm $(NVM_VERSION)..."; \
			curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
			export NVM_DIR="$$HOME/.nvm"; \
			. "$$NVM_DIR/nvm.sh" && nvm install; \
		fi; \
	}
	@command -v pnpm >/dev/null 2>&1 || { echo "Installing pnpm $(PNPM_VERSION)..."; \
		if command -v corepack >/dev/null 2>&1; then \
			corepack enable && corepack prepare pnpm@$(PNPM_VERSION) --activate; \
		else \
			npm install -g pnpm@$(PNPM_VERSION); \
		fi; \
	}
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}
	@command -v docker >/dev/null 2>&1 || echo "WARNING: docker is not installed (needed for 'make image-build'). Install from https://docs.docker.com/get-docker/"
	@command -v git >/dev/null 2>&1 || echo "WARNING: git is not installed (needed for 'make release'). Install from https://git-scm.com/downloads"
	@echo "All dependencies checked."

#clean: @ Remove node_modules/ and dist/
clean:
	@rm -rf node_modules/ dist/

#setup: @ Setup environment and git hooks (husky)
setup: deps
	@npx husky init

#install: @ Install project dependencies via pnpm
install: deps
	@pnpm install

#lint: @ Run ESLint on TypeScript source files
lint: deps
	@pnpm lint

#build: @ Type-check with tsc and build for production via Vite
build: install
	@pnpm build

#test: @ Run tests
test: deps
	@pnpm test

#update: @ Update dependencies to latest compatible versions
update: deps
	@pnpm update

#upgrade: @ Upgrade dependencies including major version bumps
upgrade: deps
	@pnpm upgrade

#run: @ Start Vite dev server with HMR
run: install
	@pnpm dev

#ci: @ Run full local CI pipeline (install, lint, build, test)
ci: install lint build test
	@echo "CI pipeline passed."

#image-build: @ Build Docker image
image-build: build
	@docker buildx build --load -t $(APP_NAME):$(CURRENTTAG) .

#image-run: @ Run Docker container on port 8080
image-run: deps image-stop
	@docker run --rm -p 8080:8080 --name $(APP_NAME) $(APP_NAME):$(CURRENTTAG)

#image-stop: @ Stop Docker container
image-stop: deps
	@docker stop $(APP_NAME) 2>/dev/null || true

#release: @ Create and push a new tag (VERSION=vX.Y.Z)
release: deps
	@bash -c 'read -p "New tag (current: $(CURRENTTAG)): " newtag && \
		echo "$$newtag" | grep -qE "^v[0-9]+\.[0-9]+\.[0-9]+$$" || { echo "Error: Tag must match vN.N.N"; exit 1; } && \
		echo -n "Create and push $$newtag? [y/N] " && read ans && [ "$${ans:-N}" = y ] && \
		git commit -a -s -m "Cut $$newtag release" && \
		git tag $$newtag && \
		git push origin $$newtag && \
		git push && \
		echo "Done."'

#run-ci: @ Run GitHub Actions workflow locally using act
run-ci: deps
	@act push --container-architecture linux/amd64

#renovate: @ Run Renovate locally in dry-run mode (requires GITHUB_TOKEN)
renovate: deps
	@LOG_LEVEL=debug npx renovate --dry-run=full --platform=local --repository-cache=reset --token=$(GITHUB_TOKEN)

.PHONY: help deps clean setup install lint build test update upgrade run ci \
	image-build image-run image-stop release run-ci renovate
