defmodule SportsCoachBookings.Core.TenantWorker do
  @moduledoc """
  Base behaviour/macro for Oban workers that must run with tenant context.

  The job args **must** contain a `tenant_id` string. Before `perform_with_tenant/1`
  runs, the tenant is restored into the process context. Implementers define
  `perform_with_tenant/1` instead of `perform/1`.

      defmodule MyApp.Notify do
        use SportsCoachBookings.Core.TenantWorker, queue: :mailers

        @impl SportsCoachBookings.Core.TenantWorker
        def perform_with_tenant(%Oban.Job{args: args}) do
          ...
        end
      end
  """

  @callback perform_with_tenant(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()}

  defmacro __using__(opts) do
    quote do
      @behaviour SportsCoachBookings.Core.TenantWorker
      use Oban.Worker, unquote(opts)

      alias SportsCoachBookings.Core.TenantContext

      @doc false
      @impl Oban.Worker
      def perform(%Oban.Job{args: %{"tenant_id" => tenant_id}} = job) do
        TenantContext.with_tenant(tenant_id, fn ->
          perform_with_tenant(job)
        end)
      end

      def perform(%Oban.Job{args: args}) do
        {:error, {:missing_tenant_id, args}}
      end

      defoverridable perform: 1
    end
  end
end
