# WP-05 — Notifications Engine

**Phase:** 1 · **Hard deps:** wp-00 · **Soft deps:** wp-01 (branding schema per ERD; stub `branding_for_email/1` until merged)

## Goal
A single, reliable way for every context to send branded email, with delivery tracking, preferences, and suppression. (Email only in MVP; design for SMS/push later.)

## You own
`App.Notifications` (excluding `Broadcasts`, which is wp-17), email layout templates, `webhooks/resend`. Migrations prefixed `notifications_`.

## Public API
```elixir
Notifications.deliver(template_key, recipients, assigns, opts \\ [])
# recipients: [%{type: :customer_user | :staff_user | :email, id: _, email: _}]
# opts: category: :transactional | :operational | :marketing (default :transactional),
#       attachments: [...], idempotency_key: string, send_at: DateTime
```
- Inserts `messages` + one `deliveries` row per recipient and enqueues Oban jobs (`notifications` queue, concurrency tuned to Resend rate limit).
- `idempotency_key` is unique per tenant — same key twice is a no-op.
- Template registry: `App.Notifications.Templates.<Key>` modules implementing `subject/1`, `html/1`, `text/1`, `required_assigns/0`. Other WPs add template modules in their own directories and register them (registry is config-driven so there are no merge conflicts).

## Layout & branding
- One responsive HTML email layout (HEEx; inline CSS at build time via a premailer step) with tenant logo, primary color, footer text, social links, unsubscribe link (for non-transactional), physical address/contact (CASL).
- Plain-text alternative always generated.
- From: `"{Tenant Name}" <notifications@mail.yourapp.com>`; Reply-To: tenant contact email. (Tenant-verified sending domains are post-MVP.)

## Delivery tracking
- Resend webhook (`POST /webhooks/resend`, verify svix signature): `email.delivered`, `email.bounced`, `email.complained` → update `deliveries.status`.
- Hard bounce / complaint → add to `suppressions` (tenant, email). Suppressed addresses are skipped (status `suppressed`) except for password reset.

## Preferences
- `notification_preferences` per customer user / staff user: `marketing_opt_in` (default false — CASL requires express consent), `operational` always on, `transactional` always on.
- Signed one-click unsubscribe token (List-Unsubscribe + List-Unsubscribe-Post headers).
- `Notifications.Preferences` API for wp-02's account settings.

## Admin endpoints
- Delivery log per customer/household (last 90 days): template, subject, status, timestamps. Resend a failed/bounced delivery (except suppressed).

## Dev tooling
- `/dev/mailbox` (Swoosh local) and `/dev/emails/:template_key` preview rendering with fake assigns for each registered template.

## Acceptance criteria
- A test template renders with two different tenants' branding correctly.
- Idempotency, suppression, and preference rules tested.
- Resend webhook replay safe. Job retries with backoff; permanent failures marked `failed`.

## Out of scope
Specific event emails (wp-16), auth emails content (wp-01/wp-02 own their templates), broadcasts (wp-17), SMS.
