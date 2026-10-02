defmodule SportsCoachBookingsWeb.Portal.Account.PrivacyController do
  @moduledoc "Portal: PIPEDA household data export and erasure."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Privacy
  alias SportsCoachBookings.Privacy.Policy
  alias SportsCoachBookingsWeb.Customers.Helpers
  alias SportsCoachBookingsWeb.Portal.Auth
  alias SportsCoachBookingsWeb.PrivacyJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Privacy, as: Schemas

  tags(["portal"])

  operation(:export,
    summary: "Export all data held about the caller's household",
    description:
      "Returns accounts, players (including medical information), waivers, bookings, " <>
        "credits, and orders. Medical reads and the export are audited.",
    responses: [
      ok: {"Export", "application/json", Schemas.export()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/account/export"
  def export(conn, _params) do
    actor = Helpers.actor(conn)

    with :ok <- Policy.authorize(actor, :export, :household),
         {:ok, bundle} <- Privacy.export_household(actor) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("content-disposition", ~s(attachment; filename="household-data.json"))
      |> json(PrivacyJSON.export(bundle))
    end
  end

  operation(:erase,
    summary: "Permanently erase the caller's household",
    description:
      "Primary member only; requires the account password. Refused with 409 while the " <>
        "household has upcoming bookings or an unpaid order. Irreversible; ends the session.",
    request_body: {"Erasure", "application/json", Schemas.erase_request()},
    responses: [
      ok: {"Erased", "application/json", Schemas.erase_response()},
      forbidden: {"Forbidden or wrong password", "application/json", ErrorResponse},
      conflict: {"Erasure blocked", "application/json", ErrorResponse},
      unprocessable_entity: {"Confirmation missing", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/account/erase"
  def erase(conn, params) do
    actor = Helpers.actor(conn)

    with :ok <- Policy.authorize(actor, :erase, :household),
         :ok <- require_confirmation(params),
         {:ok, summary} <- Privacy.erase_household(actor, params["password"]) do
      conn |> Auth.log_out_customer() |> json(PrivacyJSON.erasure(summary))
    end
  end

  defp require_confirmation(%{"confirm" => "ERASE"}), do: :ok

  defp require_confirmation(_params),
    do: {:error, {:validation_error, "confirm must be the literal ERASE", %{}}}
end
