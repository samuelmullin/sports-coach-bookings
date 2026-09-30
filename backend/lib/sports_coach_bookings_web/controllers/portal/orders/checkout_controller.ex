defmodule SportsCoachBookingsWeb.Portal.Orders.CheckoutController do
  @moduledoc "Portal: turn the caller's cart into a hosted-checkout order."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Commerce
  alias SportsCoachBookings.Commerce.Policy
  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Customers
  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookingsWeb.CommerceJSON
  alias SportsCoachBookingsWeb.Schemas.Commerce, as: Schemas
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse

  tags(["portal"])

  operation(:create,
    summary: "Check out the caller's cart",
    responses: [
      created: {"Checkout", "application/json", Schemas.checkout_result()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Checkout error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/portal/checkout"
  def create(conn, _params) do
    actor = conn.assigns[:current_customer_actor]

    with :ok <- Policy.authorize(actor, :checkout, :order),
         :ok <- require_confirmed(actor),
         {:ok, result} <- Commerce.checkout(actor, actor.household_id) do
      conn
      |> put_status(:created)
      |> json(CommerceJSON.checkout(result))
    end
  end

  defp require_confirmed(%CustomerActor{customer_user: %CustomerUser{} = user}),
    do: Customers.require_confirmed(user)

  defp require_confirmed(_actor), do: :ok
end
