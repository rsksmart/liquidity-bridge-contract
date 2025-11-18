FROM node:20.15.1@sha256:6326b52a508f0d99ffdbfaa29a69380321b215153db6f32974835bac71b38fa4

# Install Foundry and required tools
RUN apt-get update -y && \
    apt-get install -y -qq --no-install-recommends jq make curl && \
    apt-get clean && \
    curl -L https://foundry.paradigm.xyz | bash && \
    /root/.foundry/bin/foundryup && \
    cp -r /root/.foundry /home/node/.foundry && \
    chown -R node:node /home/node/.foundry

USER node

# Add Foundry to PATH
ENV PATH="/home/node/.foundry/bin:${PATH}"

WORKDIR /home/node

COPY --chown=node:node package.json \
    package-lock.json \
    deploy.sh \
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
COPY --chown=node:node contracts ./contracts
COPY --chown=node:node forge-scripts ./forge-scripts

RUN npm run compile

ENTRYPOINT [ "./deploy.sh" ]
