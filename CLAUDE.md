# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

**Package manager:** pnpm (via corepack)

```bash
make deps              # Install system dependencies (node, pnpm, docker, git) if missing
make install           # pnpm install (runs deps first)
make lint              # ESLint + hadolint (Dockerfile linting)
make build             # TypeScript check + Vite production build (runs install first)
make test              # Run Vitest tests
make coverage-check    # Run Vitest with coverage thresholds (CI gate)
make run               # Start Vite dev server with HMR
make format            # Format source files with Prettier
make format-check      # Check formatting without writing
make vulncheck         # Check for known vulnerabilities in dependencies (moderate+)
make trivy-fs          # Trivy filesystem scan (vuln, secret, misconfig)
make secrets           # Scan repository for leaked secrets via gitleaks
make static-check      # Composite quality gate (format-check, lint, vulncheck, trivy-fs, secrets)
make ci                # Full local CI pipeline (install, static-check, test, coverage-check, build, deps-prune-check)
make ci-run            # Run GitHub Actions workflow locally using act
make clean             # Remove node_modules/ and dist/
make image-build       # Build Docker image (nginx-unprivileged)
make image-run         # Run Docker container on port 8080
make image-stop        # Stop Docker container
make release           # Create and push a new tag (interactive prompt for vX.Y.Z)
make deps-act          # Install act for local CI runs
make deps-hadolint     # Install hadolint for Dockerfile linting
make deps-trivy        # Install trivy for filesystem vulnerability scanning
make deps-gitleaks     # Install gitleaks for secret scanning
make deps-update       # Update dependencies to latest compatible versions (pnpm update)
make deps-prune        # Check for unused dependencies
make deps-prune-check  # Verify no prunable dependencies (CI gate)
make renovate          # Run Renovate locally in dry-run mode (requires GITHUB_TOKEN)
make renovate-validate # Validate Renovate configuration
```

Direct pnpm scripts:

```bash
pnpm dev               # Vite dev server
pnpm build             # tsc && vite build
pnpm lint              # ESLint (*.ts, *.tsx)
pnpm prettier          # Format src/**/*.{ts,tsx,js,jsx}
pnpm prettier:diff     # Check formatting without writing
```

Test runner: `pnpm test` runs Vitest (`vitest run`). Test setup in `src/test/setup.ts` (jest-dom matchers).

## Architecture

React 19 SPA built with Vite 8 and TypeScript (strict mode).

- **Entry:** `index.html` -> `src/main.tsx` (defines ThemeContext inline, wraps App) -> `src/App.tsx`
- **State:** React Context API (ThemeContext for light/dark theme, defined in `src/main.tsx`), standard hooks
- **Path alias:** `@` -> `src/` (configured in `vite.config.ts` and `tsconfig.json`)
- **Performance:** Web Vitals via `src/reportWebVitals.ts` (called with `console.log` in `src/main.tsx`; all `console.*` calls stripped in production by terser `drop_console`)

## Build & Bundle Config

Vite config (`vite.config.ts`):

- Target: ES2022
- Terser minification -- drops `console.*` and `debugger` in production
- CSS minification: esbuild (`build.cssMinify`) -- chosen over lightningcss because lightningcss doesn't support ES year targets
- Manual chunks: `react` vendor bundle
- CommonJS interop enabled for mixed ESM modules
- Bundler: Rolldown (Vite 8 default); config key remains `rollupOptions` for backward compatibility

## Docker & Deployment

Multi-stage build: Node 24 Alpine builder -> official `nginx:1.29-alpine` server with a DIY unprivileged-user setup (runs as UID 101, PID file in `/tmp`, `apk upgrade --no-cache` for Alpine CVE patches). We previously used `nginxinc/nginx-unprivileged` but switched to the official image because the unprivileged variant lagged the official rebuild cadence by multiple patch releases.

Nginx (`nginx/nginx.conf`):

- Listens on port 8080
- SPA fallback: `try_files $uri /index.html`
- Health endpoints: `/internal/isalive`, `/internal/isready`
- Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`):

- Triggers: push to `main`, tags `v*`, pull requests, `workflow_call` (reusable)
- `static-check` job: checkout (`fetch-depth: 0` for gitleaks history) -> pnpm/action-setup -> setup-node (with pnpm cache) -> install -> `make static-check` (format-check + lint + vulncheck + trivy-fs + secrets, composite quality gate)
- `build` job: install -> `make build` (runs after `static-check`)
- `test` job: install -> `make coverage-check` (runs after `static-check`, parallel with `build`)
- `docker` job (runs only on `v*` tags, after `build` + `test` pass): QEMU -> Buildx -> meta -> build-for-scan (single-arch, `load: true`) -> Trivy image scan (CRITICAL/HIGH blocking, `ignore-unfixed: true`) -> smoke test (`curl /internal/isalive`) -> ZAP baseline DAST scan (cached ZAP image, `-I` = warn only) -> GHCR login -> multi-arch build+push with `provenance: mode=max` and `sbom: true` (captures digest) -> cosign keyless signing of each tag by digest
- Docker images pushed to `ghcr.io` as multi-arch (`amd64` + `arm64`) with GHA build cache
- Permissions: `contents: read` at workflow level; `packages: write` + `id-token: write` (cosign OIDC) on docker job only

Cleanup (`.github/workflows/cleanup-runs.yml`):

- Weekly cron + `workflow_dispatch` + `workflow_call`: deletes workflow runs older than 7 days (keeps minimum 5) and orphaned caches from deleted branches
- Uses native `gh` CLI (no third-party actions)

## Code Quality

- **ESLint:** flat config (`eslint.config.js`) with `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`; `--max-warnings 0` enforced
- **hadolint:** Dockerfile linting via `make lint` (auto-installed by `deps-hadolint` target)
- **Trivy:** filesystem scanner (`make trivy-fs`); part of `make static-check` composite gate
- **gitleaks:** secret scanner (`make secrets`); part of `make static-check` composite gate
- **Renovate:** auto-merges all dependency updates after CI passes (no restrictive schedule, ASAP merging)
- **Prettier:** uses defaults (no config file)
- **Vitest:** unit tests with `@testing-library/react` and `jest-dom` matchers; coverage via `@vitest/coverage-v8` with thresholds; config in `vite.config.ts`; setup in `src/test/setup.ts`

## Upgrade Backlog

Last reviewed: 2026-04-10

- [x] ~~Evaluate husky alternatives — removed husky entirely (CI format-check is the safety net)~~
- [x] ~~Switch off `nginxinc/nginx-unprivileged` because of upstream lag — migrated to official `nginx:1.29.8-alpine` with DIY UID 101 / `/tmp` PID file (2026-04-10)~~
- [ ] **`eslint-plugin-react-hooks` peer dep warning** — currently 7.0.1, peer declares `eslint@^3..^9` but project pins eslint 10. Plugin works at runtime; warning is cosmetic. Track for next stable release that lists eslint 10 in peer deps.
- [ ] **`.dockerignore` contains stale `.husky` reference** (line 5) — clean up after husky removal.
- [ ] **Optional: enable Renovate `github-runners` manager** — would generate auto-PRs when GitHub deprecates `ubuntu-22.04` / `ubuntu-24.04` runner images. Currently disabled; `ubuntu-latest` rarely breaks but the warning window is short when it does.

## Skills

Use the following skills when working on related files:

| File(s)                          | Skill          |
| -------------------------------- | -------------- |
| `Makefile`                       | `/makefile`    |
| `renovate.json`                  | `/renovate`    |
| `README.md`                      | `/readme`      |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
