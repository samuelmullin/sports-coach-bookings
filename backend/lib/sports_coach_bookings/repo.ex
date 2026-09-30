defmodule SportsCoachBookings.Repo do
  @moduledoc """
  The application's Ecto repo.

  Two tenancy-related hooks live here:

    * `prepare_query/3` raises `SportsCoachBookings.Core.MissingTenantError`
      when a tenant-scoped schema (one that `use`s
      `SportsCoachBookings.Core.TenantSchema`) is queried with no tenant in
      context and without `skip_tenant: true`.

    * `with_tenant_tx/2` sets the Postgres GUC `app.tenant_id` for the duration
      of the transaction when a tenant is in context, activating the Row Level
      Security policies. Tenant-scoped writes MUST use it (or `transaction/2`
      directly) — see `docs/conventions.md`.
  """

  use Ecto.Repo,
    otp_app: :sports_coach_bookings,
    adapter: Ecto.Adapters.Postgres

  alias Ecto.Adapters.SQL
  alias SportsCoachBookings.Core.MissingTenantError
  alias SportsCoachBookings.Core.TenantContext

  @impl true
  def prepare_query(operation, query, opts) do
    if tenant_scoped?(query) and opts[:skip_tenant] != true and
         is_nil(TenantContext.get_tenant_id()) do
      raise MissingTenantError, schema: source_schema(query), operation: operation
    end

    {query, opts}
  end

  @impl true
  def default_options(_operation), do: [timeout: 15_000]

  @doc """
  Runs `fun` (arity 0) or an `Ecto.Multi` in a transaction that carries the
  tenant.

  When a tenant is in the process context, the transaction begins by setting
  `app.tenant_id` locally so Postgres RLS policies apply. This is the preferred
  entry point for all tenant-scoped writes.
  """
  @spec with_tenant_tx((-> result) | Ecto.Multi.t(), keyword()) ::
          {:ok, result} | {:error, term()}
        when result: var
  def with_tenant_tx(fun, opts \\ [])

  def with_tenant_tx(fun, opts) when is_function(fun, 0) do
    transaction(
      fn ->
        set_tenant_guc(TenantContext.get_tenant_id())
        fun.()
      end,
      opts
    )
  end

  def with_tenant_tx(%Ecto.Multi{} = multi, opts) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:__set_tenant__, fn _repo, _changes ->
      set_tenant_guc(TenantContext.get_tenant_id())
      {:ok, :ok}
    end)
    |> Ecto.Multi.merge(fn _changes -> multi end)
    |> transaction(opts)
  end

  @doc """
  Sets the Postgres `app.tenant_id` GUC for the current transaction.

  Pass the tenant id (string/none). No-op when `tenant_id` is `nil`. Exposed for
  test helpers that already run inside the sandbox transaction.
  """
  @spec set_tenant_guc(binary() | nil) :: :ok
  def set_tenant_guc(nil), do: :ok

  def set_tenant_guc(tenant_id) do
    SQL.query!(__MODULE__, "SELECT set_config('app.tenant_id', $1, true)", [
      tenant_id
    ])

    :ok
  end

  defp tenant_scoped?(%Ecto.Query{} = query) do
    sources = [query.from && query.from.source | Enum.map(query.joins, & &1.source)]
    Enum.any?(sources, &tenant_schema?/1)
  end

  defp tenant_scoped?(_), do: false

  defp tenant_schema?({a, b}), do: tenant_schema?(a) or tenant_schema?(b)

  defp tenant_schema?(schema) when is_atom(schema) and not is_nil(schema) do
    Code.ensure_loaded?(schema) and
      function_exported?(schema, :__tenant_scoped__, 0) and
      schema.__tenant_scoped__()
  end

  defp tenant_schema?(_), do: false

  defp source_schema(%Ecto.Query{from: %{source: source}}), do: schema_from_source(source)
  defp source_schema(_), do: nil

  defp schema_from_source({_a, b}) when is_atom(b) and not is_nil(b), do: b
  defp schema_from_source({a, _}) when is_atom(a) and not is_nil(a), do: a
  defp schema_from_source(_), do: nil
end
