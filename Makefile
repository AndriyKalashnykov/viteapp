.DEFAULT_GOAL := help

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-14s\033[0m - %s\n", $$1, $$2}'

#clean: @ Cleanup
clean:
	@rm -rf node_modules/ dist/

#setup: @ Setup environment and tools
setup:
	@npx pretty-quick install -g
	@npx husky install -g

#install: @ Install
install:
	pnpm install

#build: @ Build
build: install
	pnpm build

#update: @ Update
update:
	pnpm update

#upgrade: @ Upgrade
upgrade:
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

renovate:
	@LOG_LEVEL=debug npx renovate --dry-run=full --platform=local --repository-cache=reset --token=$(GITHUB_TOKEN)
