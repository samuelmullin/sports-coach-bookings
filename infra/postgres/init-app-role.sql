-- Local dev parity: create the non-superuser application role and databases.
-- Run automatically by the postgres image on first boot (mounted into
-- /docker-entrypoint-initdb.d). Mirrors the setup step in .github/workflows/ci.yml
-- and docs/conventions.md §1.4.
--
-- NEVER use this password outside local development.

CREATE ROLE scb_app LOGIN PASSWORD 'scb_app' NOSUPERUSER NOBYPASSRLS CREATEDB;

CREATE DATABASE sports_coach_bookings_dev OWNER scb_app;
CREATE DATABASE sports_coach_bookings_test OWNER scb_app;
