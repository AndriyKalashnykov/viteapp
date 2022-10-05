# viteapp

## Requirements

* [nvm](https://github.com/nvm-sh/nvm#install--update-script)
  ```bash
  nvm install v17.4.0
  nvm use v17.4.0
  ```
* [pnpm](https://pnpm.io/installation)

## Help 

```bash
$ make help
```
```text
Usage: make COMMAND
Commands :
help           - List available tasks
clean          - Cleanup
install        - Install
build          - Build
update         - Update
upgrade        - Upgrade
run            - Run
image          - Build Docker Image
check-version  - Ensure VERSION variable is set
release        - Creates and pushes tag for the current $VERSION
tag-release    - Create and push a new tag

```

## Create react app

```bash
pnpm create vite viteapp -- --template react
pnpm add graphql urql
pnpm install
pnpm build
pnpm run dev
```

## Release

Set version as env variable
```bash
export VERSION=v0.0.1
```

run release task
```bash
make release
```

## References
* https://fullstackcode.dev/2022/01/30/creating-react-js-app-using-vite-2-0/
* https://blog.logrocket.com/vite-3-vs-create-react-app-comparison-migration-guide/

###  React.js Setup for GraphQL using Vite and urql
* https://www.youtube.com/watch?v=x4Rc3RytAls&t=356s&ab_channel=ZaisteProgramming
* https://zaiste.net/posts/modern-lightweight-reactjs-setup-graphql-vite-urql/
