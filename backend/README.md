# SportsCoachBookings — backend

Phoenix JSON API + OTP release. See `../00-shared-context.md`,
`../docs/conventions.md`, and `../docs/erd.md` for the architecture.

## Local development

```bash
docker compose up -d postgres minio   # from the repo root
mix setup                              # deps, create/migrate, seeds, assets
mix phx.server                         # http://demo.localhost:4000
```

The app connects as the non-superuser role `scb_app`/`scb_app`; RLS is bypassed
by superusers, so never point the app at the `postgres` role
(`docs/conventions.md` §1.4).

## Checks

```bash
mix test                  # ecto.create/migrate, then ExUnit
mix precommit             # compile --warnings-as-errors, format, credo --strict, test
mix app.openapi.export    # writes ../docs/openapi.json (CI checks for drift)
```

## Release & deploy

The backend ships as an Elixir release inside a Docker image built from the repo
root (the image also builds and embeds the frontend SPA bundles):

```bash
docker build -f backend/Dockerfile -t scb-backend .
docker run --rm --env-file .env scb-backend /app/bin/migrate   # migrate once
docker run --env-file .env -p 4000:4000 scb-backend             # /app/bin/server
```

Inside a release:

| Command | Purpose |
|---|---|
| `bin/sports_coach_bookings start` | Start the app (server enabled via `PHX_SERVER=true`). |
| `bin/migrate` | Run pending migrations (`SportsCoachBookings.Release.migrate/0`). |
| `bin/seed` | Seed the `demo` tenant — **staging only**. |
| `bin/server` | Migrate-free start; the platform runs migrations via `release_command`. |

Production runs on Fly.io in `yyz` (Toronto). `fly.toml` / `fly.staging.toml`
define the region, health checks, and `release_command`. **Full runbook —
deploy, rollback, migrations, backups, secrets, scaling, incident notes:
[`docs/ops.md`](../docs/ops.md).** Required runtime secrets are listed there and
in `.env.example`; the release refuses to boot without the required ones.

Quick deploy:

```bash
fly secrets import --app <app> < .env.production
fly deploy --config fly.toml          # or: git tag v0.1.0 && git push origin v0.1.0
```

CI (`.github/workflows/ci.yml`) must pass before `.github/workflows/deploy.yml`
builds and releases.
