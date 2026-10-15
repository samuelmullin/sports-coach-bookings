defmodule SportsCoachBookings.Waivers.PdfRenderer.Document do
  @moduledoc """
  Lightweight dev/test fallback for `SportsCoachBookings.Waivers.PdfRenderer`:
  lays the signed waiver out with `SportsCoachBookings.Waivers.PdfDocument` and
  writes it to `SportsCoachBookings.Waivers.PdfStore`.

  Objects are keyed `<tenant_id>/waivers/<signature_id>.pdf`, so a re-render
  overwrites the same object (idempotent) and a tenant's files share a prefix.
  Must run with the tenant in context (the Oban worker guarantees it).
  """

  @behaviour SportsCoachBookings.Waivers.PdfRenderer

  alias SportsCoachBookings.Waivers.PdfData
  alias SportsCoachBookings.Waivers.PdfDocument
  alias SportsCoachBookings.Waivers.PdfStore

  @impl true
  def render(signature) do
    with {:ok, data} <- PdfData.load(signature),
         key = key(signature),
         :ok <- PdfStore.put(key, PdfDocument.build(document_data(data))) do
      {:ok, key}
    end
  end

  @doc "The storage key for a signature's PDF."
  @spec key(%{id: binary(), tenant_id: binary()}) :: binary()
  def key(%{id: id, tenant_id: tenant_id}), do: "#{tenant_id}/waivers/#{id}.pdf"

  defp document_data(data) do
    %{
      tenant_name: data.tenant_name,
      template_name: data.template_name,
      version: data.version,
      body_markdown: data.body_markdown,
      player_name: data.player_name,
      signature: data.signature
    }
  end
end
