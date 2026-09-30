# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sports_coach_bookings,
  ecto_repos: [SportsCoachBookings.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# IANA timezone database for DST-safe recurrence (WP-11). Used by
# `DateTime.new/4` / `DateTime.shift_zone/3` to keep local wall-clock times across
# daylight-saving transitions.
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Oban is the single background-job system. Events are published through a
# transactional outbox: SportsCoachBookings.Events.publish/2 inserts a job in
# the same transaction as the state change.
config :sports_coach_bookings, Oban,
  repo: SportsCoachBookings.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", SportsCoachBookings.Credits.DispatchExpiryWorker},
       {"* * * * *", SportsCoachBookings.Reservations.SweepWorker}
     ]}
  ],
  queues: [
    default: 10,
    events: 20,
    mailers: 10,
    notifications: 10,
    payments: 10
  ]

# Event subscriber registry. Maps a domain event name to the list of subscriber
# modules that implement handle_event/2. Add entries here when you publish or
# subscribe to a new event (see docs/rfcs).
config :sports_coach_bookings, :event_subscribers, %{
  "tenant.created" => [
    SportsCoachBookings.Policies.TenantCreatedSubscriber,
    SportsCoachBookings.Legal.TenantCreatedSubscriber
  ],
  "payment.succeeded" => [SportsCoachBookings.Commerce.PaymentEventsSubscriber],
  "payment.failed" => [SportsCoachBookings.Commerce.PaymentEventsSubscriber],
  "payment.refunded" => [SportsCoachBookings.Commerce.PaymentEventsSubscriber],
  "order.paid" => [
    SportsCoachBookings.Inventory.OrderEventsSubscriber,
    SportsCoachBookings.Credits.OrderEventsSubscriber,
    SportsCoachBookings.Bookings.OrderEventsSubscriber,
    SportsCoachBookings.Notifications.Subscribers.EventSubscriber
  ],
  "order.expired" => [
    SportsCoachBookings.Inventory.OrderEventsSubscriber,
    SportsCoachBookings.Bookings.OrderEventsSubscriber,
    SportsCoachBookings.Notifications.Subscribers.EventSubscriber
  ],
  "order.cancelled" => [SportsCoachBookings.Inventory.OrderEventsSubscriber],
  "order.refunded" => [
    SportsCoachBookings.Inventory.OrderEventsSubscriber,
    SportsCoachBookings.Credits.OrderEventsSubscriber,
    SportsCoachBookings.Notifications.Subscribers.EventSubscriber
  ],
  "session.cancelled" => [
    SportsCoachBookings.Bookings.SessionEventsSubscriber,
    SportsCoachBookings.Notifications.Subscribers.EventSubscriber
  ],
  "session.rescheduled" => [
    SportsCoachBookings.Bookings.SessionEventsSubscriber,
    SportsCoachBookings.Notifications.Subscribers.EventSubscriber
  ],
  # WP-16 transactional email subscribers. `staff.invited` and
  # `household.member_invited` are intentionally absent: WP-01/WP-02 send those
  # invitation emails directly and subscribing again would double-send.
  "staff.joined" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "staff.removed" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "customer.registered" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "household.member_joined" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "waiver.published" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "waiver.signed" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "credits.granted" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "credits.expiring_soon" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "credits.expired" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "booking.created" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "booking.cancelled" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "booking.rebooked" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "booking.attended" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "booking.no_show" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "feedback.submitted" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber],
  "stock.low" => [SportsCoachBookings.Notifications.Subscribers.EventSubscriber]
}

# WP-12: how long a credit returned after its original lot expired stays valid
# on the replacement `return_grace` lot. Per-tenant configuration would need a
# `tenants.settings` column (see docs/rfcs); until then this app-level default is
# the seam.
config :sports_coach_bookings, :credits_return_grace_days, 14

# WP-08: resolves a household's order line ids for the portal pickup view.
# Commerce (wp-13) implements `order_line_ids_for_household/1`; the Inventory
# read seam points at it. See
# docs/rfcs/20260928-inventory-commerce-event-contract.md.
config :sports_coach_bookings,
       :inventory_order_source,
       SportsCoachBookings.Commerce

# WP-13: resolves a drop-in booking hold (created by wp-14 Bookings) to its
# offering, price, and household. WP-14 points this at its own implementation.
# See SportsCoachBookings.Commerce.BookingHoldSource.
config :sports_coach_bookings,
       :commerce_booking_hold_source,
       SportsCoachBookings.Bookings.HoldSource

# WP-11: resolves a session's roster and "already booked" answers from Bookings
# (wp-14). See docs/rfcs/20260928-scheduling-tzdata-and-bookings-seam.md.
config :sports_coach_bookings,
       :scheduling_bookings_source,
       SportsCoachBookings.Bookings.SchedulingSource

# Module that answers whether a coach may see a player. Owned by WP-14; kept
# configurable so tests can exercise both visibility outcomes. See
# SportsCoachBookings.Players.Policy.
config :sports_coach_bookings, :coach_access, SportsCoachBookings.Bookings.CoachAccess

# Player medical data vault. The key is read at runtime from
# PLAYER_MEDICAL_ENCRYPTION_KEY (base64); see Players.Vault and
# docs/rfcs/20260928-players-medical-encryption.md.
config :sports_coach_bookings, SportsCoachBookings.Players.Vault, []

# The platform (apex) hostname. Requests to this host are not tenant-scoped.
config :sports_coach_bookings, :platform_host, "sportscoachbookings.com"

# Repo root, used to locate the built frontend bundles for SPA serving.
config :sports_coach_bookings, :repo_root, Path.expand("../..", __DIR__)

# Reserved slugs that may not be used as tenant subdomains.
config :sports_coach_bookings, :reserved_slugs, ~w(
  www api app admin portal staff signup login logout static assets docs
  support help status mail smtp webhooks platform dashboard
)

# Staff session cookie domain. `nil` = host-only (dev/test on localhost); a
# leading-dot domain is set in production so one login spans all tenant
# subdomains. See docs/rfcs/20260928-tenancy-session-cookie.md.
config :sports_coach_bookings, :session_domain, nil

# Cookie / LiveView signing salts and the `Secure` cookie flag. These salts are
# not secrets on their own (Plug mixes them with SECRET_KEY_BASE), but they are
# kept in config rather than hardcoded in the endpoint. `:session_secure` is
# turned on in production (HTTPS only).
config :sports_coach_bookings, :session_signing_salt, "MOSH6PiA"
config :sports_coach_bookings, :session_secure, false

# PBKDF2 work factor for staff passwords. Lowered in test.exs for speed.
config :sports_coach_bookings,
       :password_hashing_iterations,
       if(config_env() == :test, do: 1_000, else: 120_000)

# Object storage backend for tenant assets. No S3 in this environment, so the
# deterministic fake is the default. See
# docs/rfcs/20260928-tenancy-storage-stub.md.
config :sports_coach_bookings,
       :tenancy_storage,
       SportsCoachBookings.Tenancy.Storage.Fake

# --- WP-04 Payments --------------------------------------------------------

# The payment provider adapter. Tests swap this for the in-memory Fake; a second
# real provider only needs to implement SportsCoachBookings.Payments.Provider.
config :sports_coach_bookings,
       :payments_provider,
       SportsCoachBookings.Payments.Providers.Stripe

# Stripe Connect configuration. Express accounts with direct charges (pending
# decision #1); the account type and fee stay configurable. No real keys exist
# in this environment, so calls fail gracefully and the persisted status is
# returned. `:payments_stripe_client` is injectable so tests never hit the
# network.
config :sports_coach_bookings,
       :payments_stripe_account_type,
       "express"

config :sports_coach_bookings,
       :payments_stripe_api_base,
       "https://api.stripe.com"

config :sports_coach_bookings,
       :payments_stripe_client,
       SportsCoachBookings.Payments.Providers.Stripe.Client

config :sports_coach_bookings, :payments_stripe_secret_key, nil
config :sports_coach_bookings, :payments_stripe_webhook_secret, nil

# Platform fee in basis points applied to new provider accounts (platform-
# controlled; default 0).
config :sports_coach_bookings, :payments_default_platform_fee_bps, 0

# Configure the endpoint
config :sports_coach_bookings, SportsCoachBookingsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: SportsCoachBookingsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SportsCoachBookings.PubSub,
  live_view: [signing_salt: "pD2uUeyP"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sports_coach_bookings, SportsCoachBookings.Mailer, adapter: Swoosh.Adapters.Local

# --- WP-05 Notifications ---------------------------------------------------

# Template registry: key => module implementing
# SportsCoachBookings.Notifications.Template. Contexts add their own templates
# here instead of editing a shared module (no merge conflicts).
config :sports_coach_bookings, :notification_templates, %{
  sample: SportsCoachBookings.Notifications.Templates.Sample,
  customer_confirm: SportsCoachBookings.Notifications.Templates.CustomerConfirm,
  customer_reset_password: SportsCoachBookings.Notifications.Templates.CustomerResetPassword,
  customer_email_change: SportsCoachBookings.Notifications.Templates.CustomerEmailChange,
  household_invite: SportsCoachBookings.Notifications.Templates.HouseholdInvite,
  staff_invite: SportsCoachBookings.Notifications.Templates.StaffInvite,
  staff_confirm: SportsCoachBookings.Notifications.Templates.StaffConfirm,
  staff_reset_password: SportsCoachBookings.Notifications.Templates.StaffResetPassword,
  # WP-16 event-driven transactional emails.
  booking_confirmed: SportsCoachBookings.Notifications.Templates.BookingConfirmed,
  booking_cancelled: SportsCoachBookings.Notifications.Templates.BookingCancelled,
  booking_rebooked: SportsCoachBookings.Notifications.Templates.BookingRebooked,
  booking_attended: SportsCoachBookings.Notifications.Templates.BookingAttended,
  booking_no_show: SportsCoachBookings.Notifications.Templates.BookingNoShow,
  session_cancelled_by_provider:
    SportsCoachBookings.Notifications.Templates.SessionCancelledByProvider,
  session_rescheduled: SportsCoachBookings.Notifications.Templates.SessionRescheduled,
  order_receipt: SportsCoachBookings.Notifications.Templates.OrderReceipt,
  order_refunded: SportsCoachBookings.Notifications.Templates.OrderRefunded,
  order_expired: SportsCoachBookings.Notifications.Templates.OrderExpired,
  credits_granted: SportsCoachBookings.Notifications.Templates.CreditsGranted,
  credits_expiring: SportsCoachBookings.Notifications.Templates.CreditsExpiring,
  credits_expired: SportsCoachBookings.Notifications.Templates.CreditsExpired,
  staff_joined: SportsCoachBookings.Notifications.Templates.StaffJoined,
  staff_removed: SportsCoachBookings.Notifications.Templates.StaffRemoved,
  customer_welcome: SportsCoachBookings.Notifications.Templates.CustomerWelcome,
  household_member_joined: SportsCoachBookings.Notifications.Templates.HouseholdMemberJoined,
  waiver_resign_required: SportsCoachBookings.Notifications.Templates.WaiverResignRequired,
  waiver_signed: SportsCoachBookings.Notifications.Templates.WaiverSigned,
  # Portal legal documents / waiver copies requested by the customer.
  legal_document: SportsCoachBookings.Notifications.Templates.LegalDocument,
  feedback_shared: SportsCoachBookings.Notifications.Templates.FeedbackShared,
  admin_low_stock: SportsCoachBookings.Notifications.Templates.AdminLowStock,
  # WP-17 staff broadcast emails.
  broadcast: SportsCoachBookings.Notifications.Templates.Broadcast
}

# wp-02's `Customers.Preferences` seam delegates here once wired up.
config :sports_coach_bookings,
       :customer_preferences_module,
       SportsCoachBookings.Notifications.Preferences

# The `From:` address and link base for transactional email.
config :sports_coach_bookings,
       :notifications_from_address,
       "notifications@mail.sportscoachbookings.com"

config :sports_coach_bookings,
       :notifications_app_url,
       "https://sportscoachbookings.com"

config :sports_coach_bookings, :notifications_url_scheme, "https"

# Resend (Svix) webhook signing secret. Overridden per environment at runtime;
# tests set a known value.
config :sports_coach_bookings, :resend_webhook_secret, nil

# Injectable deliverer: tests swap this for a fake.
config :sports_coach_bookings,
       :notifications_deliverer,
       SportsCoachBookings.Notifications.Deliverer.Swoosh

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sports_coach_bookings: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  sports_coach_bookings: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger. `tenant_id` and `error` are set by the tenancy
# plug and the ops error reporter respectively (WP-20).
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :tenant_id, :error]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# WP-19: scrub secrets and medical data from request params before they reach
# logs / telemetry. This is defence in depth on top of per-schema `redact: true`
# virtual fields (e.g. `CustomerUser.password`).
config :phoenix,
       :filter_parameters,
       ~w(password password_confirmation token tokens secret api_key authorization cookie medical medical_info allergies conditions medications)

config :logger, :filter_parameters, ~w(password token secret api_key authorization cookie medical)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
