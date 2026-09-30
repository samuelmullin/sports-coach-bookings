defmodule SportsCoachBookings.Policies.TenantCreatedSubscriber do
  @moduledoc """
  Seeds a sensible default cancellation policy when a tenant is created.

  Subscribed to `tenant.created` in `config :sports_coach_bookings,
  :event_subscribers`. Delivery is at-least-once, so seeding is idempotent: if
  the tenant already has a default policy it is left untouched.
  """

  alias SportsCoachBookings.Policies

  @doc "Handles `tenant.created` by seeding the tenant's default policy."
  @spec handle_event(String.t(), map()) :: :ok | {:error, term()}
  def handle_event("tenant.created", payload) do
    case tenant_id(payload) do
      nil ->
        {:error, :missing_tenant_id}

      tenant_id ->
        case Policies.seed_default_policy(tenant_id) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def handle_event(_name, _payload), do: :ok

  defp tenant_id(payload) do
    Map.get(payload, "tenant_id") || Map.get(payload, :tenant_id)
  end
end
