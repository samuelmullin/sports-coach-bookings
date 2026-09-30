defmodule SportsCoachBookingsWeb.Portal.Inventory.PickupsController do
  @moduledoc "Portal: pickup status for the caller's own orders."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Inventory
  alias SportsCoachBookings.Inventory.Policy
  alias SportsCoachBookingsWeb.InventoryJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Inventory, as: Schemas

  tags(["portal"])

  operation(:index,
    summary: "List pickup status for the household's orders",
    responses: [
      ok: {"Pickups", "application/json", Schemas.pickup_list()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/inventory/pickups"
  def index(conn, _params) do
    actor = conn.assigns[:current_customer_actor]

    with :ok <- Policy.authorize(actor, :view_pickup_status, :fulfillment) do
      pickups =
        actor.household_id
        |> Inventory.pickup_status_for_household()
        |> Enum.map(&InventoryJSON.pickup/1)

      json(conn, InventoryJSON.collection(pickups))
    end
  end
end
