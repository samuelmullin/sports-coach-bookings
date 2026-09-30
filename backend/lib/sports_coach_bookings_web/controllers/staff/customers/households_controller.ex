defmodule SportsCoachBookingsWeb.Staff.Customers.HouseholdsController do
  @moduledoc "Staff (owner/admin) household search and detail."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.Policy
  alias SportsCoachBookingsWeb.CustomersJSON
  alias SportsCoachBookingsWeb.Schemas.Customers, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["staff"])

  operation(:index,
    summary: "Search/list households",
    parameters: [
      q: [in: :query, type: :string, required: false, description: "name or member email"],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Households", "application/json", Schemas.household_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/households"
  def index(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :list, :household) do
      %{data: data, next_cursor: cursor} = Customers.page_households(term(params), params)
      json(conn, CustomersJSON.collection(Enum.map(data, &CustomersJSON.household/1), cursor))
    end
  end

  operation(:show,
    summary: "Get a household with its members",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Household", "application/json", Schemas.household_detail()},
      not_found: {"Not found", "application/json", ErrorResponse},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/households/:id"
  def show(conn, %{"id" => id}) do
    with :ok <- Policy.authorize(actor(conn), :get, :household),
         {:ok, household} <- fetch(id) do
      json(conn, CustomersJSON.household_detail(household))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp fetch(id) do
    case Customers.household_detail(id) do
      nil -> {:error, :not_found}
      household -> {:ok, household}
    end
  end

  defp term(params) do
    Map.get(params, "q") || Map.get(params, "query")
  end
end
