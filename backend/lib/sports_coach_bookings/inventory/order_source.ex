defmodule SportsCoachBookings.Inventory.OrderSource do
  @moduledoc """
  Resolves a household's order line ids for the portal pickup view.

  Orders are owned by Commerce (wp-13). Until it is merged, the default
  implementation is `SportsCoachBookings.Inventory.OrderSource.Stub`, which
  returns `[]`. wp-13 replaces it by setting
  `config :sports_coach_bookings, :inventory_order_source,
  SportsCoachBookings.Commerce` (a module exporting
  `order_line_ids_for_household/1`).

  See `docs/rfcs/20260928-inventory-commerce-event-contract.md`.
  """

  @callback order_line_ids_for_household(household_id :: binary()) :: [binary()]

  @doc "The configured order source implementation."
  @spec impl() :: module()
  def impl do
    Application.get_env(:sports_coach_bookings, :inventory_order_source, __MODULE__.Stub)
  end

  @doc "The order line ids belonging to `household_id`."
  @spec order_line_ids_for_household(binary()) :: [binary()]
  def order_line_ids_for_household(household_id) when is_binary(household_id) do
    impl().order_line_ids_for_household(household_id)
  end

  defmodule Stub do
    @moduledoc "Placeholder order source used until Commerce (wp-13) is merged."

    @behaviour SportsCoachBookings.Inventory.OrderSource

    @impl true
    def order_line_ids_for_household(_household_id), do: []
  end
end
