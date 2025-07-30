FROM node:18-bullseye-slim
WORKDIR /workspace

COPY ./package.json ./
RUN yarn
COPY ./*.ts ./tsconfig.json ./
RUN yarn build

CMD ["node", "dist/index.js"]
