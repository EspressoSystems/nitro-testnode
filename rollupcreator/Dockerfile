FROM node:20-bookworm-slim
ARG NITRO_CONTRACTS_BRANCH=main
ARG NITRO_CONTRACTS_REPO=https://github.com/OffchainLabs/nitro-contracts.git
RUN apt-get update
RUN apt-get install -y git
RUN apt-get install -y docker.io
RUN apt-get install -y python3
RUN apt-get install -y build-essential
RUN apt-get install -y curl jq
WORKDIR /workspace  
RUN git clone --no-checkout ${NITRO_CONTRACTS_REPO} ./
RUN git checkout ${NITRO_CONTRACTS_BRANCH}
RUN git submodule update --init --recursive
RUN yarn install && yarn cache clean
RUN curl -L https://foundry.paradigm.xyz | bash
ENV PATH="${PATH}:/root/.foundry/bin"
RUN foundryup --install 1.0.0
RUN touch scripts/config.ts
RUN yarn install
RUN yarn build:all
ENTRYPOINT ["yarn"]
