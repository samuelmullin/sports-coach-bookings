defmodule SportsCoachBookings.Legal.TenantCreatedSubscriber do
  @moduledoc """
  Seeds the default Terms of Service and Privacy Policy when a tenant is
  created. Subscribed to `tenant.created` in
  `config :sports_coach_bookings, :event_subscribers`.

  Delivery is at-least-once, so seeding is idempotent: a kind that already has
  an active document is left untouched.
  """

  alias SportsCoachBookings.Legal

  @doc "Handles `tenant.created` by seeding the tenant's default legal documents."
  @spec handle_event(String.t(), map()) :: :ok | {:error, term()}
  def handle_event("tenant.created", payload) do
    case tenant_id(payload) do
      nil ->
        {:error, :missing_tenant_id}

      tenant_id ->
        case Legal.seed_defaults(tenant_id) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def handle_event(_name, _payload), do: :ok

  defp tenant_id(payload), do: Map.get(payload, "tenant_id") || Map.get(payload, :tenant_id)
end
