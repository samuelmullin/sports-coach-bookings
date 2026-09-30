defmodule SportsCoachBookingsWeb.Portal.Account.PurchaseGuardController do
  @moduledoc """
  Stub purchase/booking guard for the portal.

  WP-13 (Commerce) and WP-14 (Bookings) call
  `SportsCoachBookings.Customers.require_confirmed/1` inside their guard path.
  Until those land, this endpoint exercises that guard so the
  `403 email_unconfirmed` contract is verifiable end to end. See
  `docs/rfcs/20260928-customers-purchase-guard-stub.md`.
  """

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookingsWeb.Customers.Helpers
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "Stub purchase guard (requires a confirmed email)",
    responses: [
      ok: {"Confirmed", "application/json", Schemas.message()},
      forbidden: {"Email unconfirmed", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/account/purchase_guard"
  def show(conn, _params) do
    with :ok <- Customers.require_confirmed(Helpers.customer_user(conn)) do
      json(conn, %{message: "confirmed"})
    end
  end
end
