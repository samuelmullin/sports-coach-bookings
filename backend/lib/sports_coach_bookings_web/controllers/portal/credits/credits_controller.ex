defmodule SportsCoachBookingsWeb.Portal.Credits.CreditsController do
  @moduledoc "Portal: the caller's own household credit balance, lots, and ledger."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Credits.Policy
  alias SportsCoachBookingsWeb.CreditsJSON
  alias SportsCoachBookingsWeb.Schemas.Credits, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:show,
    summary: "The household's credit balance",
    responses: [
      ok: {"Balance", "application/json", Schemas.balance_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/credits"
  def show(conn, _params) do
    with :ok <- authorize(conn, :list, :credit_lot) do
      json(conn, CreditsJSON.balance_response(Credits.balance(household_id(conn))))
    end
  end

  operation(:lots,
    summary: "The household's credit lots",
    parameters: [
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Lots", "application/json", Schemas.lot_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/credits/lots"
  def lots(conn, params) do
    with :ok <- authorize(conn, :list, :credit_lot) do
      %{data: data, next_cursor: cursor} =
        Credits.page_lots(household_id(conn), Map.take(params, ["cursor", "limit"]))

      json(conn, CreditsJSON.collection(Enum.map(data, &CreditsJSON.lot/1), cursor))
    end
  end

  operation(:ledger,
    summary: "The household's credit ledger history",
    parameters: [
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Ledger", "application/json", Schemas.ledger_entry_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/credits/ledger"
  def ledger(conn, params) do
    with :ok <- authorize(conn, :list_ledger, :credit_ledger_entry) do
      %{data: data, next_cursor: cursor} =
        Credits.page_ledger(household_id(conn), Map.take(params, ["cursor", "limit"]))

      json(conn, CreditsJSON.collection(Enum.map(data, &CreditsJSON.entry/1), cursor))
    end
  end

  defp household_id(conn), do: conn.assigns[:current_customer_actor].household_id

  defp authorize(conn, action, resource) do
    Policy.authorize(conn.assigns[:current_customer_actor], action, resource)
  end
end
