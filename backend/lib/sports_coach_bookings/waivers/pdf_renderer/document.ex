defmodule SportsCoachBookings.Waivers.PdfRenderer.Document do
  @moduledoc """
  Production `SportsCoachBookings.Waivers.PdfRenderer`: lays the signed waiver
  out with `SportsCoachBookings.Waivers.PdfDocument` and writes it to
  `SportsCoachBookings.Waivers.PdfStore`.

  Objects are keyed `<tenant_id>/waivers/<signature_id>.pdf`, so a re-render
  overwrites the same object (idempotent) and a tenant's files share a prefix.
  Must run with the tenant in context (the Oban worker guarantees it).
  """

  @behaviour SportsCoachBookings.Waivers.PdfRenderer

  import Ecto.Query

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Waivers.PdfDocument
  alias SportsCoachBookings.Waivers.PdfStore
  alias SportsCoachBookings.Waivers.WaiverVersion

  @impl true
  def render(signature) do
    with {:ok, data} <- load(signature),
         key = key(signature),
         :ok <- PdfStore.put(key, PdfDocument.build(data)) do
      {:ok, key}
    end
  end

  @doc "The storage key for a signature's PDF."
  @spec key(%{id: binary(), tenant_id: binary()}) :: binary()
  def key(%{id: id, tenant_id: tenant_id}), do: "#{tenant_id}/waivers/#{id}.pdf"

  defp load(signature) do
    version =
      Repo.one(
        from v in WaiverVersion,
          where: v.id == ^signature.waiver_version_id,
          preload: [:waiver_template]
      )

    case version do
      nil ->
        {:error, :waiver_version_not_found}

      version ->
        {:ok,
         %{
           tenant_name: tenant_name(signature.tenant_id),
           template_name: version.waiver_template.name,
           version: version.version,
           body_markdown: version.body_markdown,
           player_name: player_name(signature.player_id),
           signature: signature
         }}
    end
  end

  defp tenant_name(tenant_id) do
    case Tenancy.get_tenant(tenant_id) do
      %{name: name} when is_binary(name) -> name
      _ -> ""
    end
  end

  defp player_name(player_id) do
    case Players.fetch_player(player_id) do
      {:ok, player} -> "#{player.first_name} #{player.last_name}"
      _ -> "(player record removed)"
    end
  end
end
