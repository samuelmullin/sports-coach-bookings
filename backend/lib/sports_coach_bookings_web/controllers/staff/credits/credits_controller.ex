defmodule SportsCoachBookingsWeb.Staff.Credits.CreditsController do
  @moduledoc "Staff: household credit balance, lots, ledger, grant, and adjust."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Credits
  alias SportsCoachBookings.Credits.Policy
  alias SportsCoachBookingsWeb.CreditsJSON
  alias SportsCoachBookingsWeb.Schemas.Credits, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:show,
    summary: "Household credit balance",
    parameters: [household_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Balance", "application/json", Schemas.balance_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/households/:household_id/credits"
  def show(conn, %{"household_id" => household_id}) do
    with :ok <- authorize(conn, :list, :credit_lot) do
      json(conn, CreditsJSON.balance_response(Credits.balance(household_id)))
    end
  end

  operation(:lots,
    summary: "Household credit lots",
    parameters: [
      household_id: [in: :path, type: :string, required: true],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Lots", "application/json", Schemas.lot_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/households/:household_id/credits/lots"
  def lots(conn, %{"household_id" => household_id} = params) do
    with :ok <- authorize(conn, :list, :credit_lot) do
      %{data: data, next_cursor: cursor} = Credits.page_lots(household_id, params)
      json(conn, CreditsJSON.collection(Enum.map(data, &CreditsJSON.lot/1), cursor))
    end
  end

  operation(:ledger,
    summary: "Household credit ledger history",
    parameters: [
      household_id: [in: :path, type: :string, required: true],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Ledger", "application/json", Schemas.ledger_entry_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/households/:household_id/credits/ledger"
  def ledger(conn, %{"household_id" => household_id} = params) do
    with :ok <- authorize(conn, :list_ledger, :credit_ledger_entry) do
      %{data: data, next_cursor: cursor} = Credits.page_ledger(household_id, params)
      json(conn, CreditsJSON.collection(Enum.map(data, &CreditsJSON.entry/1), cursor))
    end
  end

  operation(:grant,
    summary: "Grant complimentary credits to a household",
    parameters: [household_id: [in: :path, type: :string, required: true]],
    request_body: {"Grant", "application/json", Schemas.grant_request()},
    responses: [
      created: {"Lot", "application/json", Schemas.lot()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/households/:household_id/credits/grant"
  def grant(conn, %{"household_id" => household_id} = params) do
    with :ok <- authorize(conn, :grant, :credit_lot),
         {:ok, lot} <-
           Credits.grant_complimentary(actor(conn), household_id, body(params, "grant")) do
      conn
      |> put_status(:created)
      |> json(CreditsJSON.lot(lot))
    end
  end

  operation(:adjust,
    summary: "Adjust a household's credits",
    parameters: [household_id: [in: :path, type: :string, required: true]],
    request_body: {"Adjustment", "application/json", Schemas.adjust_request()},
    responses: [
      created: {"Lot", "application/json", Schemas.lot()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/households/:household_id/credits/adjust"
  def adjust(conn, %{"household_id" => household_id} = params) do
    attrs = body(params, "adjustment")

    with :ok <- authorize(conn, :adjust, :credit_lot),
         {:ok, lot} <-
           Credits.adjust(actor(conn), household_id, lot_id(attrs), attrs) do
      conn
      |> put_status(:created)
      |> json(CreditsJSON.lot(lot))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  defp lot_id(attrs), do: Map.get(attrs, "lot_id") || Map.get(attrs, :lot_id)

  defp body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _ -> Map.drop(params, ["household_id", "id", "cursor", "limit", key])
    end
  end
end
