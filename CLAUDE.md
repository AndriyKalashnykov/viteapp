# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

**Version manager:** mise (portfolio-wide; reads `.nvmrc` natively + binary tools pinned in `.mise.toml`, auto-installed by `make deps`)
**Package manager:** pnpm 11 (via corepack; version pinned in `package.json` `packageManager`). Dependency `overrides` and the `allowBuilds` build-script policy live in `pnpm-workspace.yaml` — pnpm 11 removed the legacy `pnpm.overrides` / `pnpm.ignoredBuiltDependencies` package.json fields.

```bash
make deps              # Install mise + Node + pnpm + binary tools (act, hadolint, trivy, gitleaks, container-structure-test) from .mise.toml
make install           # pnpm install (runs deps first)
make lint              # ESLint + hadolint + shell-script executable-bit guard
make build             # TypeScript check + Vite production build (runs install first)
make test              # Run Vitest tests
make coverage-check    # Run Vitest with coverage thresholds (CI gate, 80%)
make run               # Start Vite dev server with HMR
make format            # Format source files with Prettier
make format-check      # Check formatting without writing
make vulncheck         # Check for known vulnerabilities in dependencies (moderate+)
make trivy-fs          # Trivy filesystem scan (vuln, secret, misconfig)
make secrets           # Scan repository for leaked secrets via gitleaks
make mermaid-lint      # Parse every ```mermaid block in README.md / CLAUDE.md via pinned mermaid-cli (script: scripts/mermaid-lint.sh)
make static-check      # Composite quality gate (format-check, lint, vulncheck, trivy-fs, secrets, mermaid-lint)
make ci                # Full local CI pipeline (install, static-check, coverage-check, build, deps-prune-check)
make ci-run            # Run GitHub Actions workflow locally using act (push event)
make ci-run-tag        # Run CI with a tag event via act (exercises docker job + DAST gate)
make clean             # Remove node_modules/, dist/, coverage/, zap-output/
make image-build       # Build Docker image
make image-run         # Run Docker container on port 8080
make image-stop        # Stop the production Docker container
make image-cst         # Container-structure-test against the built image (USER 101, EXPOSE 8080, file presence, nginx -t)
make e2e               # E2E tests against the built container (health, SPA fallback, security headers, hashed bundle, 404 fallback)
make dast              # ZAP baseline DAST scan against the built image (fail-on-warn; .zap/baseline-rules.tsv ignores informational 10049/10109)
make release           # Create and push a new tag (interactive prompt for vX.Y.Z)
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

**Test layers:**

| Layer | Target | Scope | Typical runtime |
|-------|--------|-------|-----------------|
| Unit | `make test` / `make coverage-check` | React components + ThemeContext via jsdom; 80% coverage gate | seconds |
| E2E | `make e2e` | Built container through nginx: health endpoints, SPA fallback, security headers (incl. CSP/COEP/COOP/CORP), hashed bundle URL, 404 fallback | ~15s (image build + 43 curl assertions) |
| DAST | `make dast` | ZAP baseline scan against the running container (fail-on-warn) | minutes |

No integration layer — the app is a static SPA with no DB/broker/inter-service calls. `make e2e` is the first layer that exercises the full nginx surface.

## Architecture

React 19 SPA built with Vite 8 and TypeScript (strict mode).

- **Entry:** `index.html` -> `src/main.tsx` -> `src/App.tsx`
- **State:** React Context API (`ThemeContext` for light/dark theme, defined in `src/theme.tsx`), standard hooks
- **Path alias:** `@` -> `src/` (configured in `vite.config.ts` and `tsconfig.json`)
- **Performance:** Web Vitals via `src/reportWebVitals.ts` (called with `console.log` in `src/main.tsx`; all `console.*` calls stripped in production by terser `drop_console`)

### Notable design decisions

- **Playwright deferred** — current curl-based e2e covers nginx surface and hashed bundle; adding a Playwright smoke against the built bundle would catch Rolldown/terser/chunking regressions jsdom cannot see. Low priority; counter logic is already unit-tested.
- **No CSP `'unsafe-inline'`** — production code uses className-only styling so `script-src 'self'; style-src 'self'` (no `unsafe-inline`) is enforceable. `src/demo/hooks.tsx` references inline styles but is dead code (not imported by `main.tsx`/`App.tsx`); Vite tree-shakes it from the bundle.

## Build & Bundle Config

Vite config (`vite.config.ts`):

- Target: ES2022
- Terser minification -- drops `console.*` and `debugger` in production
- CSS minification: esbuild (`build.cssMinify`) -- chosen over lightningcss because lightningcss doesn't support ES year targets
- Manual chunks: `react` vendor bundle
- CommonJS interop enabled for mixed ESM modules
- Bundler: Rolldown (Vite 8 default); config key remains `rollupOptions` for backward compatibility

## Docker & Deployment

Multi-stage build: Node 24 Alpine builder -> official `nginx:1.31-alpine` server with a DIY unprivileged-user setup (runs as UID 101, PID file in `/tmp`, `apk upgrade --no-cache` for Alpine CVE patches). The official image is tracked directly because the `nginxinc/nginx-unprivileged` variant lagged the official rebuild cadence by multiple patch releases. (Renovate's docker datasource tracks the highest tag, so the pin follows nginx's mainline line — 1.31.x — not the stable 1.30.x line; the image passes the Trivy/e2e/DAST gates on every bump.)

Nginx (`nginx/nginx.conf`):

- Listens on port 8080 as numeric UID 101 (non-root)
- SPA fallback: `try_files $uri /index.html`
- Health endpoints: `/internal/isalive`, `/internal/isready`
- Security headers: `server_tokens off`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `Content-Security-Policy`, `Cross-Origin-Embedder-Policy`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy`
- Cache control: hashed `/assets/*` get `public, max-age=31536000, immutable`; `/` and SPA fallback get `no-cache, no-store, must-revalidate`; health endpoints get `no-store`
- Headers re-declared in every `location` block — nginx silently shadows ALL parent `add_header` directives once a location defines its own. The e2e suite asserts header inheritance on `/`, SPA fallback, and both health endpoints.

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`):

- Triggers: push to `main`, tags `v*`, pull requests, `workflow_call` (reusable). No trigger-level `paths-ignore` — uses a `changes` detector job (`dorny/paths-filter`) so doc-only changes skip heavy work without deadlocking Repository Rulesets that require `ci-pass`.
- `changes` job: emits `outputs.code` (true on tag push or any non-doc file change). All heavy jobs gate on `if: needs.changes.outputs.code == 'true'`.
- `static-check` job: checkout (`fetch-depth: 0` for gitleaks history) -> pnpm/action-setup -> setup-node (with pnpm cache) -> install -> `make static-check` (format-check + lint + vulncheck + trivy-fs + secrets + mermaid-lint, composite quality gate)
- `build` job: install -> `make build` (runs after `static-check`)
- `test` job: install -> `make coverage-check` (runs after `static-check`, parallel with `build`)
- `e2e` job: install -> `make e2e` (curl-based assertions against built nginx container)
- `docker` job: QEMU -> Buildx -> meta -> build-for-scan (single-arch, `load: true`) -> Trivy image scan (CRITICAL/HIGH blocking, `ignore-unfixed: true`) -> container-structure-test -> smoke test (`curl /internal/isalive`) -> multi-arch build (runs every push so arm64 cross-compile regressions surface pre-tag) -> tag-gated push + cosign keyless OIDC signing. `provenance: false` + `sbom: false` on the publish step (buildkit attestations break the GHCR "OS / Arch" UI; cosign keyless signing provides supply-chain verification).
- `dast` job (parallel with `docker`): build single-arch image -> start -> ZAP baseline (fail-on-warn; `.zap/baseline-rules.tsv` IGNOREs ZAP rules 10049 (cache-storability informational) and 10109 (Modern Web Application informational) with rationale) -> upload report. **Job is skipped under act** (`if: ${{ vars.ACT != 'true' }}`) because ZAP requires Docker-in-Docker and `actions/upload-artifact@v7` fails under act's v4-protocol artifact server — `make ci-run` does NOT exercise this job. Failure modes that can slip through `make ci-run` and only surface on real GitHub Actions: ZAP rule additions/removals (run `make dast` locally before push), nginx response-header regressions that ZAP catches but e2e doesn't, and any `actions/upload-artifact@v7+` migration breakage. Mitigation: every nginx.conf edit MUST be followed by `make dast` locally before push.
- `ci-pass` job (aggregation gate, `if: always()`, `needs: [changes, static-check, build, test, e2e, docker, dast]`): single check suitable for branch protection.
- Docker images pushed to `ghcr.io` as multi-arch (`amd64` + `arm64`) with GHA build cache.
- Permissions: `contents: read` at workflow level; `packages: write` + `id-token: write` (cosign OIDC) on docker job only; `pull-requests: read` on changes job.

Cleanup (`.github/workflows/cleanup-runs.yml`):

- Weekly cron + `workflow_dispatch` + `workflow_call`: deletes workflow runs older than 7 days (keeps minimum 5) and orphaned caches from deleted branches
- Uses native `gh` CLI (no third-party actions)

## Code Quality

- **ESLint:** flat config (`eslint.config.js`) with `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`; `--max-warnings 0` enforced
- **hadolint:** Dockerfile linting via `make lint` (auto-installed by mise from `.mise.toml`)
- **Trivy:** filesystem scanner (`make trivy-fs`); part of `make static-check` composite gate
- **gitleaks:** secret scanner (`make secrets`); part of `make static-check` composite gate
- **container-structure-test:** asserts USER 101, EXPOSE 8080, PID-file relocation, nginx config presence + syntax (`make image-cst`); CI `docker` job runs it before publish
- **ZAP baseline DAST:** fail-on-warn; informational rules ignored via `.zap/baseline-rules.tsv` with documented rationale
- **Renovate:** auto-merges all dependency updates after CI passes (no restrictive schedule, ASAP merging); `automergeType: pr` + `platformAutomerge: false` — `main` has a ruleset requiring the `ci-pass` check, so branch-mode (direct push) is rejected for the bot; `pr` mode opens a PR and Renovate merges it on its own run after re-confirming green (`platformAutomerge: false` avoids the native-auto-merge registration race that can merge a red bump before the check registers). Dependabot **alerts** enabled (feeds Renovate's `vulnerabilityAlerts` fast-track); Dependabot security-update PRs disabled (Renovate owns version + security bumps)
- **Prettier:** uses defaults (no config file)
- **Vitest:** unit tests with `@testing-library/react` and `jest-dom` matchers; coverage via `@vitest/coverage-v8` with thresholds; config in `vite.config.ts`; setup in `src/test/setup.ts`
- **Mermaid lint:** every `` ```mermaid `` block in README.md / CLAUDE.md is parsed by pinned `minlag/mermaid-cli` (`make mermaid-lint`, script at `scripts/mermaid-lint.sh`); part of `make static-check` composite gate
- **Shell-script executable-bit guard:** `make lint` runs `find scripts -name '*.sh' -not -executable` so subagent-created scripts (Write tool defaults to mode 0644) don't ship with the executable bit missing.

## Upgrade Backlog

Last reviewed: 2026-06-24 (`/upgrade-analysis` + `/renovate` pass)

- [ ] **`undici` override (`pnpm-workspace.yaml`) + `<8` cap (`renovate.json`)** — `undici@>=7.0.0 <7.28.0` is overridden to `^7.28.0` to clear the TLS cert-validation-bypass / WebSocket-DoS / cross-origin-routing advisories (transitive via `@vitest/coverage-v8 > vitest > jsdom > undici`). A Renovate `allowedVersions: <8` cap holds it on the 7.x line because jsdom 29.1.1 hard-requires `undici/lib/handler/wrap-handler.js`, which undici v8 removed (verified: PR #303 broke the vitest/jsdom runtime and was closed). Remove both the override and the `<8` cap when jsdom ships a release that consumes `undici >= 8` directly.
- [ ] **`brace-expansion` override (`pnpm-workspace.yaml`)** — `brace-expansion@>=5.0.0 <5.0.6` is overridden to `^5.0.6` to clear the ReDoS advisory (transitive via eslint). Remove when eslint pulls `brace-expansion >= 5.0.6` directly.

## Skills

Use the following skills when working on related files:

| File(s)                          | Skill          |
| -------------------------------- | -------------- |
| `Makefile`                       | `/makefile`    |
| `renovate.json`                  | `/renovate`    |
| `README.md`                      | `/readme`      |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |
| `README.md` / `CLAUDE.md` (Mermaid blocks) | `/architecture-diagrams` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
