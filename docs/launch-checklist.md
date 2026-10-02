# Production launch checklist

Everything here needs a human decision, a credential, or access to an external
account, so none of it can be done from the repository. Each item says where the
placeholder or setting lives. `docs/ops.md` has the commands; this is the list to
tick off. Do staging first, then production.

## 1. Accounts and names

- [ ] **Fly apps.** Pick real names and replace `sportscoachbookings-prod` /
      `sportscoachbookings-staging` in `fly.toml` and `fly.staging.toml`, and every
      `<<PLACEHOLDER>>-prod` / `-staging` in `docs/ops.md` (§1, §3, §5, §6, §10).
- [ ] **Domain and DNS.** Apex + wildcard (`*.sportscoachbookings.com`) pointing at
      Fly, with certificates (`fly certs add …`). Set `PHX_HOST`, `BASE_DOMAIN`,
      `PLATFORM_HOST` to match. Tenancy is host-based, so the wildcard is required.
- [ ] **`APP_URL`** (secret): the platform base URL used in staff email links
      (`https://<apex>`); customer links use `<slug>.<BASE_DOMAIN>` automatically.
- [ ] **Contacts.** Fill `docs/security-review.md` §9: security lead / on-call and the
      **PIPEDA privacy officer** (the person who answers access and deletion
      requests, which the app now supports; see `SportsCoachBookings.Privacy`).

## 2. Storage (Canadian region; players are minors)

- [ ] **Public assets bucket** (`S3_BUCKET`, `S3_REGION=ca-central-1`, keys,
      `S3_PUBLIC_BASE_URL`). Public read for branding assets only.
- [ ] **Private bucket** for signed waivers (`S3_PRIVATE_BUCKET`). **Never public.**
      Waiver PDFs hold a minor's name and the signer's IP address. Without this
      variable they share the public bucket's `<tenant_id>/waivers/` prefix.
- [ ] **Validate against your real bucket in staging.** `Tenancy.Storage.S3` and
      `Waivers.PdfStore.S3` were verified live against a local RustFS (PDF
      put/get/delete, presigned upload), but not against your provider. Upload a
      logo; sign a waiver, download the PDF, erase a household and confirm the
      object is deleted.

## 3. Secrets (`fly secrets import`; full table in `docs/ops.md` §2)

- [ ] `SECRET_KEY_BASE`, `DATABASE_URL` (non-superuser `scb_app`; RLS is bypassed by
      superusers), `PLAYER_MEDICAL_ENCRYPTION_KEY` (back it up; losing it makes all
      medical data unreadable).
- [ ] Stripe **live** keys + `STRIPE_WEBHOOK_SECRET`; register the webhook URL
      `https://<host>/webhooks/stripe`. Staging uses test keys.
      Without `STRIPE_SECRET_KEY`, *dev* falls back to the in-memory fake provider; production must set it.
- [ ] Resend: `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, verified sending domain
      (`NOTIFICATIONS_FROM_ADDRESS`).
- [ ] `RATE_LIMIT_BACKEND` is `postgres` by default (shared across machines); leave it.

## 4. Observability and alerts

- [ ] **Error reporting.** Write or choose an adapter exporting
      `capture_exception/4` and set `ERROR_REPORTER_MODULE` (`docs/ops.md` §7;
      `SportsCoachBookings.Ops.ErrorReporter`). Until then errors are log-only.
- [ ] Create the uptime check on `/api/health` and the alerts in `docs/ops.md` §7.
- [ ] Route alerts somewhere a human will see them (on-call channel from item 1).

## 5. Backups and recovery

- [ ] Confirm Fly Postgres point-in-time recovery is enabled and retained as planned.
- [ ] **Run the restore drill** (`docs/ops.md` §5) into a new database and record
      the date, operator, observed RPO/RTO in the *Drill log* line.
- [ ] Decide the schedule for the logical backup (defence in depth).

## 6. Legal and policy decisions the code now needs

- [ ] **Retention.** Erasure keeps orders/payments/refunds and the credit ledger
      (no personal details, opaque ids) and anonymizes waiver signatures. Confirm
      the retention period for financial records with your accountant.
- [ ] **Response procedure** for access/deletion requests that arrive by email
      (who, how fast; PIPEDA expects a response within 30 days).
- [ ] Review `docs/security-review.md` §4 accepted risks (CSRF approach, email
      enumeration on signup, rate limiter fixed windows) before go-live.

## 7. Final verification

- [ ] CI green on the release commit (backend, frontend, **Browser E2E**).
- [ ] Staging smoke test: register, confirm email, buy a pack (Stripe test card),
      book, sign a waiver, cancel, coach attendance + feedback.
- [ ] Tag `v*` to deploy production (`.github/workflows/deploy.yml`).
