# https://hub.docker.com/_/node/tags
FROM node:24.13.1-alpine@sha256:4f696fbf39f383c1e486030ba6b289a5d9af541642fc78ab197e584a113b9c03 AS builder
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
FROM nginxinc/nginx-unprivileged:1.29.5@sha256:0ac6770a4747ee05799deba85731496e001bbfdcd204a27f364090fa9ad77157 AS server
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
