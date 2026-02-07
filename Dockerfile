# https://hub.docker.com/_/node/tags
FROM node:24.13.0-alpine@sha256:cd6fb7efa6490f039f3471a189214d5f548c11df1ff9e5b181aa49e22c14383e AS builder
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
FROM nginxinc/nginx-unprivileged:1.29.5@sha256:18649fec7f0cba6b99f796e108aaee069d65c06e498c775d05caec6092cad750 AS server
COPY ./nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder ./app/dist /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
