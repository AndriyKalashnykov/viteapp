.DEFAULT_GOAL := help

cleanup:
	@rm -rf node_modules/ dist/

install:
	pnpm install

build:
	pnpm build

update:
	pnpm update

upgrade:
	pnpm upgrade

run: install
	pnpm dev