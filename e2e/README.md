# Browser end-to-end tests

Playwright journeys that drive the real React SPAs against a real Phoenix server
and Postgres. The backend's `test/e2e` suite exercises Phoenix directly and the
frontend unit tests use MSW; this suite is what proves the pieces work together.

| Journey | Covers |
|---|---|
| `01-customer-onboarding` | Register, email confirmation link, add a player (5-step wizard), sign waivers, download the signed PDF |
| `02-purchase` | Package → cart (tax) → checkout hand-off → provider webhook → order paid → sessions granted |
| `03-booking-and-waiver-gate` | Book with purchased sessions; unsigned waivers block the booking (UI **and** server) |
| `04-cancellation-and-rebooking` | Cancel returns the session; keeping a booking changes nothing |
| `05-coach-workflow` | Roster, attendance, share feedback, family reads it; coach access limits |
| `06-club-signup` | Create a club (tenant), owner confirmation email, the club's own host |
| `07-password-reset` | Customer and staff reset links |
| `08-data-privacy` | PIPEDA export download, erasure (wrong password, blocked by an upcoming booking, success), waiver records anonymized |

## Running locally

Prerequisites: `docker compose up -d postgres`, Elixir/Erlang (asdf), Node, and
Google Chrome (tests use `channel: 'chrome'`; set `E2E_BROWSER_CHANNEL=chromium`
after `pnpm exec playwright install chromium` to use the bundled browser).

```bash
pnpm --dir ../frontend install --frozen-lockfile && pnpm --dir ../frontend build
pnpm install
pnpm test:fresh     # drops/recreates + seeds sports_coach_bookings_e2e, then runs everything
pnpm test           # reuse the existing database
```

`pnpm test` starts `mix phx.server` itself (dev env, port `4010`, database
`sports_coach_bookings_e2e`, `RATE_LIMITING=off`) and reuses a server that is
already listening. The SPAs must be built first; Phoenix serves
`frontend/apps/*/dist`.

## How it works

- **Tenant host.** Tenancy is host-based, so tests use `demo.localhost:4010`
  (Chromium resolves `*.localhost` to loopback; CI adds a hosts entry for Node).
- **Seeded data.** `mix run priv/repo/seeds.exs` creates the `demo` tenant, an
  owner, a coach, a customer household, and a schedule (see `helpers.ts`).
- **Payments.** Without `STRIPE_SECRET_KEY` the dev server uses the in-memory
  `Payments.Providers.Fake`; the purchase journey posts the provider's
  `checkout.session.completed` webhook itself.
- **Email.** Dev mail goes to Swoosh's local mailbox; tests read it from
  `/dev/mailbox/json` and follow the real links.
- **Isolation.** Each journey gets a fresh customer (`fixtures.ts`), set up
  through the API except where the journey is *about* that UI. Teardown cancels
  leftover bookings so repeated runs don't fill sessions.
- **Time.** Attendance and feedback open when a session starts, and every seeded
  session is in the future, so the coach journey creates a just-started session
  through the owner API.

## Reset script

`scripts/reset-db.sh` needs a Postgres superuser. Locally it uses the
docker-compose container; elsewhere set `PSQL="psql -h localhost -U postgres"`.
