[![ci](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/viteapp.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/viteapp/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/viteapp)

# viteapp

React 19 SPA built with [Vite 8](https://vite.dev), TypeScript (strict mode), and React Router v7.

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

## Available Commands

| Command                       | Description                                                        |
| ----------------------------- | ------------------------------------------------------------------ |
| `make deps`                   | Check and install system dependencies (Node.js, pnpm, Docker, Git) |
| `make install`                | Install project dependencies via pnpm                              |
| `make lint`                   | Run ESLint on TypeScript source files                              |
| `make build`                  | Type-check with `tsc` and build for production via Vite            |
| `make run`                    | Start Vite dev server with HMR at `http://localhost:5173`          |
| `make clean`                  | Remove `node_modules/` and `dist/`                                 |
| `make image`                  | Build Docker image (`viteapp:v0.0.3`) with nginx                   |
| `make update`                 | Update dependencies to latest compatible versions                  |
| `make upgrade`                | Upgrade dependencies including major version bumps                 |
| `make setup`                  | Initialize environment and git hooks (husky)                       |
| `make release VERSION=vX.Y.Z` | Tag and push a release                                             |
| `make renovate`               | Run Renovate locally in dry-run mode (requires `GITHUB_TOKEN`)     |

Or use pnpm scripts directly:

```bash
pnpm dev              # Vite dev server
pnpm build            # tsc + vite build
pnpm lint             # ESLint
pnpm prettier         # Format src/**/*.{ts,tsx,js,jsx}
pnpm prettier:diff    # Check formatting without writing
```

## Release

```bash
export VERSION=v0.0.3
make release
```

This creates and pushes a git tag. The CI pipeline builds and publishes the Docker image to `ghcr.io` on tagged releases.

## References

- [Creating a React app using Vite](https://fullstackcode.dev/2022/01/30/creating-react-js-app-using-vite-2-0/)
- [Vite 3 vs Create React App: comparison and migration guide](https://blog.logrocket.com/vite-3-vs-create-react-app-comparison-migration-guide/)
