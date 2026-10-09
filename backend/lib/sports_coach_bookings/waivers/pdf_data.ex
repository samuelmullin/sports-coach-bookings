defmodule SportsCoachBookings.Waivers.PdfData do
  @moduledoc false

  import Ecto.Query

  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Tenancy.Branding
  alias SportsCoachBookings.Waivers.WaiverVersion

  @spec load(map()) :: {:ok, map()} | {:error, :waiver_version_not_found}
  def load(signature) do
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
        tenant = Tenancy.get_tenant(signature.tenant_id)
        branding = if tenant, do: Tenancy.get_branding(tenant), else: %Branding{}

        {:ok,
         %{
           tenant_name: if(tenant, do: tenant.name, else: ""),
           template_name: version.waiver_template.name,
           version: version.version,
           body_markdown: version.body_markdown,
           player_name: player_name(signature.player_id),
           signature: signature,
           branding: %{
             logo_url: Branding.asset_url(branding.logo_key),
             primary_color: branding.primary_color || "#1d4ed8",
             text_color: branding.text_color || "#111827",
             font_family: branding.font_family || "system"
           }
         }}
    end
  end

  defp player_name(player_id) do
    case Players.fetch_player(player_id) do
      {:ok, player} -> "#{player.first_name} #{player.last_name}"
      _ -> "(player record removed)"
    end
  end
end
