FROM node:18-bullseye-slim
ENV NITRO_CONTRACTS_BRANCH=export-reader-addr
ENV NITRO_CONTRACTS_REPO=https://github.com/EspressoSystems/nitro-contracts.git
RUN apt-get update && \
    apt-get install -y git docker.io python3 build-essential curl jq
WORKDIR /workspace  
RUN git clone --no-checkout ${NITRO_CONTRACTS_REPO} ./
RUN git fetch
RUN git stash
RUN git checkout -b ${NITRO_CONTRACTS_BRANCH}
RUN git pull origin ${NITRO_CONTRACTS_BRANCH}
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="${PATH}:/root/.foundry/bin"
RUN foundryup
RUN forge update lib/forge-std
RUN git submodule update --init --recursive
RUN touch scripts/config.ts
RUN yarn install
RUN yarn build:all
ENTRYPOINT ["yarn"]
