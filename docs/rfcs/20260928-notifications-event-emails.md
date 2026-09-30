# RFC 20260928 — Event-driven transactional emails (wp-16)

**Owner:** wp-16 (Notifications.Templates.*, Notifications.Subscribers.*).
**Status:** implemented. **Depends on:** wp-05, and the event payloads from
wp-01/02/07/08/11/12/13/14/15.

## Context

wp-16 turns the shared domain-event catalog (`00-shared-context.md`) into branded
transactional email. It adds `Notifications.Templates.*` modules, registers them
in `:notification_templates`, and maps each event to recipients/assigns in
`SportsCoachBookings.Notifications.Subscribers.EventSubscriber`, registered in
`:event_subscribers`. It owns no schemas and no endpoints, so there is no new
tenant-isolation or OpenAPI surface.

## Event → recipient → template mapping

| Event | Template | Category | Recipients |
|---|---|---|---|
| `booking.created` (confirmed only) | `booking_confirmed` | transactional | household managers |
| `booking.cancelled` | `booking_cancelled` | transactional | household managers |
| `booking.rebooked` | `booking_rebooked` | operational | household managers |
| `booking.attended` | `booking_attended` | transactional | household managers |
| `booking.no_show` | `booking_no_show` | operational | household managers |
| `session.cancelled` | `session_cancelled_by_provider` | operational | affected households + assigned coaches |
| `session.rescheduled` | `session_rescheduled` | operational | affected households + assigned coaches |
| `order.paid` | `order_receipt` (+ `booking_confirmed` per held drop-in line) | transactional | household managers |
| `order.refunded` | `order_refunded` | transactional | household managers |
| `order.expired` | `order_expired` | operational | household managers |
| `credits.granted` | `credits_granted` | transactional | household managers |
| `credits.expiring_soon` | `credits_expiring` | operational | household managers |
| `credits.expired` | `credits_expired` | operational | household managers |
| `waiver.published` (require_resign) | `waiver_resign_required` | transactional | households with unsigned players |
| `waiver.signed` | `waiver_signed` | transactional | household managers |
| `feedback.submitted` (shared) | `feedback_shared` | transactional | household managers |
| `customer.registered` | `customer_welcome` | transactional | the new customer |
| `household.member_joined` | `household_member_joined` | operational | existing household managers |
| `staff.joined` / `staff.removed` | `staff_joined` / `staff_removed` | operational | owners/admins |
| `stock.low` | `admin_low_stock` | operational | owners/admins |

## Decisions

1. **Auth/invite emails are not duplicated.** `staff.invited`,
   `household.member_invited`, confirmation, and reset emails are owned by
   WP-01/WP-02 and sent directly by their notifiers. WP-16 deliberately does
   **not** subscribe to `staff.invited` or `household.member_invited`; doing so
   would send the invitation twice (acceptance: "no event is double-emailed").

2. **Idempotency keys.** Every send uses a stable key. Booking confirmation uses
   `booking_confirmed:<booking_id>` for both triggers (`booking.created` and
   `order.paid` hold confirmation) so a booking is confirmed by email exactly
   once. Other sends use `"<event>:<entity_id>:<template>"` (credits/waivers add
   the lot/version id), matching the brief. Reminder/job-style events are not
   part of the catalog yet (see below).

3. **No cross-context `Repo`.** Recipients and assigns are resolved only through
   public context APIs: `Customers.list_manager_emails/1`,
   `Customers.list_households/1`, `Staff.list_team/0`,
   `Scheduling.session_detail/1`, `Bookings.fetch_booking/1` +
   `Bookings.list_for_household/1`, `Commerce.fetch_order/1`,
   `Waivers.status_for_household/1`, `Credits.balance/1`,
   `Players.fetch_player/1`, `Feedback.fetch_feedback/1`,
   `Inventory.fetch_variant/1`/`fetch_product/1`, `Tenancy.get_tenant/1`.

4. **Graceful degradation.** If a lookup returns `not_found` or a value the
   assigning template cannot use, the handler returns `:ok` without sending
   rather than failing the event. Events are at-least-once; a transient DB error
   still surfaces as `{:error, reason}` for Oban retry.

5. **`.ics`.** `Notifications.Ics` emits RFC 5545 with the venue `TZID`, a
   stable `UID` per booking, and `SEQUENCE` = `rebook_count`. Tests validate the
   output with a minimal parser/unfolder. A manual open in Google/Apple Calendar
   is not possible in this environment and is noted for the PR reviewer.

## Payload gaps (RFC requests, degraded gracefully)

The following are implemented via public reads because the event payloads do not
carry enough data. A future wp-11/wp-14 change could add the ids to the payloads
to avoid the O(households) scan; until then wp-16 composes public APIs:

- `session.cancelled` / `session.rescheduled` do not carry affected household
  ids. WP-16 iterates `Customers.list_households/0` and
  `Bookings.list_for_household/1`. A public
  `Bookings.household_ids_for_session/1` would be the clean fix (RFC to wp-14).
- `waiver.published` does not carry affected player/household ids. WP-16 scans
  households and calls `Waivers.status_for_household/1` (RFC to wp-07/wp-06).
- `order.paid` does not carry the tenant tax number. The tenant has no tax-number
  column, so `order_receipt` omits it (RFC to wp-03/wp-01 if required).

## Out of scope / not in the event catalog

The brief also lists `session_reminder`, `coach_daily_digest`, and
`merch_ready_for_pickup`. These are scheduled jobs or fulfillment-state changes,
not catalog events; the catalog would need new events via RFC
(`session.reminder_due`, `coach.daily_digest`, `fulfillment.ready_for_pickup`)
before subscribers can be attached. They are intentionally not implemented here.

## Not changed

No other context, `core/*`, `docs/erd.md`, or `docs/conventions.md` edited. No
new schemas or endpoints; `docs/openapi.json` is unchanged.
