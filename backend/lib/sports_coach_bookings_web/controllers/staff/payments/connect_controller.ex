defmodule SportsCoachBookingsWeb.Staff.Payments.ConnectController do
  @moduledoc "Staff (owner-only) Stripe Connect status and onboarding."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Payments
  alias SportsCoachBookings.Payments.Policy
  alias SportsCoachBookingsWeb.PaymentsJSON
  alias SportsCoachBookingsWeb.SafeRedirect
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Payments, as: Schemas

  tags(["staff"])

  operation(:show,
    summary: "Get the tenant's payment provider connection status",
    responses: [
      ok: {"Connection status", "application/json", Schemas.connect_status()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/payments/connect"
  def show(conn, _params) do
    with :ok <- authorize(conn, :connect_status) do
      json(conn, PaymentsJSON.connect_status(Payments.connect_status()))
    end
  end

  operation(:onboarding,
    summary: "Start or resume provider onboarding",
    parameters: [
      return_url: [in: :query, type: :string, required: false],
      refresh_url: [in: :query, type: :string, required: false]
    ],
    responses: [
      ok: {"Onboarding redirect", "application/json", Schemas.onboarding()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Provider error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/payments/connect/onboarding"
  def onboarding(conn, params) do
    with :ok <- authorize(conn, :start_onboarding),
         {:ok, url} <-
           Payments.start_onboarding(return_url(params),
             refresh_url: refresh_url(params),
             actor: conn.assigns[:current_staff_actor]
           ) do
      json(conn, %{url: url})
    end
  end

  defp authorize(conn, action) do
    Policy.authorize(conn.assigns[:current_staff_actor], action, :provider_account)
  end

  defp return_url(params) do
    SafeRedirect.sanitize(params["return_url"]) || default_url(:payments_onboarding_return_url)
  end

  defp refresh_url(params) do
    SafeRedirect.sanitize(params["refresh_url"]) || default_url(:payments_onboarding_refresh_url)
  end

  defp default_url(key) do
    Application.get_env(
      :sports_coach_bookings,
      key,
      "https://sportscoachbookings.com/admin/settings/payments"
    )
  end
end
