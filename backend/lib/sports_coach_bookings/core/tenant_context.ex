defmodule SportsCoachBookings.Core.TenantContext do
  @moduledoc """
  Process-level tenant context.

  Every tenant-scoped operation runs with a tenant placed in the process
  dictionary. `SportsCoachBookings.Repo.prepare_query/3` reads it to guard
  against cross-tenant queries, and `SportsCoachBookings.Repo.transaction/2`
  propagates it to Postgres via `set_config('app.tenant_id', …, true)` so the
  Row Level Security policies apply.

  The tenant is resolved from the request host by
  `SportsCoachBookingsWeb.Plugs.ResolveTenant`; it is never taken from a
  request body or header.
  """

  alias SportsCoachBookings.Core.Tenant

  @tenant_key :sports_coach_bookings_tenant
  @tenant_id_key :sports_coach_bookings_tenant_id

  @doc """
  Places a tenant (struct or id) in the current process.
  """
  @spec put_tenant(Tenant.t() | binary()) :: Tenant.t() | binary()
  def put_tenant(%Tenant{} = tenant) do
    Process.put(@tenant_key, tenant)
    Process.put(@tenant_id_key, tenant.id)
    tenant
  end

  def put_tenant(tenant_id) when is_binary(tenant_id) do
    Process.put(@tenant_id_key, tenant_id)
    tenant_id
  end

  @doc "Returns the tenant struct if one was placed, else `nil`."
  @spec get_tenant() :: Tenant.t() | nil
  def get_tenant, do: Process.get(@tenant_key)

  @doc "Returns the tenant id if one is set, else `nil`."
  @spec get_tenant_id() :: binary() | nil
  def get_tenant_id, do: Process.get(@tenant_id_key)

  @doc "Returns the tenant struct or raises."
  @spec get_tenant!() :: Tenant.t()
  def get_tenant! do
    get_tenant() || raise "no tenant in context"
  end

  @doc """
  Runs `fun` with the given tenant set, restoring the previous tenant after.

  The Postgres GUC is set per transaction by `Repo.transaction/2`; this only
  manages the process-level context.
  """
  @spec with_tenant(Tenant.t() | binary(), (-> result)) :: result when result: var
  def with_tenant(tenant_or_id, fun) when is_function(fun, 0) do
    previous_tenant = Process.get(@tenant_key)
    previous_id = Process.get(@tenant_id_key)

    put_tenant(tenant_or_id)

    try do
      fun.()
    after
      restore(@tenant_key, previous_tenant)
      restore(@tenant_id_key, previous_id)
    end
  end

  @doc "Clears the tenant from the current process."
  @spec clear() :: :ok
  def clear do
    Process.delete(@tenant_key)
    Process.delete(@tenant_id_key)
    :ok
  end

  defp restore(key, nil), do: Process.delete(key)
  defp restore(key, value), do: Process.put(key, value)
end
