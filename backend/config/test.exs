import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sports_coach_bookings, SportsCoachBookings.Repo,
  username: "scb_app",
  password: "scb_app",
  hostname: "localhost",
  port: 5432,
  database: "sports_coach_bookings_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  # In shared sandbox mode every process uses the owner's single connection, so
  # concurrent tasks queue. Raise DBConnection's queue timeout so the concurrency
  # tests (wp-14) wait for the connection instead of being dropped.
  queue_target: 5_000,
  queue_interval: 5_000

# Base domain used to resolve tenants from the Host header in tests.
config :sports_coach_bookings, :base_domain, "localhost"

# Run Oban in manual test mode: jobs are inserted but never executed
# automatically, so tests can assert on the outbox rows deterministically.
config :sports_coach_bookings, Oban, testing: :manual, queues: [], plugins: []

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sports_coach_bookings, SportsCoachBookingsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9M+yVo3ZbiBnvxk6UoD3h3ylKTK2plQjzgmEQOvbHv+cTOC7liomU/8jB9RryE4l",
  server: false

# In test we don't send emails
config :sports_coach_bookings, SportsCoachBookings.Mailer, adapter: Swoosh.Adapters.Test

# A known Resend (Svix) webhook secret for signature tests.
config :sports_coach_bookings,
       :resend_webhook_secret,
       "whsec_" <> Base.encode64("test-resend-webhook-secret")

# WP-04: use the in-memory provider so tests never make a network call. The
# Stripe adapter is still exercised directly (signature + normalisation) with a
# known webhook secret.
config :sports_coach_bookings,
       :payments_provider,
       SportsCoachBookings.Payments.Providers.Fake

config :sports_coach_bookings,
       :payments_stripe_webhook_secret,
       "whsec_test_secret"

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# WP-19 rate limiting is disabled suite-wide because the limiter's ETS table is
# shared across async tests. The dedicated
# `test/security/rate_limit_test.exs` enables it explicitly.
config :sports_coach_bookings, :rate_limiting_enabled, false
