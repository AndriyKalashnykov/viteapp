[![ci](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/viteapp.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/viteapp/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/viteapp)

# viteapp

ReactJS + Vite

## Requirements

All required dependencies can be installed automatically:

```bash
make deps
```

This checks for and installs (if missing):

- [Node.js](https://nodejs.org/) via [nvm](https://github.com/nvm-sh/nvm#install--update-script)
- [pnpm](https://pnpm.io/installation) via corepack or npm
- [Docker](https://docs.docker.com/get-docker/) (warns if missing, needed for `make image`)
- [Git](https://git-scm.com/downloads) (warns if missing, needed for `make release`)

## Help

```bash
$ make help
```

```text
Usage: make COMMAND
Commands :
help           - List available tasks
deps           - Install dependencies if not present (node, pnpm, docker, git)
clean          - Cleanup
setup          - Setup environment and tools
install        - Install
build          - Build
update         - Update
upgrade        - Upgrade
run            - Run
image          - Build Docker Image
check-version  - Ensure VERSION variable is set
release        - Creates and pushes tag for the current $VERSION
tag-release    - Create and push a new tag
renovate       - Run Renovate locally in dry-run mode
```

## Release

Set version as env variable

```bash
export VERSION=v0.0.1
```

run a release task

```bash
make release
```

## References

- https://fullstackcode.dev/2022/01/30/creating-react-js-app-using-vite-2-0/
- https://blog.logrocket.com/vite-3-vs-create-react-app-comparison-migration-guide/

### React.js Setup for GraphQL using Vite and urql

- https://www.youtube.com/watch?v=x4Rc3RytAls&t=356s&ab_channel=ZaisteProgramming
- https://zaiste.net/posts/modern-lightweight-reactjs-setup-graphql-vite-urql/
