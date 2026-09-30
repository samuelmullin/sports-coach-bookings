defmodule SportsCoachBookings.Customers.HouseholdInvite do
  @moduledoc """
  A pending invitation for another adult to co-manage a household.
  Tenant-owned (RLS).

  Invitations are single-use and expire after 7 days. Only the SHA-256 hash of
  the token is stored; the plaintext token is what the invitee receives.
  """

  use SportsCoachBookings.Core.TenantSchema

  @type t :: %__MODULE__{}

  @validity_days 7

  schema "household_invites" do
    field :tenant_id, :binary_id
    field :email, :string
    field :relationship, :string
    field :token_hash, :string
    field :invited_by, :binary_id
    field :expires_at, :utc_datetime_usec
    field :accepted_at, :utc_datetime_usec

    belongs_to :household, SportsCoachBookings.Customers.Household

    timestamps()
  end

  @doc false
  def changeset(invite, attrs) do
    invite
    |> Ecto.Changeset.cast(attrs, [
      :tenant_id,
      :household_id,
      :email,
      :relationship,
      :token_hash,
      :invited_by,
      :expires_at,
      :accepted_at
    ])
    |> Ecto.Changeset.validate_required([
      :tenant_id,
      :household_id,
      :email,
      :token_hash,
      :expires_at
    ])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/i)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :token_hash])
  end

  @doc "True when the invite has expired."
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: true

  def expired?(%__MODULE__{expires_at: expires_at}),
    do: DateTime.compare(expires_at, now()) != :gt

  @doc "True when the invite has already been accepted."
  @spec accepted?(t()) :: boolean()
  def accepted?(%__MODULE__{accepted_at: nil}), do: false
  def accepted?(%__MODULE__{}), do: true

  @doc "Number of days an invite stays valid."
  @spec validity_days() :: pos_integer()
  def validity_days, do: @validity_days

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
