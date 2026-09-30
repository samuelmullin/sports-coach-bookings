defmodule SportsCoachBookings.Players.MedicalInfo do
  @moduledoc """
  Encrypted medical details for a player. One row per player.

  The clinical text fields are encrypted at rest with `cloak_ecto`;
  `has_medical_info` is an unencrypted boolean for quick display. Every read is
  audited by `SportsCoachBookings.Players`.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Players.Encrypted.Binary
  alias SportsCoachBookings.Players.Player

  @type t :: %__MODULE__{}

  schema "medical_info" do
    field :tenant_id, :binary_id
    field :allergies, Binary
    field :conditions, Binary
    field :medications, Binary
    field :notes, Binary
    field :has_medical_info, :boolean, default: false

    belongs_to :player, Player, foreign_key: :player_id

    timestamps()
  end

  @doc false
  def changeset(medical_info, attrs) do
    medical_info
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :player_id,
      :allergies,
      :conditions,
      :medications,
      :notes,
      :has_medical_info
    ])
    |> Ecto.Changeset.validate_required([:tenant_id, :player_id])
    |> Ecto.Changeset.unique_constraint([:tenant_id, :player_id])
    |> put_has_medical_info()
  end

  defp put_has_medical_info(changeset) do
    has_medical_info? =
      [:allergies, :conditions, :medications, :notes]
      |> Enum.any?(&present?(Ecto.Changeset.get_field(changeset, &1)))

    Ecto.Changeset.put_change(changeset, :has_medical_info, has_medical_info?)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
