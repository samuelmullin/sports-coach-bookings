defmodule SportsCoachBookings.Inventory.Policy do
  @moduledoc """
  Authorization for products, stock, and pickups. Owned by WP-08.

  | Actor | Products / variants / stock | Fulfillments | Portal shop |
  |---|---|---|---|
  | Owner / admin | Full CRUD, receive/adjust, reorder, upload | Read + mark ready/picked up | Read |
  | Coach | Read-only | Read + mark ready/picked up | Read |
  | Household manager | — | Own order pickup status | List + view products |
  | Anonymous | — | — | List + view products |

  Portal actions (`:list_public`, `:view_public` on `:product`,
  `:view_pickup_status` on `:fulfillment`) are open to anonymous callers; the
  pickup status itself is scoped to the caller's household by the context.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Core.StaffActor

  @resources [:product, :product_variant, :stock_level, :stock_movement, :fulfillment]

  @coach_actions [
    :list,
    :get,
    :list_variants,
    :list_movements,
    :list_stock_levels,
    :list_fulfillments,
    :mark_ready,
    :mark_picked_up,
    :upload,
    :list_public,
    :view_public
  ]

  ## Owner / admin: full control within their tenant.

  def authorize(%StaffActor{role: role}, _action, _resource) when role in [:owner, :admin],
    do: :ok

  ## Coach: read-only plus pickup-queue operations.

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in @coach_actions and resource in @resources,
      do: :ok

  ## Anonymous + household managers: public shop browsing.

  def authorize(actor, action, :product) when action in [:list_public, :view_public] do
    case actor do
      nil -> :ok
      %CustomerActor{} -> :ok
      _ -> {:error, :forbidden}
    end
  end

  def authorize(%CustomerActor{}, :view_pickup_status, :fulfillment), do: :ok

  ## Default: deny.

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "The actions the policy understands. Used by tests and tooling."
  @spec actions() :: [atom()]
  def actions do
    Enum.uniq(
      @coach_actions ++
        [
          :create,
          :update,
          :archive,
          :reorder,
          :receive_stock,
          :adjust_stock,
          :list_public,
          :view_public,
          :view_pickup_status
        ]
    )
  end

  @doc "The resources the policy understands. Used by tests and tooling."
  @spec resources() :: [atom()]
  def resources, do: @resources

  @doc "The actions a coach is allowed."
  @spec coach_actions() :: [atom()]
  def coach_actions, do: @coach_actions
end
