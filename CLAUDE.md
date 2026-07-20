# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

**Version manager:** mise (portfolio-wide; reads `.nvmrc` natively + binary tools pinned in `.mise.toml`, auto-installed by `make deps`)
**Package manager:** pnpm 11 (via corepack; version pinned in `package.json` `packageManager`). Dependency `overrides` and the `allowBuilds` build-script policy live in `pnpm-workspace.yaml` — pnpm 11 removed the legacy `pnpm.overrides` / `pnpm.ignoredBuiltDependencies` package.json fields.

```bash
make deps              # Install mise + Node + pnpm + binary tools (act, hadolint, trivy, gitleaks, container-structure-test) from .mise.toml
make install           # pnpm install (runs deps first)
make check-node-alignment # Verify Node version matches across .nvmrc and Dockerfile (Renovate split-drift guard)
make check-minifier-deps # Verify every minifier named in vite.config.ts is a declared dependency (esbuild/terser optional-peer guard)
make check-dockerfile-stage # Verify ci.yml's no-cache-filters matches the Dockerfile's final stage (makes the apk-upgrade fix fail-closed)
make image-apk-check   # Assert the built image's apk upgrade layer actually ran (catches a replayed cache layer)
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
make diagrams          # Render PlantUML architecture diagrams (docs/diagrams/*.puml) to PNG via pinned plantuml/plantuml (script: scripts/render-diagrams.sh)
make diagrams-check    # Verify committed diagram PNGs match current PlantUML source (CI drift gate; part of static-check)
make static-check      # Composite quality gate (check-node-alignment, check-dockerfile-stage, check-minifier-deps, format-check, lint, vulncheck, trivy-fs, secrets, mermaid-lint, diagrams-check)
make ci                # Full local CI pipeline (install, static-check, coverage-check, build, deps-prune-check)
make ci-run            # Run GitHub Actions workflow locally using act (push event)
make ci-run-tag        # Run CI with a tag event via act (exercises docker job + DAST gate)
make clean             # Remove node_modules/, dist/, coverage/, zap-output/
make image-build       # Build Docker image
make image-run         # Run Docker container on port 8080
make image-stop        # Stop the production Docker container
make image-cst         # Container-structure-test against the built image (USER 101, EXPOSE 8080, file presence, nginx -t)
make e2e               # E2E tests against the built container (health, SPA fallback, security headers, hashed bundle, 404 fallback)
make e2e-browser       # Playwright Chromium smoke against the built container (counter, theme toggle + persistence, axe a11y, CSP)
make lighthouse        # Lighthouse CI budgets (perf/a11y/best-practices/SEO) against the built container
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
| Unit | `make test` / `make coverage-check` | React components + ThemeProvider/useTheme via jsdom; 80% coverage gate | seconds |
| E2E | `make e2e` | Built container through nginx: health endpoints, SPA fallback, security headers (incl. CSP/COEP/COOP/CORP), hashed bundle URL, 404 fallback | ~15s (image build + 49 curl assertions) |
| Browser E2E | `make e2e-browser` | Playwright Chromium against the built nginx container: app boot, counter, light/dark theme toggle + persistence, axe accessibility scan (both themes), console CSP-violation check | ~30s (image build + Chromium) |
| Lighthouse | `make lighthouse` | Lighthouse CI budgets against the built container: performance ≥0.9, accessibility ≥0.95, best-practices ≥0.95, SEO ≥0.9 (3 runs, median; desktop preset) | ~1 min |
| DAST | `make dast` | ZAP baseline scan against the running container (fail-on-warn) | minutes |

No integration layer — the app is a static SPA with no DB/broker/inter-service calls. `make e2e` (curl) exercises the full nginx surface; `make e2e-browser` then drives the built bundle in a real browser (the JS behavior — theme toggle, counter, CSP enforcement — that curl and jsdom cannot reach).

## Architecture

React 19 SPA built with Vite 8 and TypeScript (strict mode).

- **Entry:** `index.html` -> `src/main.tsx` -> `src/App.tsx`
- **State:** React Context API — `ThemeProvider` (`src/ThemeProvider.tsx`) exposes a light/dark theme via `useTheme()` (`src/theme.tsx`). The active theme is reflected onto `<html data-theme>`, persisted to `localStorage` (key `viteapp-theme`), and defaults to the OS `prefers-color-scheme`. A toggle button in `App.tsx` flips it. Standard hooks elsewhere.
- **Path alias:** `@` -> `src/` (configured in `vite.config.ts` and `tsconfig.json`)
- **Performance:** Web Vitals via `src/reportWebVitals.ts` (called with `console.log` in `src/main.tsx`; all `console.*` calls stripped in production by terser `drop_console`)

### Notable design decisions

- **Playwright browser smoke + a11y** (`make e2e-browser`, CI `e2e-browser` job) — Chromium specs (`e2e/browser/app.spec.ts` + `e2e/browser/a11y.spec.ts`, config `playwright.config.ts`) drive the built bundle inside the production nginx container, under the real CSP: app boot, counter increment, the light/dark theme toggle (`data-theme` flip + `localStorage` persistence across reload), a console CSP-violation assertion, and an `@axe-core/playwright` accessibility scan (WCAG 2.0/2.1 A/AA, fail on serious/critical) in **both** themes. Catches Rolldown/terser/chunking, inline-style/CSP, and accessibility regressions that jsdom (source, not bundle) and curl (no JS) cannot. The a11y scan runs under emulated `reducedMotion: reduce` (via `emulateMedia`, not config `use` — which the `devices` block shadows) so axe reads the settled palette, not a mid-transition blend; correspondingly the theme color-transition in `index.css` is gated behind `@media (prefers-reduced-motion: no-preference)`. The CI job caches the Chromium binary (`~/.cache/ms-playwright`, keyed on `pnpm-lock.yaml`). Skipped under act (browser download + DinD + `upload-artifact@v7`), so `make ci-run` does NOT exercise it — run `make e2e-browser` locally before pushing UI/bundle changes.
- **No CSP `'unsafe-inline'`** — all styling is className + CSS-custom-property based (never inline `style`), so `script-src 'self'; style-src 'self'` (no `unsafe-inline`) is enforceable. The light/dark theme switches by toggling a `data-theme` attribute on `<html>` (which selects CSS variables defined in `src/index.css`) rather than applying inline styles — that is why the theme is CSP-safe. The `ThemeContext` default carries no colors, only the theme name + setters.

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
- `changes` job: emits `outputs.code` (true on tag push or any non-doc file change). `docs/**` is treated as non-code EXCEPT `docs/diagrams/**`, which is re-included so a `.puml`/rendered-PNG change runs `static-check` → `diagrams-check` (the drift gate) instead of being skipped as docs-only. All heavy jobs gate on `if: needs.changes.outputs.code == 'true'`.
- `static-check` job: checkout (`fetch-depth: 0` for gitleaks history) -> pnpm/action-setup -> setup-node (with pnpm cache) -> install -> `make static-check` (check-node-alignment + check-dockerfile-stage + check-minifier-deps + format-check + lint + vulncheck + trivy-fs + secrets + mermaid-lint + diagrams-check, composite quality gate)
- `build` job: install -> `make build` (runs after `static-check`)
- `test` job: install -> `make coverage-check` (runs after `static-check`, parallel with `build`)
- `e2e` job: install -> `make e2e` (curl-based assertions against built nginx container)
- `e2e-browser` job: install -> cache `~/.cache/ms-playwright` (keyed on `pnpm-lock.yaml`) -> install Chromium (browser+deps on cache miss, system deps only on hit) -> `make e2e-browser` (Playwright Chromium smoke + axe a11y against the built container; uploads the HTML report as an artifact). **Skipped under act** (`if: ${{ vars.ACT != 'true' }}`) because the browser download + Docker-in-Docker + `actions/upload-artifact@v7` don't work under act — `make ci-run` does NOT exercise it; run `make e2e-browser` locally before pushing UI/bundle changes.
- `docker` job: QEMU -> Buildx -> meta -> build-for-scan (single-arch, `load: true`) -> Trivy image scan (CRITICAL/HIGH blocking, `ignore-unfixed: true`) -> **apk-upgrade mechanism gate** -> container-structure-test -> smoke test (`curl /internal/isalive`) -> multi-arch build (runs every push so arm64 cross-compile regressions surface pre-tag) -> tag-gated push -> **Trivy scan of the pushed digest** -> cosign keyless OIDC signing. `provenance: false` + `sbom: false` on the publish step (buildkit attestations break the GHCR "OS / Arch" UI; cosign keyless signing provides supply-chain verification).
  - **`no-cache-filters: server` on every gha-cached build (BLOCKING invariant).** The `server` stage's `apk upgrade` keys on (command string + PINNED parent digest), so neither cache input encodes the Alpine package index — the layer stays cache-valid indefinitely while the index moves daily. Measured 2026-07-20: the layer logged `#14 CACHED` while Trivy reported 8 fixable HIGHs, i.e. the image's only OS-package patching mechanism had been silently inert, and the Trivy gate is the sole reason anyone found out. The filter must be on **all three** cache-importing builds (docker's scan + push, and `dast`, which writes `mode=max` into the same scope and would otherwise re-seed a stale layer). Filtering only the scanned build is **worse than not fixing it**: Trivy would scan a freshly-patched image while the push restored the stale layer, shipping a vulnerable image behind a green gate. A stale/typo'd stage name fails **open** (silently no-ops), so `make check-dockerfile-stage` asserts both that the value matches the Dockerfile's final stage and that cache-importing builds == filtered builds.
  - **Why the pushed digest is scanned separately:** the scan build and the push build are distinct invocations producing distinct images, so Gates 1–2 never inspect the published bytes. The post-push scan runs **before** cosign, so a vulnerable push fails the job and is left unsigned rather than promoted.
- `dast` job (parallel with `docker`): build single-arch image -> start -> ZAP baseline (fail-on-warn; `.zap/baseline-rules.tsv` IGNOREs ZAP rules 10049 (cache-storability informational) and 10109 (Modern Web Application informational) with rationale) -> upload report. **Job is skipped under act** (`if: ${{ vars.ACT != 'true' }}`) because ZAP requires Docker-in-Docker and `actions/upload-artifact@v7` fails under act's v4-protocol artifact server — `make ci-run` does NOT exercise this job. Failure modes that can slip through `make ci-run` and only surface on real GitHub Actions: ZAP rule additions/removals (run `make dast` locally before push), nginx response-header regressions that ZAP catches but e2e doesn't, and any `actions/upload-artifact@v7+` migration breakage. Mitigation: every nginx.conf edit MUST be followed by `make dast` locally before push.
- `lighthouse` job: install -> `make lighthouse` (Lighthouse CI budgets against the built container; uploads the report). Uses the runner's pre-installed `google-chrome`; `@lhci/cli` is run via pinned `npx` (`LHCI_VERSION` in the Makefile, Renovate-tracked) rather than a devDependency, so its heavy transitive tree stays OUT of `pnpm-lock.yaml` (keeps `pnpm audit`/`vulncheck` clean — the same npx-pinned pattern as `renovate`/`depcheck`). The committed `lighthouserc.json` sets thresholds (perf ≥0.9, a11y ≥0.95, best-practices ≥0.95, SEO ≥0.9). SEO is kept at 100 by `<meta name="description">` in `index.html` + `public/robots.txt`. **Skipped under act** (needs Chrome + DinD + `upload-artifact@v7`).
- `ci-pass` job (aggregation gate, `if: always()`, `needs: [changes, static-check, build, test, e2e, e2e-browser, lighthouse, docker, dast]`): single check suitable for branch protection.
- Docker images pushed to `ghcr.io` as multi-arch (`amd64` + `arm64`) with GHA build cache.
- Permissions: `contents: read` at workflow level; `packages: write` + `id-token: write` (cosign OIDC) on docker job only; `pull-requests: read` on changes job.

Diagram regen (`.github/workflows/diagram-regen.yml`):

- Triggers on `pull_request` (`opened`/`synchronize`/`reopened`/`labeled`) that touches `docs/diagrams/**/*.puml` or `Makefile` (which carries `PLANTUML_VERSION`), **and** is either from `renovate[bot]` or carries the `regen-diagrams` label (an on-demand "force-regenerate" button — only write-access users can apply labels). Solves the structural problem that **Renovate (Mend Cloud) cannot run `make diagrams`**: a render-affecting bump (the C4-PlantUML `!include` version, the `plantuml/plantuml` image) drifts the committed PNG from source, so `diagrams-check` fails until the PNG is regenerated.
- The job runs `make diagrams` and, if the committed PNG drifted, commits it back to the PR head. **It does NOT auto-merge** (deliberate): `main` is Ruleset-gated, and a GITHUB_TOKEN commit-back push is held `action_required` (anti-recursion) so its CI never enters the PR's check rollup → the PR stays BLOCKED. A hands-off path would require pushing with a GitHub App/PAT token (not GITHUB_TOKEN) — see the `/ci-workflow` rule "workflow_dispatch re-trigger does NOT unblock a Repository-RULESET-gated PR"; we chose not to manage that secret. **The PNG regeneration is automated; finishing the merge is MANUAL**: approve the held CI run on the PR (Actions → "Approve and run"), or locally `make diagrams && git commit && git push` (a non-bot push runs CI in PR context and unblocks).
- Permissions: `contents: write` only; no `actions:`/`pull-requests:`/`packages: write`. A recursion guard skips when the branch tip is already `github-actions[bot]`. No secret required. Skipped under act (not exercised by `make ci-run`).

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
- **Node toolchain (`.nvmrc` + Dockerfile `FROM node`):** both pins are tracked by Renovate's **docker** datasource — the Dockerfile via the built-in `dockerfile` manager, and `.nvmrc` via a `custom.regex` manager (the built-in `nvm` manager is **disabled** in `enabledManagers`). They share the "Node toolchain" group (matched by `depName: node`) so they bump together. Resolving both from the *same* datasource is what keeps them aligned: the `nvm` manager's `node-version` datasource follows nodejs.org, which leads Docker Hub by hours-to-a-day on each Node release — so the old `nvm`+`dockerfile` grouping opened PRs with `.nvmrc` ahead of the Dockerfile, failing `make check-node-alignment` until Docker Hub caught up. With both on the docker datasource, the grouped PR only ever proposes a version Docker Hub has actually published. `.nvmrc` carries `pinDigests: false` so it stays a bare version mise/corepack can read. Enforced by `make check-node-alignment` (part of `static-check`). The `Node.js <ver>` string in the README Tech Stack table is **also** tracked by a third `custom.regex` manager (same docker-datasource + alpine-variant + bare-writeback pattern, `pinDigests: false`), grouped into the same "Node toolchain" PR — so the doc version bumps in lockstep with `.nvmrc`/Dockerfile and never needs a manual re-sync.
- **Prettier:** uses defaults (no config file)
- **Vitest:** unit tests with `@testing-library/react` and `jest-dom` matchers; coverage via `@vitest/coverage-v8` with thresholds; config in `vite.config.ts`; setup in `src/test/setup.ts`
- **Mermaid lint:** every `` ```mermaid `` block in README.md / CLAUDE.md is parsed by pinned `minlag/mermaid-cli` (`make mermaid-lint`, script at `scripts/mermaid-lint.sh`); part of `make static-check` composite gate. Currently no Mermaid blocks exist (the architecture hero migrated to PlantUML, below) — the gate stays wired and self-skips with "no mermaid blocks found", ready for any future inline sequence/flow diagram
- **Architecture diagrams (PlantUML C4):** the README hero is a C4 Context diagram authored in `docs/diagrams/c4-context.puml` (C4-PlantUML `!include` version-pinned + Renovate-tracked via a `custom.regex` manager, modern-flat theme) and rendered to a committed PNG under `docs/diagrams/out/` via the pinned `plantuml/plantuml` Docker image (`PLANTUML_VERSION` in the Makefile, Renovate-tracked). `make diagrams` renders; `make diagrams-check` (a `git diff --exit-code` drift gate in `static-check`) fails if the committed PNG diverges from current source. A version-stamped sentinel (`docs/diagrams/out/.plantuml-*.stamp`, gitignored) forces a full re-render on a `PLANTUML_VERSION` bump so a renderer bump can't ship stale PNGs. Because Renovate can't run `make diagrams`, a render-affecting bump (the `!include` version or `PLANTUML_VERSION`) fails `diagrams-check` until the PNG is regenerated — `diagram-regen.yml` (see CI/CD) renders + commits the PNG back to the bump PR automatically (or on the `regen-diagrams` label), but the merge is finished manually (Ruleset blocks the bot's commit-back CI; approve the held run or push a local `make diagrams` commit). Rendering is skipped under act (DinD bind-mount), same as mermaid-lint
- **Shell-script executable-bit guard:** `make lint` runs `find scripts -name '*.sh' -not -executable` so subagent-created scripts (Write tool defaults to mode 0644) don't ship with the executable bit missing.
- **Minifier-deps guard:** `make check-minifier-deps` asserts every minifier named in `vite.config.ts` (terser, esbuild) is a declared dependency, guarding the Vite optional-peer trap where a config string references a minifier that isn't installed; part of `make static-check` composite gate.
- **apk-upgrade mechanism gate:** `scripts/check-apk-upgraded.sh` asserts `apk list --upgradable` is empty in the built image (`make image-apk-check`; CI runs it in the `docker` job after the Trivy scan). It gates the **mechanism** ("did the patch step run?") rather than the **outcome** ("is a CVE scored?"), which matters because a Trivy RED needs a scored CVE to exist and so cannot be produced on demand — nobody had ever demonstrated that gate firing. This one's RED is always available (proven: 6 packages upgradable on the pre-fix base, exit 1) and is strictly more sensitive, firing on package drift *before* a CVE is scored — it caught `freetype`/`tzdata`, which carry no HIGH and which Trivy therefore ignores. It does **not** replace Trivy, which catches vulnerabilities in artifacts `apk` cannot fix (e.g. the nginx binary when upstream hasn't rebuilt). Needs `--user 0` (image is `USER 101`) and network egress; a failed `apk update` is reported as an error, never as a pass.
- **Dockerfile-stage guard:** `make check-dockerfile-stage` (`scripts/check-dockerfile-stage.sh`) makes `no-cache-filters` fail **closed**. It derives the final stage name from the Dockerfile (never re-typing it) and asserts (1) every `no-cache-filters:` value in `ci.yml` matches it, and (2) the count of gha-cache-importing builds equals the count carrying the filter — so a *new* cached build cannot be added without one. Both directions RED-proven. Part of `make static-check`.

## Upgrade Backlog

Last reviewed: 2026-07-20 (apk-upgrade cache-inertness fix)

- [ ] **`make image-apk-check` measures the WRONG PROPERTY — replace it with an execution marker.** Shipped in PR #372 and then refuted the same day by an adversary round (correction merged as claude-config#76). `apk list --upgradable` asserts *"nothing is upgradable right now"* (world-state), not *"the patch layer executed"* (the mechanism it exists to gate). So it reddens whenever Alpine publishes a package between build and check — a cause the operator cannot fix — and it needs network + `apk update`, so a missing index makes it print nothing and exit **0**. ⚠️ That guard was **written but unreachable** until 2026-07-20: the pipeline's `| grep 'upgradable from:'` stripped the `APK_UPDATE_FAILED` sentinel *before* the check that looked for it, and `|| true` swallowed a `docker run` failure the same way — so the gate built to prevent a false green had two of its own (both measured, both now fail closed, all five paths RED/GREEN-proven). An earlier revision of this entry claimed "our script does guard that case explicitly"; it did not. Replacement: `ARG BUILD_RUN_ID` fed `${{ github.run_id }}`, written by the patch layer itself (`RUN apk --no-cache upgrade && printf '%s' "$BUILD_RUN_ID" > /etc/.patch-run-id`), then assert the shipped image's marker equals this run's. Deterministic, offline, no feed dependency — and fed a per-run value the marker *is* the bust, so it could replace `no-cache-filters` rather than sit beside it. Keep the current check only as an advisory.
- [ ] **`make check-dockerfile-stage` coverage — stated positively, because two earlier revisions of this entry overstated it.** It DOES cover: ci.yml `docker/build-push-action` steps (per-step, incl. block-scalar `cache-from: |`), and Makefile build lines incl. `\`-continuations and both `docker build` / `buildx build`. It does NOT cover: a flag supplied through a **Make variable** (`--cache-from $(DOCKER_CACHE)` — no regex can expand it), a `docker buildx build` inside a **workflow `run:` step**, builders under **`scripts/`** or an included **`*.mk`**. Note the Makefile population is **currently zero** (`image-build` filters but imports no cache), so check 3a examines nothing today — the PASS line says so explicitly rather than printing a reassuring ratio.
- [ ] **Stage derivation can pick a WRONG non-empty stage from a Dockerfile heredoc.** A `FROM x AS decoy` inside a heredoc *after* the real final stage is derived as the final stage; the gate would then instruct setting `no-cache-filters: decoy`, which silently no-ops — re-creating the original bug. Not reachable today (this Dockerfile has no heredocs); latent. A real fix needs heredoc-aware parsing, not another regex.

- [ ] **`linux/arm64` is published, cosign-signed, and has NEVER been CVE-scanned.** Both scan builds pin `platforms: linux/amd64`, and Trivy resolves a multi-arch manifest to the runner's platform — so the post-push digest scan added 2026-07-20 also covers amd64 only. `apk` resolves a different package set per arch, so an arm64-only fixable HIGH would ship undetected. Fix by adding a second scan leg (`--platform linux/arm64`, or an arm64 `load: true` build — QEMU is already set up). Pre-existing; not introduced by the cache fix.
- [ ] **`ci-pass` treats `skipped` as pass.** It fails only on `contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')`. Today no security-relevant job is conditional, so this is latent — but `e2e-browser`, `dast` and `lighthouse` are all gated `if: ${{ vars.ACT != 'true' }}`, so setting the repo variable `ACT=true` would silently skip three gates and still report green. If any `ci-pass`-needed job ever becomes conditional, require explicit `success` rather than "not failure".

- [ ] **`undici` override (`pnpm-workspace.yaml`) + `<8` cap (`renovate.json`)** — `undici@>=7.0.0 <7.28.0` is overridden to `^7.28.0` to clear the TLS cert-validation-bypass / WebSocket-DoS / cross-origin-routing advisories (transitive via `@vitest/coverage-v8 > vitest > jsdom > undici`). A Renovate `allowedVersions: <8` cap holds it on the 7.x line because jsdom 29.1.1 hard-requires `undici/lib/handler/wrap-handler.js`, which undici v8 removed (verified: PR #303 broke the vitest/jsdom runtime and was closed). Remove both the override and the `<8` cap when jsdom ships a release that consumes `undici >= 8` directly.
- [ ] **`brace-expansion` override (`pnpm-workspace.yaml`)** — `brace-expansion@>=5.0.0 <5.0.7` is overridden to `^5.0.7` to clear the DoS advisory GHSA-3jxr-9vmj-r5cp (transitive via eslint). The floor moved from 5.0.6→5.0.7 when the advisory's patched version was published, making the prior 5.0.6 pin vulnerable. Remove when eslint pulls `brace-expansion >= 5.0.7` directly.

## Skills

Use the following skills when working on related files:

| File(s)                          | Skill          |
| -------------------------------- | -------------- |
| `Makefile`                       | `/makefile`    |
| `renovate.json`                  | `/renovate`    |
| `README.md`                      | `/readme`      |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |
| `docs/diagrams/*.puml`, README/CLAUDE Mermaid blocks | `/architecture-diagrams` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
