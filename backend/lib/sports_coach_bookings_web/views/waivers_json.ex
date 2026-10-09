defmodule SportsCoachBookingsWeb.WaiversJSON do
  @moduledoc "Serialises waiver templates, versions, and signatures."

  alias SportsCoachBookings.Waivers.IP
  alias SportsCoachBookings.Waivers.WaiverSignature
  alias SportsCoachBookings.Waivers.WaiverTemplate
  alias SportsCoachBookings.Waivers.WaiverVersion

  @doc "Serialises a waiver template."
  @spec template(WaiverTemplate.t(), [binary()]) :: map()
  def template(template, offering_ids \\ []) do
    %{
      id: template.id,
      name: template.name,
      scope: template.scope,
      require_resign_on_new_version: template.require_resign_on_new_version,
      active: template.active,
      offering_ids: offering_ids,
      inserted_at: datetime(template.inserted_at),
      updated_at: datetime(template.updated_at)
    }
  end

  @doc "Serialises a waiver version."
  @spec version(WaiverVersion.t()) :: map()
  def version(version) do
    %{
      id: version.id,
      waiver_template_id: version.waiver_template_id,
      version: version.version,
      body_markdown: version.body_markdown,
      status: version.status,
      published_at: datetime(version.published_at),
      content_sha256: version.content_sha256,
      immutable: WaiverVersion.immutable?(version),
      inserted_at: datetime(version.inserted_at),
      updated_at: datetime(version.updated_at)
    }
  end

  @doc "Serialises a signature."
  @spec signature(WaiverSignature.t()) :: map()
  def signature(signature) do
    %{
      id: signature.id,
      waiver_version_id: signature.waiver_version_id,
      player_id: signature.player_id,
      customer_user_id: signature.customer_user_id,
      signer_name_typed: signature.signer_name_typed,
      signer_relationship: signature.signer_relationship,
      consent_checkbox: signature.consent_checkbox,
      signed_at: datetime(signature.signed_at),
      ip: IP.format(signature.ip),
      user_agent: signature.user_agent,
      content_sha256: signature.content_sha256,
      pdf_key: signature.pdf_key,
      inserted_at: datetime(signature.inserted_at)
    }
  end

  @doc "Serialises a player's waiver status matrix."
  @spec player_status(map()) :: map()
  def player_status(status) do
    %{
      player_id: status.player_id,
      waivers: Enum.map(status.waivers, &waiver_status/1)
    }
  end

  @doc "Serialises a single template's status for a player."
  @spec waiver_status(map()) :: map()
  def waiver_status(status) do
    %{
      template_id: status.template_id,
      name: status.name,
      version_id: status.version_id,
      required: status.required,
      signed: status.signed,
      signed_version_id: status.signed_version_id,
      signed_at: datetime(status.signed_at)
    }
  end

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
