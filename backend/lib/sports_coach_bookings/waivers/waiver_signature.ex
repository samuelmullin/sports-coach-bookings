defmodule SportsCoachBookings.Waivers.WaiverSignature do
  @moduledoc """
  A household manager's signature of a specific waiver version for a player.
  Owned by WP-07.

  `content_sha256` must equal the signed version's hash; the context rejects a
  client-supplied hash that does not match the current published version.
  At most one signature per `(version, player)`.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Waivers.IP
  alias SportsCoachBookings.Waivers.WaiverVersion

  @type t :: %__MODULE__{}

  schema "waiver_signatures" do
    field :tenant_id, :binary_id
    belongs_to :waiver_version, WaiverVersion
    # Cross-context references (Players + Customers); plain uuids, no FK.
    field :player_id, :binary_id
    field :customer_user_id, :binary_id
    field :signer_name_typed, :string
    field :signer_relationship, :string
    field :consent_checkbox, :boolean, default: false
    field :signed_at, :utc_datetime_usec
    field :ip, IP
    field :user_agent, :string
    field :content_sha256, :string
    field :pdf_key, :string

    timestamps()
  end

  @doc false
  def changeset(signature, attrs) do
    signature
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :waiver_version_id,
      :player_id,
      :customer_user_id,
      :signer_name_typed,
      :signer_relationship,
      :consent_checkbox,
      :signed_at,
      :ip,
      :user_agent,
      :content_sha256,
      :pdf_key
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :waiver_version_id,
      :player_id,
      :customer_user_id,
      :signer_name_typed,
      :signed_at,
      :ip,
      :user_agent,
      :content_sha256
    ])
    |> Ecto.Changeset.validate_acceptance(:consent_checkbox,
      message: "must be accepted to sign"
    )
    |> Ecto.Changeset.validate_length(:signer_name_typed, min: 1, max: 200)
    |> Ecto.Changeset.unique_constraint([:waiver_version_id, :player_id])
  end
end
