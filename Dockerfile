# syntax=docker/dockerfile:1
# https://hub.docker.com/_/node/tags
FROM node:24.15.0-alpine@sha256:8e2c930fda481a6ec141fe5a88e8c249c69f8102fe98af505f38c081649ea749 AS builder
# Corepack reads the pnpm version from package.json's `packageManager` field
# (single source of truth) — no hardcoded version here. COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# suppresses corepack's interactive download-consent prompt so the first pnpm
# invocation provisions pnpm non-interactively (it otherwise blocks the build on
# stdin right after a pnpm major bump).
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
WORKDIR /app
# pnpm-workspace.yaml carries the `overrides` (pnpm 10+ location) — REQUIRED for
# --frozen-lockfile to resolve the CVE-patched transitive deps inside the image.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# https://hub.docker.com/_/nginx/tags
# Official nginx alpine image. We add the unprivileged-user setup ourselves
# (UID 101, /tmp PID file, chown of writable dirs) so the image still runs as
# non-root and listens on port 8080. Tracking the official image directly gets
# us upstream nginx security patches the same day they ship — the
# nginxinc/nginx-unprivileged variant lags the official rebuild cadence by
# multiple patch releases (it was stuck at 1.29.5 while upstream shipped
# 1.29.6/7/8). `apk upgrade --no-cache` patches any HIGH/CRITICAL Alpine CVEs
# fixed upstream but not yet rebuilt into the base image. Required to keep the
# Trivy pre-push gate clean.
FROM nginx:1.30.0-alpine@sha256:e544ba68e68ddbcdff106010fa82f4ab30378899e78d4ff7aadf4ef5a7c65091 AS server
# Drop the `user nginx;` directive (we run the entire process as UID 101 via
# the USER instruction below — no setuid required) and relocate the PID file
# to /tmp because /run is not writable by an unprivileged user. Default temp
# paths under /var/cache/nginx are made writable via chown. Mirrors the
# transformations done by nginxinc/nginx-unprivileged.
RUN apk upgrade --no-cache && \
    sed -i '/^user  nginx;/d' /etc/nginx/nginx.conf && \
    sed -i 's,^pid        /run/nginx.pid;,pid        /tmp/nginx.pid;,' /etc/nginx/nginx.conf && \
    chown -R 101:101 /var/cache/nginx /var/log/nginx
USER 101
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/internal/isalive || exit 1
CMD ["nginx", "-g", "daemon off;"]
