# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

**Package manager:** pnpm (via corepack)

```bash
make deps              # Install system dependencies (node, pnpm, docker, git) if missing
make install           # pnpm install (runs deps first)
make lint              # ESLint (runs install first)
make build             # TypeScript check + Vite production build (runs install first)
make run               # Start Vite dev server with HMR
make clean             # Remove node_modules/ and dist/
make image             # Build Docker image (nginx-unprivileged)
make release VERSION=vX.Y.Z  # Tag and push a release
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

- **Entry:** `index.html` → `src/main.tsx` (React Router setup) → `src/App.tsx`
- **Routing:** React Router DOM v7, configured in `src/main.tsx`
- **State:** React Context API (ThemeContext for light/dark theme), standard hooks
- **Path alias:** `@` → `src/` (configured in `vite.config.ts` and `tsconfig.json`)
- **Performance:** Web Vitals reporting via `src/reportWebVitals.ts` + `src/reportHandler.tsx`

## Build & Bundle Config

Vite config (`vite.config.ts`):

- Target: ES2022
- Terser minification — drops `console.*` and `debugger` in production
- CSS minification: esbuild (`build.cssMinify`) — lightningcss default doesn't accept ES year targets
- Manual chunks: `react` vendor bundle, `react-router-dom` bundle
- CommonJS interop enabled for mixed ESM modules
- Bundler: Rolldown (Vite 8 default, replaces Rollup)

## Docker & Deployment

Multi-stage build: Node 24 Alpine builder → `nginxinc/nginx-unprivileged` server.

Nginx (`nginx/nginx.conf`):

- Listens on port 8080
- SPA fallback: `try_files $uri /index.html`
- Health endpoints: `/internal/isalive`, `/internal/isready`
- Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`):

- Triggers: push to `main`, tags `v*`, pull requests
- Steps: checkout → corepack → setup-node (with pnpm cache) → install → lint (`make lint`) → build (`make build`) → Docker build (push on tags only)
- Docker images pushed to `ghcr.io` on version tags

## Code Quality

- **ESLint:** flat config (`eslint.config.js`) with `typescript-eslint`, `eslint-plugin-react-hooks`, `eslint-plugin-react-refresh`
- **Pre-commit:** lint-staged runs Prettier on staged files
- **Renovate:** auto-merges all dependency updates after CI passes (daily schedule)
- **Prettier:** uses defaults (empty `.prettierrc`)
