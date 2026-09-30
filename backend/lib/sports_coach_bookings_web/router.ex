defmodule SportsCoachBookingsWeb.Router do
  use SportsCoachBookingsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug SportsCoachBookingsWeb.Plugs.VerifyOrigin
  end

  pipeline :api_spec do
    plug OpenApiSpex.Plug.PutApiSpec, module: SportsCoachBookingsWeb.ApiSpec
  end

  pipeline :resolve_tenant do
    plug SportsCoachBookingsWeb.Plugs.ResolveTenant
  end

  # WP-20: ops probes. Not tenant-scoped and excluded from force_ssl (see
  # config/prod.exs). `/health` is a liveness check; `/health/ready` checks the
  # database. See docs/rfcs/20260928-ops-health-endpoint.md.
  get "/health", SportsCoachBookingsWeb.HealthController, :show
  get "/health/ready", SportsCoachBookingsWeb.HealthController, :ready

  # Loads the global staff session cookie (non-halting). Used by the platform
  # auth endpoints and by invite acceptance.
  #
  # CSRF: this JSON API uses `SameSite=Lax` session cookies (cross-site state
  # changes never attach the cookie) plus `Plugs.VerifyOrigin` on the `:api`
  # pipeline. Accepted as a false positive for Sobelow's `protect_from_forgery`
  # heuristic; see docs/security-review.md.
  # sobelow_skip ["Config.CSRF"]
  pipeline :staff_session do
    plug :fetch_session
    plug SportsCoachBookingsWeb.Plugs.FetchStaffUser
  end

  # Requires a logged-in staff user. (CSRF rationale above.)
  # sobelow_skip ["Config.CSRF"]
  pipeline :require_staff_user do
    plug :fetch_session
    plug SportsCoachBookingsWeb.Plugs.FetchStaffUser
    plug SportsCoachBookingsWeb.Plugs.RequireStaffUser
  end

  # Requires a logged-in staff user with an active membership in the tenant
  # resolved from the host (builds the StaffActor). (CSRF rationale above.)
  # sobelow_skip ["Config.CSRF"]
  pipeline :staff_auth do
    plug :fetch_session
    plug SportsCoachBookingsWeb.Plugs.FetchStaffUser
    plug SportsCoachBookingsWeb.Plugs.StaffActor
  end

  # Loads the host-only customer session (non-halting) and assigns the
  # CustomerActor when the request is authenticated for the resolved tenant.
  # (CSRF rationale above.)
  # sobelow_skip ["Config.CSRF"]
  pipeline :portal_session do
    plug :fetch_session
    plug SportsCoachBookingsWeb.Plugs.FetchCustomerUser
    plug SportsCoachBookingsWeb.Plugs.FetchCustomerActor
  end

  # Requires an authenticated customer with a household in the resolved tenant.
  # (CSRF rationale above.)
  # sobelow_skip ["Config.CSRF"]
  pipeline :require_customer do
    plug :fetch_session
    plug SportsCoachBookingsWeb.Plugs.FetchCustomerUser
    plug SportsCoachBookingsWeb.Plugs.CustomerActor
  end

  # WP-19 rate limiting. Buckets are keyed by client IP, the resolved tenant,
  # and (for auth) the submitted email. See
  # `SportsCoachBookingsWeb.Plugs.RateLimit`.
  pipeline :rate_limit_auth do
    plug SportsCoachBookingsWeb.Plugs.RateLimit,
      keys: [:auth],
      limit: 30,
      window: 60,
      account_param: "email"
  end

  pipeline :rate_limit_signup do
    plug SportsCoachBookingsWeb.Plugs.RateLimit,
      keys: [:signup],
      limit: 10,
      window: 3600,
      account_param: "email"
  end

  pipeline :rate_limit_invite do
    plug SportsCoachBookingsWeb.Plugs.RateLimit, keys: [:invite], limit: 30, window: 60
  end

  pipeline :rate_limit_webhook do
    plug SportsCoachBookingsWeb.Plugs.RateLimit, keys: [:webhook], limit: 300, window: 60
  end

  pipeline :rate_limit_checkout do
    plug SportsCoachBookingsWeb.Plugs.RateLimit, keys: [:checkout], limit: 30, window: 60
  end

  pipeline :rate_limit_discount do
    plug SportsCoachBookingsWeb.Plugs.RateLimit, keys: [:discount], limit: 120, window: 60
  end

  # Reads the guest reservation bearer token from `x-reservation-token` and
  # loads the reservation (401 when absent, 404 when it does not match).
  pipeline :reservation_token do
    plug SportsCoachBookingsWeb.Plugs.ReservationToken
  end

  # Platform host: tenant signup, staff auth, tenant picker. No tenant resolved.
  scope "/api/platform", SportsCoachBookingsWeb.Platform do
    pipe_through [:api, :staff_session, :rate_limit_auth]

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete

    post "/staff_users", RegistrationController, :create
    post "/confirmation", RegistrationController, :confirm
    post "/confirmation/resend", RegistrationController, :resend

    post "/password_reset", PasswordResetController, :create
    put "/password_reset", PasswordResetController, :update
  end

  # Signup is slower and more expensive than auth; limit it per IP + email over
  # a longer window.
  scope "/api/platform", SportsCoachBookingsWeb.Platform do
    pipe_through [:api, :staff_session, :rate_limit_signup]

    post "/signup", SignupController, :create
    get "/slug_available", SignupController, :slug_available
  end

  scope "/api/platform", SportsCoachBookingsWeb.Platform do
    pipe_through [:api, :require_staff_user]

    get "/me", MeController, :show
  end

  # Tenant-scoped APIs. The tenant is resolved from the host by the plug.
  scope "/api" do
    pipe_through [:api, :resolve_tenant]

    # Invite acceptance: tenant resolved, staff session optional (the token is
    # the credential).
    scope "/invites", SportsCoachBookingsWeb.Staff do
      pipe_through [:staff_session, :rate_limit_invite]

      get "/:token", InvitesController, :show
      post "/:token/accept", InvitesController, :accept
    end

    scope "/staff", SportsCoachBookingsWeb.Staff do
      pipe_through :staff_auth

      # WP-01: tenant settings, branding, team.
      scope "/settings", Settings do
        get "/", SettingsController, :show
        patch "/", SettingsController, :update
        put "/", SettingsController, :update
        post "/transfer_ownership", SettingsController, :transfer_ownership
        delete "/", SettingsController, :delete
      end

      scope "/branding", Settings do
        patch "/", BrandingController, :update
        put "/", BrandingController, :update
        post "/uploads", BrandingController, :create_upload
      end

      scope "/team", Team do
        get "/", MembersController, :index
        post "/invites", MembersController, :invite
        get "/invites", MembersController, :invites
        patch "/members/:id", MembersController, :update
        put "/members/:id", MembersController, :update
        delete "/members/:id", MembersController, :delete
      end

      scope "/policies", Policies do
        post "/simulate", PoliciesController, :simulate

        get "/", PoliciesController, :index
        post "/", PoliciesController, :create
        get "/:id", PoliciesController, :show
        patch "/:id", PoliciesController, :update
        put "/:id", PoliciesController, :update
        post "/:id/archive", PoliciesController, :archive
        post "/:id/default", PoliciesController, :set_default
        post "/:id/assign", PoliciesController, :assign
        delete "/assignments/:offering_id", PoliciesController, :unassign
      end

      scope "/waivers", Waivers do
        resources "/templates", TemplatesController, only: [:index, :show, :create, :update]
        post "/templates/:id/archive", TemplatesController, :archive

        get "/templates/:template_id/versions", VersionsController, :index
        post "/templates/:template_id/versions", VersionsController, :create
        patch "/versions/:id", VersionsController, :update
        post "/versions/:id/publish", VersionsController, :publish
        get "/versions/:id/preview", VersionsController, :preview

        get "/signatures", SignaturesController, :index
        get "/signatures/export", SignaturesController, :export
        get "/signatures/:id/pdf", SignaturesController, :pdf
      end

      get "/players", Players.PlayersController, :index
      get "/players/:id", Players.PlayersController, :show
      patch "/players/:id", Players.PlayersController, :update
      put "/players/:id", Players.PlayersController, :update

      put "/players/:id/profile",
          Players.PlayersController,
          :update_profile

      get "/players/:id/medical", Players.MedicalController, :show
      put "/players/:id/medical", Players.MedicalController, :update

      get "/position_options", Players.PositionOptionsController, :index
      post "/position_options", Players.PositionOptionsController, :create

      patch "/position_options/:id",
            Players.PositionOptionsController,
            :update

      scope "/customers", Customers do
        get "/", CustomersController, :index
        get "/:id", CustomersController, :show
        patch "/:id", CustomersController, :update
        put "/:id", CustomersController, :update
        post "/:id/password_reset", CustomersController, :reset_password
        post "/:id/deactivate", CustomersController, :deactivate
        post "/:id/reactivate", CustomersController, :reactivate
      end

      scope "/households", Customers do
        get "/", HouseholdsController, :index
        get "/:id", HouseholdsController, :show
      end

      # WP-12: household credit balance, lots, ledger, grant, adjust.
      scope "/households", Credits do
        get "/:household_id/credits", CreditsController, :show
        get "/:household_id/credits/lots", CreditsController, :lots
        get "/:household_id/credits/ledger", CreditsController, :ledger
        post "/:household_id/credits/grant", CreditsController, :grant
        post "/:household_id/credits/adjust", CreditsController, :adjust
      end

      get "/notifications/deliveries", Notifications.DeliveriesController, :index

      post "/notifications/deliveries/:id/resend", Notifications.DeliveriesController, :resend

      # WP-17: staff broadcast messaging.
      scope "/broadcasts", Broadcasts do
        get "/", BroadcastsController, :index
        post "/", BroadcastsController, :create
        get "/:id", BroadcastsController, :show
        patch "/:id", BroadcastsController, :update
        put "/:id", BroadcastsController, :update
        delete "/:id", BroadcastsController, :delete
        get "/:id/recipients", BroadcastsController, :recipients
        post "/:id/preview", BroadcastsController, :preview
        post "/:id/test", BroadcastsController, :send_test
        post "/:id/schedule", BroadcastsController, :schedule
        post "/:id/send", BroadcastsController, :send_now
        post "/:id/cancel", BroadcastsController, :cancel
        get "/:id/history", BroadcastsController, :history
      end

      scope "/payments", Payments do
        get "/connect", ConnectController, :show
        post "/connect/onboarding", ConnectController, :onboarding
      end
    end

    scope "/staff/catalog", SportsCoachBookingsWeb.Staff.Catalog do
      pipe_through [:staff_auth, :rate_limit_discount]
      resources "/venues", VenuesController, only: [:index, :show, :create, :update]
      post "/venues/:id/archive", VenuesController, :archive

      resources "/offerings", OfferingsController, only: [:index, :show, :create, :update]
      post "/offerings/reorder", OfferingsController, :reorder
      post "/offerings/:id/archive", OfferingsController, :archive

      resources "/packages", PackagesController, only: [:index, :show, :create, :update]
      post "/packages/reorder", PackagesController, :reorder
      put "/packages/:id/offerings", PackagesController, :set_offerings
      post "/packages/:id/archive", PackagesController, :archive

      resources "/discounts", DiscountsController, only: [:index, :show, :create, :update]
      post "/discounts/validate", DiscountsController, :validate
      post "/discounts/:id/archive", DiscountsController, :archive

      resources "/tax_rates", TaxRatesController, only: [:index, :show, :create, :update]
      post "/tax_rates/:id/archive", TaxRatesController, :archive
    end

    scope "/staff/inventory", SportsCoachBookingsWeb.Staff.Inventory do
      pipe_through :staff_auth

      resources "/products", ProductsController, only: [:index, :show, :create, :update]
      post "/products/reorder", ProductsController, :reorder
      post "/products/:id/archive", ProductsController, :archive

      get "/products/:product_id/variants", VariantsController, :index
      post "/products/:product_id/variants", VariantsController, :create
      get "/variants/:id", VariantsController, :show
      patch "/variants/:id", VariantsController, :update
      put "/variants/:id", VariantsController, :update
      post "/variants/:id/archive", VariantsController, :archive

      get "/stock_levels", StockController, :index
      post "/variants/:id/stock/receive", StockController, :receive
      post "/variants/:id/stock/adjust", StockController, :adjust
      get "/variants/:id/stock/movements", StockController, :movements

      get "/fulfillments", FulfillmentsController, :index
      post "/fulfillments/:id/ready", FulfillmentsController, :ready
      post "/fulfillments/:id/pickup", FulfillmentsController, :pickup

      post "/uploads", UploadsController, :create
    end

    # Legal documents: staff (owner/admin) list versions and publish new ones.
    scope "/staff/legal_documents", SportsCoachBookingsWeb.Staff.Legal do
      pipe_through :staff_auth

      get "/", DocumentsController, :index
      post "/", DocumentsController, :create
    end

    scope "/staff/schedule", SportsCoachBookingsWeb.Staff.Schedule do
      pipe_through :staff_auth

      get "/sessions", SessionsController, :index
      post "/sessions", SessionsController, :create
      get "/sessions/:id", SessionsController, :show
      patch "/sessions/:id", SessionsController, :update
      put "/sessions/:id", SessionsController, :update
      post "/sessions/:id/reschedule", SessionsController, :reschedule
      post "/sessions/:id/cancel", SessionsController, :cancel
      post "/sessions/:id/edit_series", SessionsController, :edit_series
      post "/series", SessionsController, :create_series
    end

    # WP-13: staff order list/detail, refunds, offline orders.
    scope "/staff/orders", SportsCoachBookingsWeb.Staff.Orders do
      pipe_through :staff_auth

      get "/", OrdersController, :index
      post "/", OrdersController, :create_offline
      get "/:id", OrdersController, :show
      post "/:id/refund", OrdersController, :refund
    end

    # WP-14: staff booking history, book-on-behalf, roster, cancel, attendance.
    scope "/staff/bookings", SportsCoachBookingsWeb.Staff.Bookings do
      pipe_through :staff_auth

      get "/", BookingsController, :index
      post "/", BookingsController, :create
      get "/:id", BookingsController, :show
      post "/:id/cancel", BookingsController, :cancel
      post "/:id/attendance", BookingsController, :attendance
    end

    scope "/staff/sessions", SportsCoachBookingsWeb.Staff.Bookings do
      pipe_through :staff_auth

      get "/:session_id/roster", BookingsController, :roster
    end

    scope "/staff", SportsCoachBookingsWeb.Staff.Schedule do
      pipe_through :staff_auth

      get "/my-sessions", SessionsController, :my_sessions
    end

    # WP-15: coach API (own sessions, roster, player view, bulk attendance).
    scope "/staff/coach", SportsCoachBookingsWeb.Staff.Coach do
      pipe_through :staff_auth

      get "/sessions", CoachController, :index
      get "/sessions/:session_id/roster", CoachController, :roster
      post "/sessions/:session_id/attendance", CoachController, :attendance
      get "/players/:player_id", CoachController, :player
    end

    # WP-15: feedback CRUD, sharing, skill tags, and admin review.
    scope "/staff/feedback", SportsCoachBookingsWeb.Staff.Feedback do
      pipe_through :staff_auth

      get "/", FeedbackController, :index
      post "/", FeedbackController, :create
      get "/skill_tags", FeedbackController, :skill_tags
      post "/skill_tags", FeedbackController, :create_skill_tag
      get "/:id", FeedbackController, :show
      patch "/:id", FeedbackController, :update
      post "/:id/share", FeedbackController, :share
      get "/:id/revisions", FeedbackController, :revisions
    end

    # WP-15: portal feedback (shared rows about the household's players).
    scope "/portal/players", SportsCoachBookingsWeb.Portal.Feedback do
      pipe_through [:portal_session, :require_customer]

      get "/:player_id/feedback", FeedbackController, :index
    end

    scope "/portal", SportsCoachBookingsWeb.Portal.Schedule do
      pipe_through :portal_session

      get "/sessions", SessionsController, :index
      get "/sessions/:id", SessionsController, :show
    end

    # WP-02 customer auth (host-scoped). Registration/login/logout/reset and
    # invite acceptance are unauthenticated, so rate-limit them per IP + email
    # + tenant (WP-19).
    scope "/portal", SportsCoachBookingsWeb.Portal do
      pipe_through [:portal_session, :rate_limit_auth]

      post "/registrations", Account.RegistrationsController, :create
      post "/session", Account.SessionController, :create
      delete "/session", Account.SessionController, :delete
      post "/confirmation", Account.ConfirmationsController, :create
      post "/confirmation/resend", Account.ConfirmationsController, :resend
      post "/password_reset", Account.PasswordResetController, :create
      put "/password_reset", Account.PasswordResetController, :update

      # Household invite acceptance: tenant-resolved, session optional.
      get "/household_invites/:token", Household.InvitesController, :show
      post "/household_invites/:token/accept", Household.InvitesController, :accept
    end

    scope "/portal", SportsCoachBookingsWeb.Portal do
      pipe_through :portal_session

      get "/ping", PingController, :show
      get "/branding", BrandingController, :show

      scope "/account", Account do
        pipe_through :require_customer

        get "/", AccountController, :show
        patch "/", AccountController, :update
        put "/", AccountController, :update
        patch "/email", AccountController, :update_email
        put "/password", AccountController, :update_password
        get "/notification_preferences", AccountController, :preferences
        patch "/notification_preferences", AccountController, :update_preferences
        post "/purchase_guard", PurchaseGuardController, :show
      end

      scope "/household", Household do
        pipe_through :require_customer

        get "/", HouseholdController, :show
        post "/invites", HouseholdController, :invite
        get "/invites", HouseholdController, :invites
        delete "/members/:id", HouseholdController, :remove_member
        post "/leave", HouseholdController, :leave
        post "/transfer_primary", HouseholdController, :transfer_primary
      end

      # WP-12: the caller's own household credit balance, lots, and ledger.
      scope "/credits", Credits do
        pipe_through :require_customer

        get "/", CreditsController, :show
        get "/lots", CreditsController, :lots
        get "/ledger", CreditsController, :ledger
      end

      scope "/policies", Policies do
        get "/offerings/:offering_id", PoliciesController, :show
      end

      scope "/waivers", Waivers do
        get "/status", WaiversController, :status
        get "/versions/:id", WaiversController, :show_version
        get "/signatures/:id/pdf", WaiversController, :pdf
      end

      get "/players/:player_id/waivers", Waivers.WaiversController, :player_index
      post "/players/:player_id/waivers/:version_id/sign", Waivers.WaiversController, :sign

      get "/position_options",
          Players.PositionOptionsController,
          :index

      resources "/players", Players.PlayersController, only: [:index, :show, :create, :update]

      post "/players/:id/archive", Players.PlayersController, :archive

      put "/players/:id/profile",
          Players.PlayersController,
          :update_profile

      get "/players/:id/medical", Players.MedicalController, :show
      put "/players/:id/medical", Players.MedicalController, :update

      resources "/players/:player_id/emergency_contacts",
                Players.EmergencyContactsController,
                only: [:index, :create, :update, :delete]

      resources "/players/:player_id/authorized_pickups",
                Players.AuthorizedPickupsController,
                only: [:index, :create, :update, :delete]
    end

    # Email-a-copy is a public, account-parameterised action: rate-limit per
    # IP + tenant + submitted email (WP-19).
    scope "/portal/documents", SportsCoachBookingsWeb.Portal.Legal do
      pipe_through :portal_session

      get "/", DocumentsController, :index
      get "/:kind", DocumentsController, :show
    end

    scope "/portal/documents", SportsCoachBookingsWeb.Portal.Legal do
      pipe_through [:portal_session, :rate_limit_auth]

      post "/:kind/email", DocumentsController, :email
    end

    scope "/portal/waivers", SportsCoachBookingsWeb.Portal.Waivers do
      pipe_through [:portal_session, :rate_limit_auth]

      post "/versions/:id/email", WaiversController, :email_version
    end

    scope "/portal/catalog", SportsCoachBookingsWeb.Portal.Catalog do
      get "/venues", VenuesController, :index
      get "/offerings", OfferingsController, :index
      get "/offerings/:id/packages", OfferingsController, :packages
      get "/packages", PackagesController, :index
    end

    scope "/portal/inventory", SportsCoachBookingsWeb.Portal.Inventory do
      pipe_through :portal_session

      get "/products", ProductsController, :index
      get "/products/:id", ProductsController, :show
      get "/pickups", PickupsController, :index
    end

    # WP-13: portal cart, checkout, and order history.
    scope "/portal/cart", SportsCoachBookingsWeb.Portal.Cart do
      pipe_through [:portal_session, :require_customer]

      get "/", CartController, :show
      get "/price", CartController, :price
      post "/lines", CartController, :add_line
      patch "/lines/:id", CartController, :update_line
      delete "/lines/:id", CartController, :remove_line
      post "/discount", CartController, :apply_discount
      delete "/discount", CartController, :remove_discount
    end

    scope "/portal", SportsCoachBookingsWeb.Portal.Orders do
      pipe_through [:portal_session, :require_customer, :rate_limit_checkout]

      post "/checkout", CheckoutController, :create
      get "/orders", OrdersController, :index
      get "/orders/:id", OrdersController, :show
    end

    # WP-14: portal bookings (book, list, cancel preview/cancel, rebook).
    scope "/portal/bookings", SportsCoachBookingsWeb.Portal.Bookings do
      pipe_through [:portal_session, :require_customer]

      get "/", BookingsController, :index
      post "/", BookingsController, :create
      get "/:id/cancel-preview", BookingsController, :cancel_preview
      post "/:id/cancel", BookingsController, :cancel
      get "/:id/rebook-options", BookingsController, :rebook_options
      post "/:id/rebook", BookingsController, :rebook
    end

    # Guest reservation holds: anonymous create; the opaque token is the
    # credential for show/extend/delete; convert requires a customer session.
    scope "/portal/reservations", SportsCoachBookingsWeb.Portal.Reservations do
      post "/", ReservationsController, :create
    end

    scope "/portal/reservations", SportsCoachBookingsWeb.Portal.Reservations do
      pipe_through :reservation_token

      get "/:id", ReservationsController, :show
      post "/:id/extend", ReservationsController, :extend
      delete "/:id", ReservationsController, :delete
    end

    scope "/portal/reservations", SportsCoachBookingsWeb.Portal.Reservations do
      pipe_through [:portal_session, :require_customer, :reservation_token]

      post "/:id/convert", ReservationsController, :convert
    end
  end

  # Webhooks are unauthenticated but signature-verified by the provider.
  scope "/webhooks", SportsCoachBookingsWeb.Webhooks do
    pipe_through [:api, :rate_limit_webhook]

    # WP-04 adds /stripe.
    post "/resend", ResendController, :create
    post "/stripe", StripeController, :create
  end

  # Signed one-click unsubscribe (the token is the credential). Tenant is
  # resolved from the host.
  scope "/unsubscribe" do
    pipe_through :resolve_tenant

    get "/:token", SportsCoachBookingsWeb.UnsubscribeController, :show
    post "/:token", SportsCoachBookingsWeb.UnsubscribeController, :create
  end

  # OpenAPI document.
  scope "/api" do
    pipe_through [:api, :api_spec]

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sports_coach_bookings, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: SportsCoachBookingsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      get "/emails", SportsCoachBookingsWeb.Dev.EmailPreviewController, :index
      get "/emails/:template_key", SportsCoachBookingsWeb.Dev.EmailPreviewController, :show
    end
  end

  # Built SPA bundles with history fallback. Declared last so they never shadow
  # the API, webhook, spec, or dev routes. In local development the Vite dev
  # servers serve these instead; in production Phoenix serves the built dist.
  scope "/admin", SportsCoachBookingsWeb do
    get "/", SpaController, :admin
    get "/*path", SpaController, :admin
  end

  get "/", SportsCoachBookingsWeb.SpaController, :portal
  get "/*path", SportsCoachBookingsWeb.SpaController, :portal
end
