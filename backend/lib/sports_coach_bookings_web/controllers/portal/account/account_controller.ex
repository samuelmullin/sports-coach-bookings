defmodule SportsCoachBookingsWeb.Portal.Account.AccountController do
  @moduledoc "Customer self-service account: profile, email, password, preferences."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.Policy
  alias SportsCoachBookingsWeb.Customers.Helpers
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "Get the current customer's profile",
    responses: [
      ok: {"Account", "application/json", Schemas.session_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/account"
  def show(conn, _params) do
    with :ok <- Policy.authorize(Helpers.actor(conn), :get, :account) do
      json(conn, %{customer_user: CustomersJSON.customer_user(Helpers.customer_user(conn))})
    end
  end

  operation(:update,
    summary: "Update the current customer's name and phone",
    request_body: {"Profile", "application/json", Schemas.account_update_request()},
    responses: [
      ok: {"Account", "application/json", Schemas.session_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/portal/account"
  def update(conn, params) do
    with :ok <- Policy.authorize(Helpers.actor(conn), :update, :account),
         {:ok, customer_user} <-
           Customers.update_profile(
             Helpers.customer_user(conn),
             Helpers.body(params, "customer_user")
           ) do
      json(conn, %{customer_user: CustomersJSON.customer_user(customer_user)})
    end
  end

  operation(:update_email,
    summary: "Change the current customer's email (starts re-confirmation)",
    request_body: {"Email", "application/json", Schemas.email_change_request()},
    responses: [
      ok: {"Account", "application/json", Schemas.session_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/portal/account/email"
  def update_email(conn, params) do
    with :ok <- Policy.authorize(Helpers.actor(conn), :update_email, :account),
         {:ok, %{customer_user: customer_user}} <-
           Customers.change_email(
             Helpers.customer_user(conn),
             Helpers.body(params, "customer_user")
           ) do
      json(conn, %{customer_user: CustomersJSON.customer_user(customer_user)})
    end
  end

  operation(:update_password,
    summary: "Change the current customer's password",
    request_body: {"Password", "application/json", Schemas.password_change_request()},
    responses: [
      ok: {"Account", "application/json", Schemas.session_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PUT /api/portal/account/password"
  def update_password(conn, params) do
    with :ok <- Policy.authorize(Helpers.actor(conn), :update_password, :account),
         {:ok, customer_user} <-
           Customers.update_password(
             Helpers.customer_user(conn),
             Helpers.body(params, "customer_user")
           ) do
      json(conn, %{customer_user: CustomersJSON.customer_user(customer_user)})
    end
  end

  operation(:preferences,
    summary: "Get notification preferences",
    responses: [
      ok: {"Preferences", "application/json", Schemas.notification_preferences()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/account/notification_preferences"
  def preferences(conn, _params) do
    with :ok <- Policy.authorize(Helpers.actor(conn), :notification_preferences, :account) do
      json(conn, Customers.notification_preferences(Helpers.customer_user(conn)))
    end
  end

  operation(:update_preferences,
    summary: "Update notification preferences (WP-05 stub)",
    request_body: {"Preferences", "application/json", Schemas.notification_preferences_update()},
    responses: [
      ok: {"Preferences", "application/json", Schemas.notification_preferences()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/portal/account/notification_preferences"
  def update_preferences(conn, params) do
    with :ok <- Policy.authorize(Helpers.actor(conn), :notification_preferences, :account),
         {:ok, preferences} <-
           Customers.update_notification_preferences(
             Helpers.customer_user(conn),
             Helpers.body(params, "customer_user")
           ) do
      json(conn, preferences)
    end
  end
end
