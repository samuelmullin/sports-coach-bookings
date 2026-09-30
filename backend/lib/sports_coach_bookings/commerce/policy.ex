defmodule SportsCoachBookings.Commerce.Policy do
  @moduledoc """
  Authorization for carts, orders, checkouts, and refunds. Owned by WP-13.

  | Actor | Carts / checkout | Orders | Refunds / offline orders |
  |---|---|---|---|
  | Owner / admin | Read | List + detail | Full (refund, create offline) |
  | Coach | — | List + detail (read-only) | — |
  | Household manager | Own cart, checkout, view own orders | Own orders only | — |
  | Anonymous | — | — | — |

  Portal actions are customer-only and scoped to the caller's household by the
  context; the policy only decides whether the actor may perform the action at
  all (the household filter is applied in `SportsCoachBookings.Commerce`).
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor

  @resources [:cart, :cart_line, :order, :order_line]

  @customer_actions [
    :view_cart,
    :add_line,
    :update_line,
    :remove_line,
    :apply_discount,
    :remove_discount,
    :price,
    :checkout,
    :list_own_orders,
    :view_own_order
  ]

  @coach_actions [:list, :get]
  @manager_only_actions [:refund, :create_offline, :list, :get]

  ## Owner / admin: full control within their tenant.

  def authorize(%StaffActor{role: role}, _action, resource)
      when role in [:owner, :admin] and resource in @resources,
      do: :ok

  ## Coach: read-only order access.

  def authorize(%StaffActor{role: :coach}, action, :order) when action in @coach_actions, do: :ok

  ## Household managers: their own cart and orders; checkout.

  def authorize(%CustomerActor{}, action, resource)
      when action in @customer_actions and resource in [:cart, :cart_line, :order],
      do: :ok

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions, do: Enum.uniq(@customer_actions ++ @manager_only_actions)

  @doc "The resources the policy understands. Used by tests and tooling."
  @spec resources() :: [atom()]
  def resources, do: @resources

  @doc "The actions a coach is allowed."
  @spec coach_actions() :: [atom()]
  def coach_actions, do: @coach_actions

  @doc "The actions a household manager is allowed."
  @spec customer_actions() :: [atom()]
  def customer_actions, do: @customer_actions
end
