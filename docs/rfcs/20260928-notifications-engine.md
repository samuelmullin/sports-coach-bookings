# RFC 20260928 — Notifications engine (wp-05)

**Owner:** wp-05 (Notifications). **Status:** implemented.

## Context

wp-05 owns the email engine, template registry, delivery tracking, preferences,
and suppression. The ERD (`docs/erd.md`) pins `messages`, `deliveries`,
`suppressions`, and `notification_preferences`. Two implementation needs are not
expressed there and one platform table is added.

## Decisions

1. **Template registry is config-driven.** Templates implement
   `SportsCoachBookings.Notifications.Template` and are registered in
   `config :sports_coach_bookings, :notification_templates` (key → module). A
   context adds its own template module and config entry without editing a
   shared registry file. The sample template and the WP-01/WP-02 seam templates
   are registered here; wp-16 replaces/adds event templates the same way.

2. **`messages.assigns` (jsonb).** The brief stores only `subject` on
   `messages`, but the worker must render the body and an admin "resend" must
   re-render it without the original request. Template assigns are therefore
   persisted on `messages`. They can contain action links (including tokens);
   this is a deliberate trade-off documented here. Actionable tokens remain
   single-use/expiring at their owning context.

3. **`notifications_delivery_refs` (platform, added).** Webhooks arrive with no
   tenant context, and RLS blocks reading tenant-owned `deliveries` before a
   tenant is known (the app role is not `BYPASSRLS`). When a send is accepted we
   record `provider_ref → (tenant_id, delivery_id)` in this platform table. The
   webhook resolves the tenant from it, then runs the state change in tenant
   context.

4. **`notifications_webhook_events` (platform, added).** A durable record of
   provider events with a unique `(provider, event_id)` index. This makes
   webhook replays a no-op (invariant 6). wp-04's generic `webhook_events` table
   is not merged; if it lands, this table can be folded into it.

5. **Svix signature verification.** `Notifications.Signature` HMACs
   `"<svix-id>.<svix-timestamp>.<raw-body>"` with the base64-decoded
   `whsec_…` secret and compares against each `v1,<sig>` value in
   `svix-signature`, constant-time. The secret is `:resend_webhook_secret`
   (runtime env `RESEND_WEBHOOK_SECRET`). `Plug.Parsers` uses
   `CachedBodyReader` to retain the raw body.

6. **No premailer dependency.** The layout authors inline `style="…"` and uses a
   `<style>` block only for the responsive media query, so no external CSS
   inliner is required. CASL physical address comes from
   `branding.email_footer_text` plus the tenant contact email; there is no
   dedicated address column.

7. **Suppression exemption.** Password-reset templates declare
   `exempt_from_suppression?/0` (via `use … Template, exempt: true`). All other
   mail to a suppressed address is recorded with status `suppressed` and not
   enqueued.

8. **Preferences are polymorphic.** `notification_preferences` uses
   `subject_type`/`subject_id` (resolves ERD ambiguity 14), so wp-05 never
   touches another context's schema. `Notifications.Preferences.get/1` and
   `update/2` accept `%CustomerUser{}`, `%StaffUser{}`, `%{type, id}`, or
   `{type, id}` and manage their own tenant transaction. wp-02's
   `Customers.Preferences` seam is wired via
   `:customer_preferences_module`.

## Stubs / no external services

- No Resend API key: dev/test use `Swoosh.Adapters.Local`/`Test`; prod wires
  `Swoosh.Adapters.Resend` in `runtime.exs` only when `RESEND_API_KEY` is set.
- `Notifications.Deliverer` is injectable so tests can force send failures
  without a real provider.
- No S3; branding asset URLs still come from the existing Tenancy storage stub.

## Not changed

- No other context, `core/*`, or `docs/erd.md` edited. Endpoint and router gain
  the minimal hooks needed for raw-body capture and the new routes.
