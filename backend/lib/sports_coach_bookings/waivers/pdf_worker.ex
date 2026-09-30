defmodule SportsCoachBookings.Waivers.PdfWorker do
  @moduledoc """
  Renders the PDF snapshot for a signature and stores its object key.

  Runs with tenant context; the renderer is pluggable via
  `SportsCoachBookings.Waivers.PdfRenderer.impl/0`. Idempotent: re-running
  overwrites the same `pdf_key`.
  """

  use SportsCoachBookings.Core.TenantWorker, queue: :default

  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Waivers.PdfRenderer
  alias SportsCoachBookings.Waivers.WaiverSignature

  @impl SportsCoachBookings.Core.TenantWorker
  def perform_with_tenant(%Oban.Job{args: %{"signature_id" => signature_id}}) do
    case Repo.with_tenant_tx(fn -> render_signature(signature_id) end) do
      {:ok, :ok} -> :ok
      {:ok, {:ok, _signature}} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp render_signature(signature_id) do
    case Repo.get(WaiverSignature, signature_id) do
      nil -> :ok
      signature -> render(signature)
    end
  end

  defp render(signature) do
    with {:ok, key} <- PdfRenderer.impl().render(signature) do
      signature
      |> Ecto.Changeset.change(pdf_key: key)
      |> Repo.update()
    end
  end
end
