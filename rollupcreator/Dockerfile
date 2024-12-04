FROM node:18-bullseye-slim
ARG NITRO_CONTRACTS_BRANCH=celestia-integration
ARG NITRO_CONTRACTS_REPO=https://github.com/EspressoSystems/nitro-contracts.git
RUN apt-get update && \
    apt-get install -y git docker.io python3 build-essential curl jq
WORKDIR /workspace  
RUN git clone --branch ${NITRO_CONTRACTS_BRANCH} --recurse-submodules ${NITRO_CONTRACTS_REPO} ./
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="${PATH}:/root/.foundry/bin"
RUN foundryup
RUN forge update lib/forge-std
RUN git submodule update --init --recursive
RUN touch scripts/config.ts
RUN yarn install
RUN yarn build:all
ENTRYPOINT ["yarn"]
