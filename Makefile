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

#install: @ Install
install:
	pnpm install

#build: @ Build
build:
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
	docker build -t viteapp .