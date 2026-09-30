defmodule SportsCoachBookings.Core.TenantSchema do
  @moduledoc """
  Marks a schema as tenant-owned.

  A tenant-owned schema has a `tenant_id` column protected by a Row Level
  Security policy (see `SportsCoachBookings.Core.Migration.tenant_table/3`).
  `SportsCoachBookings.Repo.prepare_query/3` refuses to run queries against
  these schemas unless a tenant is set in the process (or `skip_tenant: true`
  is passed explicitly).

  Usage:

      use SportsCoachBookings.Core.TenantSchema

      schema "widgets" do
        field :tenant_id, :binary_id
        field :name, :string
        timestamps()
      end
  """

  defmacro __using__(_opts) do
    quote do
      use SportsCoachBookings.Core.Schema

      @doc false
      def __tenant_scoped__, do: true
    end
  end
end
