FROM node:20-bookworm-slim
ARG NITRO_CONTRACTS_BRANCH=celestia-integration
ARG NITRO_CONTRACTS_REPO=https://github.com/EspressoSystems/nitro-contracts.git
RUN apt-get update && \
    apt-get install -y git docker.io python3 build-essential curl jq
WORKDIR /workspace  
RUN git clone --recurse-submodules --no-checkout ${NITRO_CONTRACTS_REPO} ./
RUN git checkout ${NITRO_CONTRACTS_BRANCH}
RUN git submodule update --init --recursive
RUN yarn install && yarn cache clean
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="${PATH}:/root/.foundry/bin"
RUN foundryup --install 1.0.0
RUN touch scripts/config.ts
RUN yarn build:all
ENTRYPOINT ["yarn"]
