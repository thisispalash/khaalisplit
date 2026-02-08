FROM node:24-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends postgresql-client && \
    rm -rf /var/lib/apt/lists/*

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN npm install -g pnpm@9

WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile || pnpm install

COPY config.yaml schema.graphql tsconfig.json ./
COPY abis/ abis/

RUN pnpm envio codegen

COPY src/ src/

CMD ["pnpm", "envio", "start"]
