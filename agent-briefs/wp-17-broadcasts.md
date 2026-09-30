# WP-17 — Broadcast Messaging to Customers

**Phase:** 3 (can start in Phase 2) · **Hard deps:** wp-05, wp-11 · **Soft deps:** wp-14

## Goal
Owners/admins email groups of customers: e.g. "everyone booked Saturday at Ravenscrag Field — rain delay", or "new fall packages".

## You own
`App.Notifications.Broadcasts`, controllers `staff/broadcasts/`. Migrations prefixed `broadcasts_`.

## Schemas
- **broadcasts**: `subject`, `body_markdown`, `category` (`operational|marketing`), `segment` (embedded definition), `status` (`draft|scheduled|sending|sent|cancelled`), `scheduled_for`, `sent_at`, `created_by`, `recipient_count`, `stats` (delivered/bounced counts).

## Segments (embedded, composable with AND)
- All households
- Households with a confirmed booking in: session(s) / offering(s) / venue / date range
- Households with players in age range
- Households with credits balance > 0 / expiring before date
- Households who purchased package X
Resolve to a de-duplicated list of manager emails via other contexts' public query functions (add small query functions to those contexts by RFC if missing — don't query their tables directly).

## Rules
- `marketing` respects opt-in (CASL): only recipients with `marketing_opt_in`. `operational` goes to everyone in the segment but the UI requires the segment to be booking-based (you can't send "operational" to all households).
- Preview: rendered HTML + recipient count + first 20 recipients. Send test to self.
- Sending uses `Notifications.deliver/4` in Oban batches of 100 with idempotency per `(broadcast_id, recipient)`.
- Cancel a scheduled broadcast before it starts.
- Markdown rendered with a safe subset (no raw HTML).

## Acceptance criteria
- Segment resolution tests for each segment type and combinations.
- Marketing broadcast excludes non-opted-in and suppressed addresses.
- Re-running a partially failed send doesn't double-send.
- Isolation + policy tests (coaches cannot broadcast).

## Out of scope
SMS, rich editor beyond markdown, A/B tests, open/click tracking.
