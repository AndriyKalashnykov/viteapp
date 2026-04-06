[![CI](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/viteapp/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/viteapp.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/viteapp/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/viteapp)

# Vite App

React 19 SPA built with [Vite 8](https://vite.dev) and TypeScript (strict mode). Deployed as a multi-arch Docker image via nginx.

## Quick Start

```bash
make deps      # install system dependencies (node, pnpm)
make install   # install project dependencies
make build     # type-check and build for production
make run       # start Vite dev server with HMR
# Open http://localhost:5173
```

## Prerequisites

| Tool                                           | Version | Purpose                     |
| ---------------------------------------------- | ------- | --------------------------- |
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+   | Build orchestration         |
| [Node.js](https://nodejs.org/)                 | 24+     | JavaScript runtime          |
| [pnpm](https://pnpm.io/)                       | 10.33+  | Package manager             |
| [Docker](https://www.docker.com/)              | latest  | Container builds (optional) |
| [Git](https://git-scm.com/)                    | latest  | Version control             |

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

| Target              | Description                                     |
| ------------------- | ----------------------------------------------- |
| `make lint`         | Run ESLint and hadolint on source files         |
| `make test`         | Run Vitest tests                                |
| `make vulncheck`    | Check for known vulnerabilities in dependencies |
| `make format`       | Format source files with Prettier               |
| `make format-check` | Check formatting without writing                |

### CI

| Target        | Description                                                                  |
| ------------- | ---------------------------------------------------------------------------- |
| `make ci`     | Full CI pipeline: install, format-check, lint, test, build                   |
| `make ci-run` | Run GitHub Actions workflow locally via [act](https://github.com/nektos/act) |

### Docker

| Target             | Description                       |
| ------------------ | --------------------------------- |
| `make image-build` | Build Docker image                |
| `make image-run`   | Run Docker container on port 8080 |
| `make image-stop`  | Stop Docker container             |

### Utilities

| Target                   | Description                                                         |
| ------------------------ | ------------------------------------------------------------------- |
| `make help`              | List available tasks                                                |
| `make deps`              | Install dependencies if not present (node, pnpm, docker, git)       |
| `make deps-act`          | Install [act](https://github.com/nektos/act) for local CI runs      |
| `make deps-hadolint`     | Install hadolint for Dockerfile linting                             |
| `make deps-update`       | Update dependencies to latest compatible versions (`pnpm update`)   |
| `make deps-upgrade`      | Upgrade dependencies including major version bumps (`pnpm upgrade`) |
| `make deps-prune`        | Check for unused dependencies                                       |
| `make deps-prune-check`  | Verify no prunable dependencies (CI gate)                           |
| `make setup`             | Setup environment and git hooks (husky)                             |
| `make release`           | Create and push a new tag (VERSION=vX.Y.Z)                          |
| `make renovate`          | Run Renovate locally in dry-run mode (requires `GITHUB_TOKEN`)      |
| `make renovate-validate` | Validate Renovate configuration                                     |

Or use pnpm scripts directly:

```bash
pnpm dev              # Vite dev server
pnpm build            # tsc + vite build
pnpm test             # Vitest
pnpm lint             # ESLint
pnpm prettier         # Format src/**/*.{ts,tsx,js,jsx}
pnpm prettier:diff    # Check formatting without writing
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, pull requests, and `workflow_call` (reusable).

| Job              | Triggers       | Steps                                 |
| ---------------- | -------------- | ------------------------------------- |
| **static-check** | push, PR, tags | Install, Format check, Lint           |
| **build**        | push, PR, tags | Install, Build (after static-check)   |
| **test**         | push, PR, tags | Install, Test (after static-check)    |
| **docker**       | `v*` tags only | QEMU, Buildx, Login, Meta, Build+Push |

A weekly [cleanup workflow](.github/workflows/cleanup-runs.yml) deletes workflow runs older than 7 days (keeping a minimum of 5).

Docker images are pushed to `ghcr.io` as multi-arch (`linux/amd64` + `linux/arm64`) with GHA build cache.

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.
