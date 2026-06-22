FROM node:26.3.1@sha256:3c05c2cf0f6a5795dfb7abefb2a4e31a78d6271a99962531c48315ced17d618a

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
    .solhintignore \
    .solhint.json \
    .solhintignore \
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
