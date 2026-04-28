FROM node:20.15.1@sha256:6326b52a508f0d99ffdbfaa29a69380321b215153db6f32974835bac71b38fa4

RUN apt-get update -y && \
    apt-get install -y -qq --no-install-recommends jq && \
    apt-get clean

USER node

WORKDIR /home/node

COPY --chown=node:node package.json \
    package-lock.json \
    deploy.sh \
    .solhintignore \
    .solhint.json \
    hardhat.config.ts \
    tsconfig.json \
    addresses.json ./

RUN npm ci --ignore-scripts

COPY --chown=node:node tasks ./tasks
COPY --chown=node:node scripts ./scripts
COPY --chown=node:node contracts ./contracts

RUN npm run compile

ENTRYPOINT [ "./deploy.sh" ]
