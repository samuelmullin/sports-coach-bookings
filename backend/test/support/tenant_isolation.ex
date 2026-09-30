defmodule SportsCoachBookings.TenantIsolation do
  @moduledoc """
  Test helpers that prove a tenant-owned schema cannot leak rows across tenants,
  both through Ecto scoping and through raw SQL (Row Level Security).
  """

  alias SportsCoachBookings.Repo

  @doc """
  Asserts that a tenant-owned schema is isolated.

  Inserts one row as tenant A, then checks that tenant B cannot see it either
  through `Repo` or through a raw SQL `SELECT` (which bypasses Ecto entirely and
  relies on Postgres RLS).

  `factory` is the ExMachina factory name. Extra attributes are merged in.
  Requires `insert/2` (ExMachina) and `put_tenant/1` (DataCase) in scope.
  """
  defmacro assert_tenant_isolated(schema, factory, attrs \\ []) do
    quote do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)

      put_tenant(tenant_a)
      record = insert(unquote(factory), Keyword.merge(unquote(attrs), tenant_id: tenant_a.id))

      put_tenant(tenant_b)

      assert is_nil(Repo.get(unquote(schema), record.id)),
             "tenant B could read tenant A's #{inspect(unquote(schema))} through Ecto"

      table = unquote(schema).__schema__(:source)

      assert SportsCoachBookings.TenantIsolation.raw_count(table, record.id) == 0,
             "RLS leak: raw SQL could read tenant A's #{inspect(unquote(schema))} as tenant B"

      :ok
    end
  end

  @doc "Counts rows for an id using raw SQL in the current transaction."
  @spec raw_count(String.t(), binary()) :: non_neg_integer()
  def raw_count(table, id) do
    dumped = Ecto.UUID.dump!(id)

    %Postgrex.Result{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM #{table} WHERE id = $1", [dumped])

    count
  end
end
