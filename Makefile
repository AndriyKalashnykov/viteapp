.DEFAULT_GOAL := help

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-14s\033[0m - %s\n", $$1, $$2}'

#deps: @ Install dependencies if not present (node, pnpm, docker, git)
deps:
	@echo "Checking dependencies..."
	@command -v node >/dev/null 2>&1 || { echo "Installing Node.js via nvm..."; \
		if command -v nvm >/dev/null 2>&1; then \
			nvm install --lts; \
		elif [ -s "$$HOME/.nvm/nvm.sh" ]; then \
			. "$$HOME/.nvm/nvm.sh" && nvm install --lts; \
		else \
			echo "Installing nvm..."; \
			curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; \
			export NVM_DIR="$$HOME/.nvm"; \
			. "$$NVM_DIR/nvm.sh" && nvm install --lts; \
		fi; \
	}
	@command -v pnpm >/dev/null 2>&1 || { echo "Installing pnpm..."; \
		if command -v corepack >/dev/null 2>&1; then \
			corepack enable && corepack prepare pnpm@latest --activate; \
		else \
			npm install -g pnpm; \
		fi; \
	}
	@command -v docker >/dev/null 2>&1 || echo "WARNING: docker is not installed (needed for 'make image'). Install from https://docs.docker.com/get-docker/"
	@command -v git >/dev/null 2>&1 || echo "WARNING: git is not installed (needed for 'make release'). Install from https://git-scm.com/downloads"
	@echo "All dependencies checked."

#clean: @ Cleanup
clean:
	@rm -rf node_modules/ dist/

#setup: @ Setup environment and tools
setup: deps
	@npx husky init

#install: @ Install
install: deps
	pnpm install

#lint: @ Lint
lint: install
	pnpm lint

#build: @ Build
build: install
	pnpm build

#update: @ Update
update: deps
	pnpm update

#upgrade: @ Upgrade
upgrade: deps
	pnpm upgrade

#run: @ Run
run: install
	pnpm dev

#image: @ Build Docker Image
image: install build
	docker buildx build --load -t viteapp:v0.0.1 .

#check-version: @ Ensure VERSION variable is set
check-version:
ifndef VERSION
	$(error VERSION is undefined)
endif
	@echo -n ""

#release: @ Creates and pushes tag for the current $VERSION
release: check-version tag-release

#tag-release: @ Create and push a new tag
tag-release: check-version
	@echo -n "Are you sure to create and push ${VERSION} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@git commit -a -s -m "Cut ${VERSION} release"
	@git tag ${VERSION}
	@git push origin ${VERSION}
	@git push
	@echo "Done."

#renovate: @ Run Renovate locally in dry-run mode
renovate: deps
	@LOG_LEVEL=debug npx renovate --dry-run=full --platform=local --repository-cache=reset --token=$(GITHUB_TOKEN)
