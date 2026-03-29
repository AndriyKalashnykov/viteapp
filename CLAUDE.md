# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

**Package manager:** pnpm (via corepack)

```bash
make deps              # Install system dependencies (node, pnpm, docker, git) if missing
make install           # pnpm install (runs deps first)
make lint              # ESLint + hadolint (Dockerfile linting)
make build             # TypeScript check + Vite production build (runs install first)
make test              # Run tests (no-op until test suite added)
make run               # Start Vite dev server with HMR
make ci                # Full local CI pipeline (install, lint, test, build)
make ci-run            # Run GitHub Actions workflow locally using act
make clean             # Remove node_modules/ and dist/
make image-build       # Build Docker image (nginx-unprivileged)
make image-run         # Run Docker container on port 8080
make image-stop        # Stop Docker container
make release           # Interactive tag creation with semver validation
make renovate-validate # Validate Renovate configuration
```

Direct pnpm scripts:

```bash
pnpm dev               # Vite dev server
pnpm build             # tsc && vite build
pnpm lint              # ESLint (.ts, .js)
pnpm prettier          # Format src/**/*.{ts,tsx,js,jsx}
pnpm prettier:diff     # Check formatting without writing
```

No test suite yet (`pnpm test` is a no-op).

## Architecture

React 19 SPA built with Vite 8 and TypeScript (strict mode).

- **Entry:** `index.html` -> `src/main.tsx` (React Router setup) -> `src/App.tsx`
- **Routing:** React Router DOM v7, configured in `src/main.tsx`
- **State:** React Context API (ThemeContext for light/dark theme), standard hooks
- **Path alias:** `@` -> `src/` (configured in `vite.config.ts` and `tsconfig.json`)
- **Performance:** Web Vitals reporting via `src/reportWebVitals.ts` + `src/reportHandler.tsx`

## Build & Bundle Config

Vite config (`vite.config.ts`):

- Target: ES2022
- Terser minification -- drops `console.*` and `debugger` in production
- CSS minification: esbuild (`build.cssMinify`) -- lightningcss default doesn't accept ES year targets
- Manual chunks: `react` vendor bundle, `react-router-dom` bundle
- CommonJS interop enabled for mixed ESM modules
- Bundler: Rolldown (Vite 8 default, replaces Rollup)

## Docker & Deployment

Multi-stage build: Node 24 Alpine builder -> `nginxinc/nginx-unprivileged` server.

Nginx (`nginx/nginx.conf`):

- Listens on port 8080
- SPA fallback: `try_files $uri /index.html`
- Health endpoints: `/internal/isalive`, `/internal/isready`
- Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`):

- Triggers: push to `main`, tags `v*`, pull requests
- `ci` job: checkout -> corepack -> setup-node (with pnpm cache) -> install -> lint -> test -> build (runs on all pushes and PRs)
- `docker` job: QEMU -> Buildx -> login -> meta -> build+push (runs only on `v*` tags, after `ci` passes)
- Docker images pushed to `ghcr.io` as multi-arch (`amd64` + `arm64`) with GHA build cache
- Permissions: `contents: read` at workflow level; `packages: write` only on docker job

## Code Quality

- **ESLint:** flat config (`eslint.config.js`) with `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`
- **hadolint:** Dockerfile linting via `make lint` (auto-installed by `deps-hadolint` target)
- **Pre-commit:** lint-staged runs Prettier on staged files
- **Renovate:** auto-merges all dependency updates after CI passes (no restrictive schedule, ASAP merging)
- **Prettier:** uses defaults (empty `.prettierrc`)

## Skills

Use the following skills when working on related files:

| File(s)                   | Skill          |
| ------------------------- | -------------- |
| `Makefile`                | `/makefile`    |
| `renovate.json`           | `/renovate`    |
| `README.md`               | `/readme`      |
| `.github/workflows/*.yml` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
