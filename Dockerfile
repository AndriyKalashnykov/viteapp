# syntax=docker/dockerfile:1
# https://hub.docker.com/_/node/tags
FROM node:24.14.1-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b AS builder
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
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
FROM nginx:1.29.8-alpine@sha256:2c4de29ca0588f9b56ced6691e0c605c2fd00501478e2e12949ba062304bc1ca AS server
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
