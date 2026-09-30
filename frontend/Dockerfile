# Frontend static image (optional deployment path).
#
# The backend release image already serves the built SPA bundles via
# SpaController. This image exists for deploying the frontend to a separate
# static host / CDN with its own cache and scaling characteristics. It builds
# the admin and portal bundles and serves them with nginx.
#
# Build from the REPO ROOT:
#
#     docker build -f frontend/Dockerfile -t scb-frontend .
#
# Note: when served separately from Phoenix, the SPA must call the API on the
# wildcard domain; the two bundles expect to be mounted at /admin and /.
# See docs/ops.md ("Separate static frontend").

ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${NODE_IMAGE} AS build

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

FROM nginx:1.27-alpine AS runtime

COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /build/frontend/apps/portal/dist /usr/share/nginx/html
COPY --from=build /build/frontend/apps/admin/dist /usr/share/nginx/html/admin

EXPOSE 80
