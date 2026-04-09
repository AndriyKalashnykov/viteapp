# syntax=docker/dockerfile:1
# https://hub.docker.com/_/node/tags
FROM node:24.14.1-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b AS builder
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# https://hub.docker.com/r/nginxinc/nginx-unprivileged/tags
# Alpine-slim: smaller attack surface than the Debian variant (no libpng/libtiff
# for a static-file server), fewer CVEs. `apk upgrade --no-cache` patches any
# HIGH/CRITICAL CVEs fixed upstream but not yet rebuilt into the base image
# (e.g. zlib CVE-2026-22184). Required to keep the Trivy pre-push gate clean.
FROM nginxinc/nginx-unprivileged:1.29.5-alpine-slim@sha256:e3a8cb843fb17e660bc43c77358a940f00eef7f99545ed3121f476b845109fdf AS server
USER 0
RUN apk upgrade --no-cache
USER 101
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/internal/isalive || exit 1
CMD ["nginx", "-g", "daemon off;"]
