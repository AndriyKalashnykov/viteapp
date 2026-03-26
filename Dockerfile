# https://hub.docker.com/_/node/tags
FROM node:24.14.0-alpine@sha256:7fddd9ddeae8196abf4a3ef2de34e11f7b1a722119f91f28ddf1e99dcafdf114 AS builder
RUN corepack enable && corepack prepare pnpm@10.32.1 --activate
WORKDIR /app
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# https://hub.docker.com/r/nginxinc/nginx-unprivileged/tags
FROM nginxinc/nginx-unprivileged:1.29.5@sha256:a4b4d6c0ea8ecf5af39ca16ffd0b388aa3afd66108883560f78adb13e84d193e AS server
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/internal/isalive || exit 1
CMD ["nginx", "-g", "daemon off;"]
