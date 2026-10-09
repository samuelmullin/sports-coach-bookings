defmodule SportsCoachBookings.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Tests that touch the database run inside the SQL sandbox, so changes are
  reverted at the end of every test. Use `put_tenant/1` to place a tenant in
  context and activate the RLS GUC before touching tenant-owned rows.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias SportsCoachBookings.Core.Tenant
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Repo

  using do
    quote do
      alias SportsCoachBookings.Core.{CustomerActor, StaffActor, Tenant, TenantContext}
      alias SportsCoachBookings.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import SportsCoachBookings.DataCase
      import SportsCoachBookings.Factory
      import SportsCoachBookings.TenantIsolation
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc """
  Places a tenant in the process context and activates the Postgres RLS GUC for
  the current sandbox transaction. Use before reading/writing tenant-owned rows.
  """
  def put_tenant(%Tenant{} = tenant) do
    TenantContext.put_tenant(tenant)
    Repo.set_tenant_guc(tenant.id)
    tenant
  end

  @doc """
  Runs `fun` with `tenant` in context, setting the RLS GUC for the transaction.
  """
  def with_tenant(%Tenant{} = tenant, fun) when is_function(fun, 0) do
    TenantContext.with_tenant(tenant, fn ->
      Repo.set_tenant_guc(tenant.id)
      fun.()
    end)
  end

  @doc """
  Runs `fun` with only the process-level tenant context set and the sandbox
  transaction's RLS GUC deliberately empty.

  Use this for regression tests of public context functions: a correct public
  function opens `Repo.with_tenant_tx/2` and can see its tenant's rows; a stray
  direct query outside that boundary sees no rows. The prior process context and
  GUC are restored afterward.
  """
  def with_tenant_context_only(%Tenant{} = tenant, fun) when is_function(fun, 0) do
    previous_tenant = TenantContext.get_tenant()
    previous_tenant_id = TenantContext.get_tenant_id()
    previous_guc = current_tenant_guc()

    TenantContext.put_tenant(tenant)
    set_tenant_guc_value("")

    try do
      fun.()
    after
      TenantContext.clear()
      if previous_tenant, do: TenantContext.put_tenant(previous_tenant)

      if is_nil(previous_tenant) and previous_tenant_id,
        do: TenantContext.put_tenant(previous_tenant_id)

      set_tenant_guc_value(previous_guc)
    end
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  defp current_tenant_guc do
    %{rows: [[value]]} =
      Repo.query!("SELECT current_setting('app.tenant_id', true)", [], skip_tenant: true)

    value || ""
  end

  defp set_tenant_guc_value(value) do
    Repo.query!("SELECT set_config('app.tenant_id', $1, true)", [value], skip_tenant: true)
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
