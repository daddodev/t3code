# syntax=docker/dockerfile:1.7

FROM node:24.13.1-bookworm AS build

WORKDIR /app

# node-pty falls back to a native build on platforms without a matching prebuild.
RUN apt-get update \
  && apt-get install --yes --no-install-recommends build-essential python3 \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@11.10.0 --activate

COPY . ./

RUN --mount=type=cache,id=t3code-pnpm-store,target=/root/.local/share/pnpm/store \
  pnpm install --frozen-lockfile

# The server build bundles the web client into apps/server/dist/client.
RUN pnpm exec vp run --filter t3 build \
  && pnpm --filter t3 deploy --prod --legacy --config.allowUnusedPatches=true /runtime

FROM node:24.13.1-bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install --yes --no-install-recommends \
    bubblewrap \
    ca-certificates \
    gh \
    git \
    openssh-client \
    tini \
  && rm -rf /var/lib/apt/lists/*

# Provider CLIs are part of the image so a fresh container is immediately usable.
RUN npm install --global \
  @anthropic-ai/claude-code@latest \
  @openai/codex@latest \
  opencode-ai@latest \
  && npm cache clean --force \
  && mv /usr/local/bin/codex /usr/local/bin/codex-cli

WORKDIR /workspace

COPY --from=build --chown=node:node /runtime /opt/t3
COPY --chown=node:node scripts/container-codex.sh /usr/local/bin/codex
RUN chmod 755 /usr/local/bin/codex \
  && mkdir /data \
  && chown node:node /data

ENV NODE_ENV=production \
  T3CODE_HOME=/data \
  T3CODE_HOST=0.0.0.0 \
  T3CODE_PORT=3773 \
  T3CODE_NO_BROWSER=true

USER node

EXPOSE 3773

ENTRYPOINT ["tini", "--"]
CMD ["node", "/opt/t3/dist/bin.mjs", "serve", "--host", "0.0.0.0", "--port", "3773", "--base-dir", "/data", "/workspace"]
