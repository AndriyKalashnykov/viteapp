# https://hub.docker.com/_/node/tags
FROM node:22.22.0-alpine@sha256:a9cd9bac76cf2396abf14ff0d1c3671a8175fe577ce350e62ab0fc1678050176 AS builder
RUN apk --no-cache add git
RUN npm --global install pnpm && pnpm self-update
WORKDIR /app
COPY package.json ./
COPY .npmrc ./
RUN pnpm install
# RUN npm install --legacy-peer-deps
COPY . .
RUN pnpm build
#RUN npm run build

# https://hub.docker.com/r/nginxinc/nginx-unprivileged/tags
FROM nginxinc/nginx-unprivileged:1.29.3@sha256:179ed2af73a233a751d9b55565172f45ff9e14d69713277074003bad98f24830 AS server
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
