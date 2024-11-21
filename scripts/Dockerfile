FROM node:18-bullseye-slim
WORKDIR /workspace
COPY ./package.json ./yarn.lock ./
RUN yarn
COPY ./*.ts ./tsconfig.json ./
#RUN mkdir /config
# populate this file with valid json that will later be overwritten. If we don't do this the docker image won't build because of typescript looking for this file before the volume that contains it is mounted (I assume)
#RUN cp ./tsconfig.json /config/l2_chain_info.json
RUN yarn build
ENTRYPOINT ["node", "index.js"]
