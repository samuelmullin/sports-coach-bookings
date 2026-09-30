defmodule SportsCoachBookings.Core.MissingTenantError do
  @moduledoc """
  Raised when a tenant-scoped query is executed without a tenant in context.

  This is a programming error: tenant-scoped reads and writes must always run
  inside `SportsCoachBookings.Core.TenantContext.with_tenant/2` (or with an
  explicit `skip_tenant: true` when the query is justified as platform-level).
  """

  defexception [:message]

  @impl true
  def exception(opts) do
    schema = Keyword.get(opts, :schema)
    operation = Keyword.get(opts, :operation)

    message =
      "attempted #{operation || :query} on tenant-scoped schema " <>
        "#{inspect(schema)} with no tenant set. " <>
        "Wrap the call in SportsCoachBookings.Core.TenantContext.with_tenant/2 " <>
        "or pass `skip_tenant: true` with a documented justification."

    %__MODULE__{message: message}
  end
end
