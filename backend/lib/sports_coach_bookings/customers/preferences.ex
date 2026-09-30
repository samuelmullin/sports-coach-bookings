defmodule SportsCoachBookings.Customers.Preferences do
  @moduledoc """
  Notification-preference seam for customer users.

  WP-05 (`SportsCoachBookings.Notifications.Preferences`) owns the real
  preference store and is not merged. Until it lands, this module returns
  documented defaults and accepts (but ignores) updates. When WP-05 ships, set

      config :sports_coach_bookings, :customer_preferences_module, Notifications.Preferences

  and this module delegates. See
  `docs/rfcs/20260928-customers-notifications-seam.md`.
  """

  alias SportsCoachBookings.Customers.CustomerUser

  @default %{marketing_opt_in: false, operational: true, transactional: true}

  @doc "The customer's notification preferences (defaults until WP-05 is merged)."
  @spec get(CustomerUser.t()) :: map()
  def get(%CustomerUser{} = customer_user) do
    case delegate_module() do
      nil -> @default
      module -> module.get(customer_user)
    end
  end

  @doc """
  Updates notification preferences. Returns `{:ok, preferences}`.

  `transactional` and `operational` are always on; only `marketing_opt_in` is
  user-controlled (CASL express consent).
  """
  @spec update(CustomerUser.t(), map()) :: {:ok, map()}
  def update(%CustomerUser{} = customer_user, attrs) do
    case delegate_module() do
      nil -> {:ok, merge(attrs)}
      module -> module.update(customer_user, attrs)
    end
  end

  @doc "The default preference values."
  @spec defaults() :: map()
  def defaults, do: @default

  defp merge(attrs) do
    marketing = Map.get(attrs, "marketing_opt_in") || Map.get(attrs, :marketing_opt_in)

    %{@default | marketing_opt_in: truthy?(marketing)}
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp delegate_module do
    module = Application.get_env(:sports_coach_bookings, :customer_preferences_module)

    if is_atom(module) and not is_nil(module) and Code.ensure_loaded?(module) and
         function_exported?(module, :get, 1) do
      module
    end
  end
end
