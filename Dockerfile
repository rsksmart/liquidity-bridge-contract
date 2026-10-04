FROM node:20.15.1@sha256:6326b52a508f0d99ffdbfaa29a69380321b215153db6f32974835bac71b38fa4

ARG VCS_REF=unknown
ARG VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/rsksmart/liquidity-bridge-contract"
LABEL org.opencontainers.image.revision="${VCS_REF}"
LABEL org.opencontainers.image.version="${VERSION}"

# Install required tools
RUN apt-get update -y && \
    apt-get install -y -qq --no-install-recommends jq make curl && \
    apt-get clean

USER node

# Install Foundry as node so its bin/ symlinks point into /home/node/.foundry
RUN curl -L https://foundry.paradigm.xyz | bash && \
    /home/node/.foundry/bin/foundryup --install v1.7.1

# Add Foundry to PATH
ENV PATH="/home/node/.foundry/bin:${PATH}"

WORKDIR /home/node

COPY --chown=node:node package.json \
    package-lock.json \
    deploy.sh \
    .solhintignore \
    .solhint.json \
    tsconfig.json \
    addresses.json \
    foundry.toml \
    Makefile ./

# Install npm dependencies
RUN npm ci --ignore-scripts

# Install Foundry dependencies (forge-std)
COPY --chown=node:node lib ./lib

# Copy contracts and deployment scripts
COPY --chown=node:node src ./src
COPY --chown=node:node script ./script

RUN npm run compile

ENTRYPOINT [ "./deploy.sh" ]
