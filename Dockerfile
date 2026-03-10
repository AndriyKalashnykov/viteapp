# https://hub.docker.com/_/node/tags
FROM node:24.14.0-alpine@sha256:7fddd9ddeae8196abf4a3ef2de34e11f7b1a722119f91f28ddf1e99dcafdf114 AS builder
RUN apk --no-cache add git
RUN npm --global install pnpm && pnpm self-update
WORKDIR /app
COPY package.json pnpm-lock.yaml .npmrc ./
RUN pnpm install
# RUN npm install --legacy-peer-deps
COPY . .
RUN pnpm build
#RUN npm run build

# https://hub.docker.com/r/nginxinc/nginx-unprivileged/tags
FROM nginxinc/nginx-unprivileged:1.29.5@sha256:204990d7b7ae5582931869d3bb62f56fdd1b3d8de7a5209e36f15074861319e1 AS server
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
