.DEFAULT_GOAL := help

clean:
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

image: install build
	docker build -t viteapp .