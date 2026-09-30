# WP-18 — End-to-End Test Suite

**Phase:** 3 · **Hard deps:** all backend WPs + fe-01/02/03

## Goal
Playwright tests that prove the golden paths work through the real UI and API, with a Fake payment provider in CI and Stripe test mode in a nightly run.

## You own
`e2e/` (Playwright project), seed scenario scripts `backend/priv/repo/scenarios/*.exs`, CI job config for e2e.

## Setup
- `mix app.e2e.reset` truncates and seeds a named scenario. Tests call a guarded `/test-only/scenario/:name` endpoint (compiled only in `:e2e` env).
- Wildcard host resolution for `*.localhost` in CI.
- `PAYMENT_PROVIDER=fake` in CI: fake hosted checkout page that posts a signed fake webhook. Nightly job uses Stripe test mode + `stripe listen`.
- Email assertions via the Swoosh test mailbox API.

## Scenarios
1. **Tenant onboarding:** sign up → set branding → connect payments (fake) → create venue, offering, package → publish sessions → publish waiver.
2. **Staff:** invite admin + coach; coach sees only coach nav.
3. **Customer first purchase:** register → confirm email → add player (minor) with emergency contact + medical → sign waiver → buy package with discount code → receipt email → credits balance shown.
4. **Book with credits:** filter calendar by age → book → confirmation email with `.ics` → credits decremented.
5. **Cancel inside vs outside window:** preview shows correct outcome; credits returned or forfeited accordingly.
6. **Rebook:** within limit succeeds; beyond `max_rebooks` blocked with message.
7. **Pay-per-session drop-in:** hold → checkout → paid → confirmed; abandoned checkout releases seat after expiry (time-travel helper).
8. **Waiver gate:** new version requiring re-sign blocks booking until signed.
9. **Coach flow:** coach views roster, opens player (medical access audited), marks attendance, shares feedback → household email.
10. **Merch:** buy product → admin marks ready → pickup email.
11. **Household co-manager:** invite second adult → they book for the same player.
12. **Provider cancels session:** all bookings cancelled, credits returned, emails sent.
13. **Isolation:** customer of tenant A cannot log in on B; direct API calls with A's IDs on B's host → 404.

## Acceptance criteria
- All scenarios pass 3 consecutive CI runs without flakes.
- Runtime < 10 min in CI (parallel workers per tenant).
