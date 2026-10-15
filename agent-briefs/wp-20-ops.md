# WP-20 — Operations & Deployment

**Phase:** 3 (can start any time after wp-00) · **Hard deps:** wp-00

## Goal
Staging and production environments in a Canadian region, with safe deploys, backups, monitoring, and all third-party wiring (DNS, email, Stripe).

## You own
`infra/`, `Dockerfile`, release config (`rel/`), deploy CI workflows, `docs/runbook.md`.

## Tasks
1. **Hosting:** Canadian region (e.g. Fly.io `yyz` or AWS `ca-central-1` — pick one and record it in `docs/decisions/`). Managed Postgres with PITR backups, encrypted at rest. S3-compatible bucket in-region (private).
2. **Release:** Elixir release in Docker, frontend built in the same image, migrations run as a release task before traffic shift, zero-downtime deploys, health/readiness endpoints.
3. **Wildcard TLS & DNS:** `*.yourapp.com` certificate (DNS-01), apex + `app.` + `mail.` records.
4. **Email:** Resend domain for `mail.yourapp.com` with SPF, DKIM, DMARC (`p=quarantine` after warm-up); webhook endpoint per environment.
5. **Stripe:** Connect platform settings, Connect webhook endpoints for staging (test mode) and prod (live), secrets per env.
6. **Secrets:** env-based secrets management; Cloak key rotation procedure documented.
7. **Observability:** error tracking (Sentry or AppSignal) with PII scrubbing, structured JSON logs with `tenant_id` + `request_id`, Phoenix LiveDashboard behind platform-admin auth, Oban monitoring (failed jobs alert), uptime check, DB metrics.
8. **Environments:** local (docker-compose Postgres + RustFS), CI, staging (seeded demo tenant), production. Staging auto-deploys from `main`; prod on tag.
9. **Runbook:** deploy/rollback, restore from backup (tested once), rotate keys, replay failed webhooks, re-send emails, disable a tenant.

## Acceptance criteria
- Staging live at `demo.staging.yourapp.com` with working email and Stripe test checkout.
- A documented backup restore drill completed.
- Alerts fire for: 5xx rate, Oban failures, webhook processing failures, DB CPU/storage.
