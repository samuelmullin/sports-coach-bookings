defmodule SportsCoachBookings.E2EHelpers do
  @moduledoc """
  HTTP helpers shared by the wp-18 end-to-end journey tests.

  These helpers drive the real request pipeline (auth plugs, tenant resolution,
  controllers, JSON envelopes) rather than calling contexts directly, so the
  journeys exercise the same surface a browser/client would.
  """

  import Ecto.Query
  import Plug.Conn

  # The HTTP verb macros in `Phoenix.ConnTest` resolve `@endpoint` at their call
  # site, so we dispatch explicitly here (this module is not a test case).
  @endpoint SportsCoachBookingsWeb.Endpoint

  alias SportsCoachBookings.Notifications.Delivery
  alias SportsCoachBookings.Notifications.Message
  alias SportsCoachBookings.ObanHelpers
  alias SportsCoachBookings.Repo

  @password "correct horse battery staple"

  @doc "The password used for every E2E-created account."
  @spec password() :: String.t()
  def password, do: @password

  @doc "Points the conn at `{slug}.localhost`."
  def host(conn, slug), do: %{conn | host: "#{slug}.localhost"}

  @doc "Points the conn at the tenant's host."
  def tenant_host(conn, %{slug: slug}), do: host(conn, slug)

  ## JSON verbs -------------------------------------------------------------

  def json_post(conn, path, body), do: json_request(conn, :post, path, body)
  def json_patch(conn, path, body), do: json_request(conn, :patch, path, body)
  def json_put(conn, path, body), do: json_request(conn, :put, path, body)

  @doc "POSTs an empty JSON object (for bodyless actions)."
  def json_empty_post(conn, path), do: json_request(conn, :post, path, %{})

  defp json_request(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  ## Platform / auth --------------------------------------------------------

  @doc "Signs up a tenant + owner and returns the conn (with its session)."
  def signup(conn, attrs) do
    attrs = Map.merge(%{password: @password}, Map.new(attrs))
    json_post(conn, "/api/platform/signup", attrs)
  end

  @doc "Logs a staff user in on the platform host."
  def staff_login(conn, email, password \\ @password) do
    json_post(conn, "/api/platform/session", %{email: email, password: password})
  end

  @doc """
  Signs up a tenant over HTTP, drains the resulting outbox (`tenant.created`),
  and returns `%{tenant, slug, owner}` where `owner` is a logged-in staff conn.
  """
  def onboard_tenant(conn, attrs) do
    attrs = Map.new(attrs)
    slug = attrs.slug
    resp = signup(conn, attrs)

    tenant = SportsCoachBookings.Tenancy.get_tenant_by_slug(slug)
    drain_outbox()

    %{tenant: tenant, slug: slug, owner: Phoenix.ConnTest.recycle(resp) |> host(slug)}
  end

  ## Customer portal --------------------------------------------------------

  @doc "Registers a customer on the tenant host."
  def register_customer(conn, slug, email, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          first_name: "Dana",
          last_name: "Reyes",
          email: email,
          phone: "+19025550111",
          password: @password,
          accept_terms: true,
          accept_privacy: true
        },
        Map.new(overrides)
      )

    conn |> host(slug) |> json_post("/api/portal/registrations", attrs)
  end

  @doc "Logs a customer in on the tenant host."
  def customer_login(conn, slug, email, password \\ @password) do
    conn
    |> host(slug)
    |> json_post("/api/portal/session", %{email: email, password: password})
  end

  ## Webhooks ---------------------------------------------------------------

  @doc """
  Posts a Stripe/Fake webhook via the real `/webhooks/stripe` endpoint.

  The test provider (`Payments.Providers.Fake`) verifies by JSON decoding, so no
  signature header is required.
  """
  def stripe_webhook(conn, id, type, data) do
    body = Jason.encode!(%{"id" => id, "type" => type, "data" => data})

    conn
    |> put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/webhooks/stripe", body)
  end

  @doc """
  Posts a `checkout.session.completed` for the order's Fake checkout.

  The Fake provider names the checkout `cs_fake_<order_id>`, so the event is
  matched to the pending payment by `checkout_ref`.
  """
  def complete_checkout(conn, tenant, order_id, amount, currency \\ "CAD") do
    stripe_webhook(conn, "evt_completed_#{order_id}", "checkout.session.completed", %{
      "tenant_id" => tenant.id,
      "checkout_ref" => "cs_fake_#{order_id}",
      "payment_ref" => "pi_#{order_id}",
      "amount" => amount,
      "currency" => currency
    })
  end

  @doc "Posts a signed Svix/Resend webhook."
  def resend_webhook(conn, event_id, payload_map) do
    payload = Jason.encode!(payload_map)
    timestamp = Integer.to_string(System.system_time(:second))
    secret = Application.get_env(:sports_coach_bookings, :resend_webhook_secret)
    raw_key = secret |> String.replace_prefix("whsec_", "") |> Base.decode64!()
    signed_payload = event_id <> "." <> timestamp <> "." <> payload
    signature = :crypto.mac(:hmac, :sha256, raw_key, signed_payload)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("svix-id", event_id)
    |> put_req_header("svix-timestamp", timestamp)
    |> put_req_header("svix-signature", "v1," <> Base.encode64(signature))
    |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/webhooks/resend", payload)
  end

  ## Outbox -----------------------------------------------------------------

  @doc "Drains the payment + event queues (the transactional outbox)."
  def drain_outbox, do: ObanHelpers.drain_all()

  @doc "Counts pending event-outbox jobs named `name`."
  def event_count(name), do: ObanHelpers.event_count(name)

  @doc "An ISO-8601 UTC timestamp `days` from now."
  def future_iso(days) do
    DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.to_iso8601()
  end

  ## Notifications ----------------------------------------------------------

  @doc "Template keys of every queued delivery to `email` in the current tenant."
  def delivered_templates(email) do
    Repo.all(
      from d in Delivery,
        join: m in Message,
        on: m.id == d.message_id,
        where: d.email == ^email,
        select: m.template_key,
        order_by: [asc: d.inserted_at]
    )
  end

  @doc "Number of delivery rows to `email` for `template_key`."
  def delivery_count(email, template_key) do
    Repo.one(
      from d in Delivery,
        join: m in Message,
        on: m.id == d.message_id,
        where: d.email == ^email and m.template_key == ^template_key,
        select: count(d.id)
    )
  end
end
