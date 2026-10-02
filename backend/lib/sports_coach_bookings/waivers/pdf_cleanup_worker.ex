defmodule SportsCoachBookings.Waivers.PdfCleanupWorker do
  @moduledoc """
  Deletes stored waiver PDFs after their signatures were anonymized by a
  household erasure (`SportsCoachBookings.Privacy`).

  The job is enqueued in the erasure transaction, so it exists exactly when the
  erasure committed. Deleting a missing object succeeds, which makes retries
  safe.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :default

  alias SportsCoachBookings.Waivers.PdfStore

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: %{"keys" => keys}}) when is_list(keys) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case PdfStore.delete(key) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {key, reason}}}
      end
    end)
  end
end
