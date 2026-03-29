[![CI](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/viteapp.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/viteapp/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/viteapp)

# Vite App

React 19 SPA built with [Vite 8](https://vite.dev), TypeScript (strict mode), and React Router v7. Deployed as a multi-arch Docker image via nginx.

## Quick Start

```bash
make deps      # install system dependencies (node, pnpm)
make install   # install project dependencies
make lint      # run ESLint and hadolint
make build     # type-check and build for production
make run       # start Vite dev server with HMR
```

## Prerequisites

| Tool                                           | Version | Purpose                               |
| ---------------------------------------------- | ------- | ------------------------------------- |
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+   | Build orchestration                   |
| [Node.js](https://nodejs.org/)                 | 24+     | JavaScript runtime                    |
| [nvm](https://github.com/nvm-sh/nvm)           | latest  | Node.js version management (optional) |
| [pnpm](https://pnpm.io/)                       | 10+     | Package manager                       |
| [Docker](https://www.docker.com/)              | latest  | Container builds (optional)           |
| [Git](https://git-scm.com/)                    | latest  | Version control                       |

Install all required dependencies:

```bash
make deps
```

## Available Make Targets

Run `make help` to see all available targets.

### Build & Run

| Target         | Description                                           |
| -------------- | ----------------------------------------------------- |
| `make install` | Install project dependencies via pnpm                 |
| `make build`   | Type-check with tsc and build for production via Vite |
| `make run`     | Start Vite dev server with HMR                        |
| `make clean`   | Remove `node_modules/` and `dist/`                    |

### Code Quality

| Target      | Description                             |
| ----------- | --------------------------------------- |
| `make lint` | Run ESLint and hadolint on source files |
| `make test` | Run tests                               |

### CI

| Target        | Description                                                                  |
| ------------- | ---------------------------------------------------------------------------- |
| `make ci`     | Full CI pipeline: install, lint, test, build                                 |
| `make ci-run` | Run GitHub Actions workflow locally via [act](https://github.com/nektos/act) |

### Docker

| Target             | Description                       |
| ------------------ | --------------------------------- |
| `make image-build` | Build Docker image                |
| `make image-run`   | Run Docker container on port 8080 |
| `make image-stop`  | Stop Docker container             |

### Utilities

| Target                   | Description                                                        |
| ------------------------ | ------------------------------------------------------------------ |
| `make deps`              | Check and install system dependencies (Node.js, pnpm, Docker, Git) |
| `make setup`             | Setup environment and git hooks (husky)                            |
| `make update`            | Update dependencies to latest compatible versions                  |
| `make upgrade`           | Upgrade dependencies including major version bumps                 |
| `make release`           | Interactive tag creation with semver validation                    |
| `make renovate`          | Run Renovate locally in dry-run mode (requires `GITHUB_TOKEN`)     |
| `make renovate-validate` | Validate Renovate configuration                                    |

Or use pnpm scripts directly:

```bash
pnpm dev              # Vite dev server
pnpm build            # tsc + vite build
pnpm lint             # ESLint
pnpm prettier         # Format src/**/*.{ts,tsx,js,jsx}
pnpm prettier:diff    # Check formatting without writing
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job        | Triggers       | Steps                                 |
| ---------- | -------------- | ------------------------------------- |
| **ci**     | push, PR, tags | Install, Lint, Test, Build            |
| **docker** | `v*` tags only | QEMU, Buildx, Login, Meta, Build+Push |

Docker images are pushed to `ghcr.io` as multi-arch (`linux/amd64` + `linux/arm64`) with GHA build cache.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.

## Release

```bash
make release
```

This interactively prompts for a tag (with semver validation), then creates and pushes it. The CI pipeline builds and publishes multi-arch Docker images to `ghcr.io` on tagged releases.

## References

- [Creating a React app using Vite](https://fullstackcode.dev/2022/01/30/creating-react-js-app-using-vite-2-0/)
- [Vite 3 vs Create React App: comparison and migration guide](https://blog.logrocket.com/vite-3-vs-create-react-app-comparison-migration-guide/)
