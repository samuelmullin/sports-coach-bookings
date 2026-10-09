#!/usr/bin/env bash
# Recreates and seeds the dedicated e2e database (never touches the dev DB).
#
# Needs a Postgres superuser to (re)create the database. Locally that is the
# docker-compose container; in CI set PSQL to a psql invocation for the service.
#
#   PSQL="psql -h localhost -U postgres" ./scripts/reset-db.sh
set -euo pipefail

DB_NAME="${DEV_DB_NAME:-sports_coach_bookings_e2e}"
PSQL="${PSQL:-docker exec -i scb-postgres psql -U postgres}"
BACKEND="$(cd "$(dirname "$0")/../../backend" && pwd)"

$PSQL -v ON_ERROR_STOP=1 -q <<SQL
DROP DATABASE IF EXISTS ${DB_NAME} WITH (FORCE);
CREATE DATABASE ${DB_NAME} OWNER scb_app;
SQL

cd "$BACKEND"
export MIX_ENV=dev DEV_DB_NAME="$DB_NAME"
mix ecto.migrate
mix run priv/repo/seeds.exs
