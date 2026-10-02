import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
#
# WP-20 owns the production block below. Every variable is documented in
# `docs/ops.md` ("Required runtime secrets"). `MIX_ENV=prod mix release` does
# not evaluate this block at build time, so the release builds with no secrets;
# the app refuses to boot without the required ones.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/sports_coach_bookings start
#
# The release overlay `bin/server` sets this for you.
if System.get_env("PHX_SERVER") do
  config :sports_coach_bookings, SportsCoachBookingsWeb.Endpoint, server: true
end

config :sports_coach_bookings, SportsCoachBookingsWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # --- Rate limiting --------------------------------------------------------
  # Shared Postgres counters by default so limits hold across machines; set
  # RATE_LIMIT_BACKEND=ets to fall back to per-node in-memory counters.
  config :sports_coach_bookings,
         :rate_limit_backend,
         if(System.get_env("RATE_LIMIT_BACKEND") == "ets", do: :ets, else: :postgres)

  # --- Database -------------------------------------------------------------
  #
  # Prefer a single DATABASE_URL (`ecto://USER:PASS@HOST:PORT/DB`). Discrete
  # PGHOST/PGUSER/PGPASSWORD/PGDATABASE/PGPORT are supported for platforms that
  # inject them separately. The app MUST connect as a non-superuser, no-BYPASSRLS
  # role (see docs/conventions.md §1.4); we refuse to boot as `postgres`.
  database_url = System.get_env("DATABASE_URL")

  db_user =
    if database_url do
      case database_url |> URI.parse() |> Map.get(:userinfo) do
        nil -> nil
        userinfo -> userinfo |> String.split(":") |> List.first()
      end
    else
      System.get_env("PGUSER", "scb_app")
    end

  repo_config =
    if database_url do
      [url: database_url]
    else
      host =
        System.get_env("PGHOST") ||
          raise "environment variable DATABASE_URL (or PGHOST) is missing (see docs/ops.md)"

      [
        hostname: host,
        username: db_user,
        password:
          System.get_env("PGPASSWORD") ||
            raise("environment variable PGPASSWORD is missing (see docs/ops.md)"),
        database:
          System.get_env("PGDATABASE") ||
            raise("environment variable PGDATABASE is missing (see docs/ops.md)"),
        port: String.to_integer(System.get_env("PGPORT", "5432"))
      ]
    end

  if db_user in [nil, "postgres", "rdsadmin"] do
    raise """
    refusing to start: the database role #{inspect(db_user)} is a superuser/owner.
    The app must connect as the non-superuser, NOBYPASSRLS role (scb_app) or RLS
    is bypassed. See docs/conventions.md §1.4 and docs/ops.md.
    """
  end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :sports_coach_bookings,
         SportsCoachBookings.Repo,
         repo_config ++
           [
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             socket_options: maybe_ipv6,
             # Managed Postgres requires TLS; local docker-compose does not.
             ssl: System.get_env("ECTO_SSL") in ~w(true 1)
           ]

  # --- Web / secrets --------------------------------------------------------
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :sports_coach_bookings, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :sports_coach_bookings, SportsCoachBookingsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind on all interfaces (Fly forwards to the internal address).
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Tenant resolution. BASE_DOMAIN is the wildcard apex; PLATFORM_HOST serves
  # signup/staff auth. Both default to PHX_HOST for a single-host deploy.
  config :sports_coach_bookings,
         :base_domain,
         System.get_env("BASE_DOMAIN", host)

  config :sports_coach_bookings,
         :platform_host,
         System.get_env("PLATFORM_HOST", host)

  # Where the built SPA bundles live. In the Docker image the release sits at
  # /app and the frontend dist is copied to /app/frontend/apps/*/dist.
  if repo_root = System.get_env("REPO_ROOT") do
    config :sports_coach_bookings, :repo_root, repo_root
  end

  # --- Field-level encryption (WP-06) --------------------------------------
  # Player medical data is encrypted with a Cloak AES-256-GCM key. The dev
  # fallback key must never be used in production.
  if is_nil(System.get_env("PLAYER_MEDICAL_ENCRYPTION_KEY")) do
    raise """
    environment variable PLAYER_MEDICAL_ENCRYPTION_KEY is missing.
    Generate a 32-byte key and base64-encode it:
      mix run -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'
    See docs/ops.md for rotation.
    """
  end

  # --- Email (Resend) -------------------------------------------------------
  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :sports_coach_bookings, SportsCoachBookings.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key

    config :swoosh, :api_client, Swoosh.ApiClient.Req
  end

  config :sports_coach_bookings,
         :resend_webhook_secret,
         System.get_env("RESEND_WEBHOOK_SECRET")

  config :sports_coach_bookings,
         :notifications_from_address,
         System.get_env("NOTIFICATIONS_FROM_ADDRESS") ||
           "notifications@mail.sportscoachbookings.com"

  config :sports_coach_bookings,
         :notifications_app_url,
         System.get_env("APP_URL") || "https://#{host}"

  # --- Stripe Connect (WP-04) ----------------------------------------------
  # Secrets are optional so a deploy without Stripe boots; Stripe features then
  # fail closed at the API boundary rather than at boot.
  config :sports_coach_bookings,
         :payments_stripe_secret_key,
         System.get_env("STRIPE_SECRET_KEY")

  config :sports_coach_bookings,
         :payments_stripe_webhook_secret,
         System.get_env("STRIPE_WEBHOOK_SECRET")

  config :sports_coach_bookings,
         :payments_stripe_account_type,
         System.get_env("STRIPE_ACCOUNT_TYPE", "express")

  if fee = System.get_env("STRIPE_PLATFORM_FEE_BPS") do
    config :sports_coach_bookings, :payments_default_platform_fee_bps, String.to_integer(fee)
  end

  # --- Object storage (WP-01) ----------------------------------------------
  # When S3_BUCKET is set, use the real S3-compatible backend; otherwise the
  # deterministic Fake remains (do NOT leave Fake on for production uploads).
  if bucket = System.get_env("S3_BUCKET") do
    config :sports_coach_bookings,
           :tenancy_storage,
           SportsCoachBookings.Tenancy.Storage.S3

    config :sports_coach_bookings, SportsCoachBookings.Tenancy.Storage.S3,
      bucket: bucket,
      region: System.get_env("S3_REGION", "ca-central-1"),
      access_key_id:
        System.get_env("S3_ACCESS_KEY_ID") ||
          raise("environment variable S3_ACCESS_KEY_ID is missing (see docs/ops.md)"),
      secret_access_key:
        System.get_env("S3_SECRET_ACCESS_KEY") ||
          raise("environment variable S3_SECRET_ACCESS_KEY is missing (see docs/ops.md)"),
      endpoint: System.get_env("S3_ENDPOINT"),
      public_base_url: System.get_env("S3_PUBLIC_BASE_URL"),
      presign_ttl_seconds: String.to_integer(System.get_env("S3_PRESIGN_TTL_SECONDS", "900")),
      force_path_style: System.get_env("S3_FORCE_PATH_STYLE", "false") in ~w(true 1),
      # Waiver PDFs hold a minor's name and the signer's IP; keep them out of the
      # public assets bucket by setting S3_PRIVATE_BUCKET (docs/ops.md).
      private_bucket: System.get_env("S3_PRIVATE_BUCKET")

    config :sports_coach_bookings,
           :waiver_pdf_store,
           SportsCoachBookings.Waivers.PdfStore.S3
  end

  # --- Error reporting hook (WP-20) ----------------------------------------
  # Set ERROR_REPORTER_MODULE to a module exporting capture_exception/4
  # (e.g. a Sentry adapter). nil = log-only.
  if reporter = System.get_env("ERROR_REPORTER_MODULE") do
    config :sports_coach_bookings, :error_reporter, Module.concat([reporter])
  end
end
