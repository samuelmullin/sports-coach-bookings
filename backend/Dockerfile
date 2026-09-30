# syntax=docker/dockerfile:1
#
# SportsCoachBookings backend release image.
#
# Build from the REPO ROOT (the build context is the repository):
#
#     docker build -f backend/Dockerfile -t scb-backend .
#
# Stages:
#   1. frontend   - builds the admin + portal SPA bundles (Vite) with pnpm
#   2. builder    - compiles the Elixir release (MIX_ENV=prod) and Phoenix assets
#   3. runtime    - minimal Debian image with the release + SPA bundles
#
# The release is started via /app/bin/server (sets PHX_SERVER=true). Migrations
# run via /app/bin/migrate (platform release_command). Nothing here needs
# secrets at build time.

ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim
ARG DEBIAN_IMAGE=debian:bookworm-20260918-slim
ARG NODE_IMAGE=node:22-bookworm-slim

# --- 1. Frontend (static bundles) -----------------------------------------
FROM ${NODE_IMAGE} AS frontend

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@12 --activate

WORKDIR /build/frontend
COPY frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml ./
COPY frontend/apps/admin/package.json apps/admin/package.json
COPY frontend/apps/portal/package.json apps/portal/package.json
COPY frontend/packages/ui/package.json packages/ui/package.json
COPY frontend/packages/api-client/package.json packages/api-client/package.json
COPY frontend/packages/mocks/package.json packages/mocks/package.json
RUN pnpm install --frozen-lockfile

COPY frontend/ ./
RUN pnpm -r build

# --- 2. Backend builder ----------------------------------------------------
FROM ${ELIXIR_IMAGE} AS builder

ENV MIX_ENV=prod
WORKDIR /build/backend

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Toolchain first (cached), then deps.
RUN mix local.hex --force && mix local.rebar --force
COPY backend/mix.exs backend/mix.lock ./
RUN mix deps.get --only prod

# Full source; recompile as needed. Runtime config is not evaluated here.
COPY backend/ ./
RUN mix deps.compile

# Phoenix static assets (esbuild + tailwind + phx.digest). The product UI is
# the SPA, but prod.exs references the digested cache manifest. `mix compile`
# first generates the Phoenix colocated CSS that tailwind imports.
RUN mix compile && mix assets.setup && mix assets.deploy

RUN mix release

# --- 3. Runtime ------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS runtime

ENV LANG=C.UTF-8
ENV REPO_ROOT=/app
ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=4000

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
      ca-certificates libstdc++6 openssl libncurses6 locales tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash --uid 10001 app
WORKDIR /app

COPY --from=builder --chown=app:app /build/backend/_build/prod/rel/sports_coach_bookings ./
# SPA bundles served by SpaController under /admin and /. REPO_ROOT=/app means
# this path resolves to /app/frontend/apps/<app>/dist at runtime.
COPY --from=frontend --chown=app:app /build/frontend/apps/admin/dist ./frontend/apps/admin/dist
COPY --from=frontend --chown=app:app /build/frontend/apps/portal/dist ./frontend/apps/portal/dist

USER app
EXPOSE 4000

# Platform health checks (Fly) hit /health; see fly.toml. A local docker run can
# use: curl -fsS http://localhost:4000/health
CMD ["/app/bin/server"]
