# WP-16 — Event-Driven Transactional Emails

**Phase:** 2 · **Hard deps:** wp-05 · **Soft deps:** wp-11, wp-12, wp-13, wp-14, wp-15, wp-07, wp-08 (event payloads per the shared catalog)

## Goal
Customers and staff get the right email for every meaningful event, branded per tenant, never duplicated.

## You own
`App.Notifications.Subscribers.*` and `App.Notifications.Templates.*` for the templates below; `.ics` generation. (Auth emails — confirmation, reset, staff invite, household invite — are owned by wp-01/wp-02.)

## Templates & triggers
| Template key | Trigger | Recipients | Notes |
|---|---|---|---|
| `booking_confirmed` | `booking.created` (confirmed) / `order.paid` hold confirm | Household managers | Session, venue (map link), coach, player, policy summary, `.ics` attachment, manage link |
| `booking_cancelled` | `booking.cancelled` | Household managers | Outcome (credits returned / refund amount / forfeited) |
| `booking_rebooked` | `booking.rebooked` | Household managers | Old → new, updated `.ics` (same UID, SEQUENCE+1) |
| `session_reminder` | Scheduled 24 h before start (tenant-configurable 2–72 h) | Household managers | Check booking still confirmed at send time; skip if not |
| `session_cancelled_by_provider` | `session.cancelled` | Affected households + assigned coaches | Credits/refund returned |
| `session_rescheduled` | `session.rescheduled` | Affected households + coaches | Free cancel/rebook link |
| `order_receipt` | `order.paid` | Purchaser + managers | Lines, discounts, tax, total, tenant tax number if set, pickup info for merch |
| `order_refunded` | `order.refunded` | Purchaser | |
| `credits_expiring` | `credits.expiring_soon` | Household managers | Remaining credits, expiry date, book-now link |
| `feedback_shared` | `feedback.submitted` | Household managers | Coach name, session date, feedback body, ratings |
| `waiver_resign_required` | `waiver.published` (re-sign) | Households with affected players | Prioritize households with upcoming bookings |
| `merch_ready_for_pickup` | fulfillment → `ready_for_pickup` | Purchaser | Venue + hours |
| `coach_daily_digest` | Scheduled, 6 AM tenant tz | Coaches with sessions that day | Sessions + rosters, flags for medical info present |
| `admin_low_stock` | `stock.low` | Owners/admins | |

## Rules
- Every send uses `idempotency_key = "#{event_name}:#{entity_id}:#{template}"` (reminders: include session id + booking id).
- Reminder jobs: Oban unique scheduled job per booking; on cancel/rebook, cancel the job; at run time re-check status anyway.
- `.ics`: valid RFC 5545, `TZID` of the venue, stable UID per booking.
- All links are absolute to the tenant's host.
- Preview fixtures for each template in the wp-05 preview route.

## Acceptance criteria
- For each trigger, a test asserts exactly one delivery per recipient, including under event replay.
- Reminder not sent for a booking cancelled after scheduling.
- `.ics` validated by a parser in tests; opens correctly in Google Calendar/Apple Calendar (manual check noted in PR).

## Out of scope
Engine/layout (wp-05), broadcasts (wp-17), SMS.
