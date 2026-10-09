# SportsCoachBookings — Operations Runbook

Owner: wp-20. This is the single source of truth for deploying, operating, and
recovering SportsCoachBookings. It complements `docs/conventions.md` (how the code
is structured) and `docs/decisions/20260928-hosting-region.md` (why `yyz`).

> **Placeholders** are marked `<<PLACEHOLDER>>`. Before the first deploy the human
> must create the Fly apps, the Canadian Postgres + bucket, the DNS records, and
> the Resend/Stripe resources, then fill these in. See
> [§12 Placeholders](#12-placeholders-to-fill-in).

---

## 1. Environments

| Env | App | Host | Region | Trigger | Data |
|---|---|---|---|---|---|
| local | `docker compose` / `mix` | `localhost` | — | manual | ephemeral |
| CI | GitHub Actions | — | `ubuntu-latest` | push/PR | ephemeral |
| staging | `<<PLACEHOLDER>>-staging` | `staging.sportscoachbookings.com` | `yyz` | CI green on `main` | seeded `demo` tenant |
| production | `<<PLACEHOLDER>>-prod` | `sportscoachbookings.com` | `yyz` | tag `v*` | real tenant data |

All non-local environments run in **Canada** (`yyz` + `ca-central-1` bucket).

---

## 2. Required runtime secrets

Set with `fly secrets set KEY=value --app <app>` (or `fly secrets import`). The
release **refuses to boot** without the required ones.

| Variable | Required | Purpose |
|---|---|---|
| `SECRET_KEY_BASE` | **yes** | Sign cookies/sessions (`mix phx.gen.secret`). |
| `DATABASE_URL` | **yes**\* | `ecto://scb_app:…@host/db`. Non-superuser role. |
| `PLAYER_MEDICAL_ENCRYPTION_KEY` | **yes** | Base64 32-byte Cloak key for medical data. |
| `PHX_HOST` | yes (env) | Public host used in generated URLs. |
| `BASE_DOMAIN` / `PLATFORM_HOST` | recommended | Tenant wildcard apex / signup host. |
| `POOL_SIZE` | no (10) | Repo connection pool size. |
| `ECTO_SSL` | no | `true` when managed Postgres requires TLS. |
| `RESEND_API_KEY` | email | Resend API key; without it mail uses the local adapter. |
| `RESEND_WEBHOOK_SECRET` | email | Svix signing secret for `/webhooks/resend`. |
| `NOTIFICATIONS_FROM_ADDRESS` | no | `From:` address. |
| `APP_URL` | no | Base URL in emails. |
| `STRIPE_SECRET_KEY` | payments | Stripe platform secret key. |
| `STRIPE_WEBHOOK_SECRET` | payments | Signing secret for `/webhooks/stripe`. |
| `STRIPE_ACCOUNT_TYPE` | no (`express`) | Connect account type. |
| `STRIPE_PLATFORM_FEE_BPS` | no (`0`) | Platform fee in basis points. |
| `S3_BUCKET` | uploads | Enables the real S3 backend; unset ⇒ local Fake. |
| `S3_REGION` | uploads | `ca-central-1` (Canadian bucket). |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | uploads | Bucket credentials. |
| `S3_ENDPOINT` / `S3_FORCE_PATH_STYLE` | no | Set for RustFS/MinIO/R2; AWS uses virtual-hosted style. |
| `S3_PUBLIC_BASE_URL` | no | CDN/base URL for reads. |
| `S3_PRIVATE_BUCKET` | recommended | Private bucket for signed-waiver PDFs (minors' names, signer IPs). Never expose publicly. Unset ⇒ shares `S3_BUCKET`; with no `S3_BUCKET` PDFs go to local disk and are lost on redeploy (re-rendered on demand). |
| `RATE_LIMIT_BACKEND` | no (`postgres`) | `ets` = per-node in-memory limits instead of the shared Postgres counters. |
| `ERROR_REPORTER_MODULE` | no | Module with `capture_exception/4` (e.g. Sentry adapter). |
| `ECTO_IPV6` / `DNS_CLUSTER_QUERY` | no | Multi-region clustering; unused while single-region. |

\* Or the discrete `PGHOST`/`PGUSER`/`PGPASSWORD`/`PGDATABASE`/`PGPORT`.

There is also a hard **role guard**: if the DB user is `postgres`/`rdsadmin`
(or missing) the app refuses to start, because a superuser bypasses RLS
(`docs/conventions.md` §1.4).

Local values live in `.env` (gitignored); see `.env.example`.

---

## 3. First-time setup

1. **Fly apps**
   ```bash
   fly apps create <<PLACEHOLDER>>-prod
   fly apps create <<PLACEHOLDER>>-staging
   ```
2. **Postgres** (managed, PITR, encrypted at rest, region `yyz`):
   ```bash
   fly postgres create --name scb-pg-prod --region yyz
   fly postgres attach scb-pg-prod --app <<PLACEHOLDER>>-prod
   ```
   The attach injects `DATABASE_URL`. **Verify the role is not superuser** and,
   if the managed role is `postgres`, create `scb_app` and point the secret at
   it (see `infra/postgres/init-app-role.sql` for the grants to mirror).
3. **Object storage**: create a private bucket in `ca-central-1` (or a `yyz`
   Tigris bucket) and set `S3_*` secrets. Block public access; reads go through
   `S3_PUBLIC_BASE_URL` or signed URLs only.
4. **Secrets**: `fly secrets import --app <<PLACEHOLDER>>-prod < .env.production`.
5. **TLS / DNS** (`*.sportscoachbookings.com`):
   ```bash
   fly certs add "sportscoachbookings.com" --app <<PLACEHOLDER>>-prod
   fly certs add "*.sportscoachbookings.com" --app <<PLACEHOLDER>>-prod
   ```
   Add the A/AAAA records Fly prints at your DNS provider. Wildcard certs use
   DNS-01 validation, so a `_acme-challenge` TXT/CNAME record is required.
   Apex (`sportscoachbookings.com`), `app.` (optional alias) and `mail.` records
   per the Resend setup below.
6. **Email (Resend)**: add `mail.sportscoachbookings.com` as a sending domain,
   publish the SPF, DKIM and DMARC (`p=quarantine`) records Resend generates,
   warm up the domain, then set `RESEND_API_KEY` and create the webhook pointing
   at `https://<host>/webhooks/resend` with `RESEND_WEBHOOK_SECRET`.
7. **Stripe**: configure the Connect platform, set `STRIPE_ACCOUNT_TYPE`, and
   register webhook endpoints `…/webhooks/stripe` for **test mode (staging)** and
   **live mode (production)**; store each signing secret as
   `STRIPE_WEBHOOK_SECRET` in the matching environment.
8. **CI secrets**: `FLY_API_TOKEN_STAGING`, `FLY_API_TOKEN` (see `.github/workflows/deploy.yml`).
   Protect the `staging` and `production` GitHub environments.
9. **Alerts**: create the uptime check and metric alerts in §7.

---

### 3.1 Commission a tenant custom domain (MVP)

Custom domains are support-managed. Do this in staging first.

1. Ask the customer for the exact hostname (prefer `www.example.com`) and have
   them publish a temporary TXT ownership record supplied by the operator.
2. Verify that TXT record, then provision the hostname certificate on the Fly
   app with `fly certs add <hostname> --app <app>`. Give the customer the CNAME
   or A/AAAA records printed by Fly; do not ask them to switch traffic yet.
3. Insert the lower-case hostname into `tenant_domains` for the intended tenant.
   Keep the platform subdomain as the primary/fallback mapping. This is a
   platform operation and must not be exposed as a tenant-supplied ID write.
4. Before DNS cutover, test with an explicit `Host` header that `/`,
   `/api/portal/website`, `/robots.txt`, `/sitemap.xml`, login, schedule, and
   checkout all resolve to the right tenant. Confirm another tenant's content
   cannot be returned through the new host.
5. Wait until `fly certs show <hostname> --app <app>` reports ready, then have
   the customer switch DNS. Re-run the checks over HTTPS and retain their old
   site until DNS TTLs expire.
6. Record the tenant, hostname, verifier, certificate state, cutover time, and
   rollback DNS target in the launch log. Certificate and DNS monitoring are a
   human responsibility until lifecycle automation is implemented.

Rollback is recoverable: point DNS back to the old host and remove the mapping
only after traffic has drained. Do not delete the tenant or published content.

## 4. Deploy

### Staging (automatic)
`push` to `main` → CI runs → when the CI **workflow run completes successfully**,
`.github/workflows/deploy.yml` builds the image, pushes to GHCR, and
`flyctl deploy`s staging. Watch in the Actions tab.

### Production (tag)
```bash
git tag v0.1.0 && git push origin v0.1.0
```
CI runs for the tag (`ci.yml` triggers on `v*`), and when it succeeds the
production job builds/pushes `:v0.1.0` and deploys. It is gated by the protected
`production` environment (require a reviewer).

Both deploy jobs are triggered by the **`workflow_run` completion of CI** and
check `conclusion == 'success'`, so a red CI build never deploys. Manual
fallback (bypasses the CI gate): `workflow_dispatch` with
`environment` = staging|production and a `ref`.

### Manual / rollback-to-image
```bash
fly deploy --config fly.toml --image ghcr.io/<owner>/<repo>:v0.1.0
```

### What happens
`fly.toml` sets `release_command = "/app/bin/migrate"`, so Fly runs migrations in
a one-off machine from the new image **before** shifting traffic. Health checks
(`/health`, `/health/ready`) must pass before a machine is taken into rotation,
giving rolling/zero-downtime deploys (`min_machines_running = 2` in prod).

### Manual migration
```bash
fly ssh console --app <<PLACEHOLDER>>-prod -C "/app/bin/migrate"
```

---

## 5. Rollback

**Prefer rolling forward**: a bad code change can be reverted by deploying the
previous image; if the change was a migration, roll forward with a corrective
migration rather than down-migrating.

1. **Code only** — redeploy the last good image:
   ```bash
   fly releases --app <<PLACEHOLDER>>-prod            # find the previous version
   fly deploy --config fly.toml --image ghcr.io/<owner>/<repo>:<last-good-tag>
   ```
2. **Schema involved** — roll a migration back inside the release (only if the
   migration is safely reversible):
   ```bash
   fly ssh console --app <<PLACEHOLDER>>-prod -C \
     "/app/bin/sports_coach_bookings eval \"SportsCoachBookings.Release.rollback(SportsCoachBookings.Repo, 20260928000000)\""
   ```
   Then deploy the previous image. **Never** down-migrate a data migration that
   dropped/transformed data without a verified backup.
3. After any rollback, confirm `/health/ready` is green and check the Oban
   dashboard/queue for failed jobs.

---

## 6. Backup & restore (drill completed once)

Fly Managed Postgres takes continuous backups with PITR (encrypted at rest). To
satisfy the acceptance criterion, run the drill below **once** and record the
date/result here.

### Restore drill (staging, monthly)
```bash
# 1. Pick a target time (PITR) — e.g. 10 minutes ago.
# 2. Restore into a NEW database (never overwrite the primary):
fly postgres db list --app scb-pg-staging
fly postgres connect --app scb-pg-staging    # psql
#   SELECT pg_dump ... or use Fly's restore flow for a new cluster.
# 3. Point a throwaway app/machine at the restored DB and run:
/app/bin/migrate
# 4. Smoke test: login as the demo tenant, load a schedule, send a test email.
# 5. Record: date, operator, target time, observed RPO/RTO, result.
```

Drill log: `<<PLACEHOLDER: date — operator — result>>`.

### Logical backup (defence in depth)
```bash
pg_dump "$DATABASE_URL" --format=custom --file=scb-$(date +%F).dump
pg_restore --clean --if-exists --no-owner -d "$RESTORE_URL" scb-$(date +%F).dump
```
Object storage is versioned at the bucket level; enable versioning + lifecycle
rules on creation.

---

## 7. Observability & alerts

- **Logs**: production emits one JSON object per line (`time`, `level`,
  `message`, `request_id`, `tenant_id`, `mfa`, Oban fields). Pipe the Fly log
  drain to your provider; `tenant_id`/`request_id` are indexed fields.
- **Health**: `/health` (liveness) and `/health/ready` (DB). Fly checks both.
- **Error reporting**: `Ops.ErrorReporter` attaches to router exceptions and
  Oban failures and logs structured errors. Set `ERROR_REPORTER_MODULE` to a
  module exporting `capture_exception/4` (write a thin Sentry/AppSignal adapter)
  to forward them. Default is log-only.
- **LiveDashboard**: `/dev/dashboard` is compiled out of production
  (`dev_routes` is dev-only). To use it in prod, enable it behind platform-admin
  auth as a follow-up; do not expose it publicly.
- **Oban**: monitor queues via the Oban UI/metadata; alert on
  `oban.job.exception` count and on `discarded`/`retryable` growth.
- **Database metrics**: Fly Managed Postgres exposes CPU/memory/storage. Alert on
  >80% CPU, >80% storage, and replica lag (when added).

### Alerts to create (acceptance)
| Alert | Source | Threshold |
|---|---|---|
| 5xx rate | log drain / proxy | >1% over 5 min |
| Oban failures | `oban.job.exception` | any `discarded`, or >5/min |
| Webhook failures | `/webhooks/*` 4xx/5xx | any sustained 5xx |
| DB CPU / storage | managed Postgres | CPU >80%, storage >80% |
| Uptime | external check on `/health` | 2 consecutive failures |

---

## 8. Secrets management & Cloak key rotation

- All secrets are env-based (`fly secrets`), injected at boot; none are committed.
- Rotate on a schedule and immediately on suspected exposure. `fly secrets set`
  triggers a rolling restart.
- **Cloak (`PLAYER_MEDICAL_ENCRYPTION_KEY`)** — the vault reads this at boot.
  Rotation uses Cloak's labelled-cipher migration:
  1. Generate a new key: `mix run -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'`.
  2. Add the new cipher as the active one and keep the old cipher for decryption
     (see `docs/rfcs/20260928-players-medical-encryption.md`, `Players.Vault`).
  3. Run `mix cloak.migrate` to re-encrypt.
  4. Remove the old cipher and destroy the old key once migration + verification
     complete. **Never** rotate by deleting the only key: encrypted medical data
     would be unrecoverable.
- **`SECRET_KEY_BASE`** rotation invalidates existing sessions/cookies (users
  re-login). Acceptable; announce beforehand.

---

## 9. Scaling

- **Web**: increase machine count / size (`fly scale count 4`, `fly scale vm shared-cpu-2x`).
  The app is stateless; scale horizontally. Keep `POOL_SIZE × machines ≤` the
  Postgres connection limit.
- **Workers**: Oban runs in the web process by default. For heavy loads, split a
  worker-only process group and disable the HTTP server there. All Oban queues are
  already configured in `config/config.exs`.
- **Postgres**: scale the managed cluster vertically first; add a read replica only
  if the replica can stay in Canada.
- **Postgres connections**: raise `POOL_SIZE` before adding machines; watch the
  `queue_time` metric.

---

## 10. Demo / staging environment

Stand up a usable demo tenant (the seeds create the `demo` tenant with catalog,
schedule, customers, etc.):

```bash
# Against staging, inside the release image:
fly ssh console --app <<PLACEHOLDER>>-staging -C "/app/bin/seed"
```

Locally:
```bash
docker compose up -d postgres rustfs rustfs-init
cd backend && mix setup          # create/migrate + seeds + assets
mix phx.server
# demo tenant at http://demo.localhost:4000  (admin at /admin)
```

Seeds are **idempotent** (`Repo.get_by(Tenant, slug: "demo")`). Never run
`/app/bin/seed` against production.

---

## 11. Security / safety notes & common runbooks

- **Never** point the app at a superuser DB role; the boot guard enforces this.
- **Disable a tenant**: set its status so `ResolveTenant` returns `404` for its
  hosts (owned by wp-01; do it via the platform tooling or a reviewed `UPDATE`).
- **Replay failed webhooks**: webhook events are stored (`webhook_events`) and
  processing is idempotent (invariant 6). Re-send from Stripe/Resend's dashboard,
  or re-enqueue the stored event; do not hand-edit payment/credit rows.
- **Re-send an email**: use the staff notifications endpoint
  `POST /api/staff/notifications/deliveries/:id/resend`, or Resend's dashboard.
- **Stuck Oban jobs**: inspect, then retry/discard from the Oban UI; jobs are
  idempotent, so retrying is safe.
- **Medical data**: field-level encrypted; reads are audited. Never dump decrypted
  medical fields to logs or tickets.

---

## 12. Placeholders to fill in

| Placeholder | Where | Notes |
|---|---|---|
| `<<PLACEHOLDER>>-prod` / `-staging` Fly app names | `fly.toml`, `fly.staging.toml` | `fly apps create`. |
| `sportscoachbookings.com` apex | `fly*.toml`, `config/prod.exs`, notifications | Stub domain; replace if it changes. |
| S3 bucket names + credentials | `.env`, Fly secrets | Canadian region, private. |
| Resend domain + key/webhook secret | Fly secrets | `mail.sportscoachbookings.com`. |
| Stripe keys + webhook secrets | Fly secrets | Test (staging) and live (prod). |
| `FLY_API_TOKEN(_STAGING)` | GitHub repo secrets | For `deploy.yml`. |
| Error reporter adapter module | `ERROR_REPORTER_MODULE` | e.g. a Sentry adapter. |
| Backup restore drill log | §6 | Record once completed. |
| Production S3 upload round-trip verification | staging | CI verifies both buckets against RustFS; staging must verify the chosen provider and policies. |
