defmodule SportsCoachBookings.Staff.StaffUser do
  @moduledoc """
  A global staff identity (owner, admin, or coach). Staff users are **not**
  tenant-owned: one login works across every tenant the user belongs to, via a
  cookie scoped to the configured base domain.

  Email + password with optional email confirmation. Password hashing is
  provided by `SportsCoachBookings.Staff.Password` because `mix phx.gen.auth`
  cannot run in this HTML-less app.
  """

  use SportsCoachBookings.Core.Schema

  alias SportsCoachBookings.Staff.Password

  @type t :: %__MODULE__{}

  schema "staff_users" do
    field :email, :string
    field :hashed_password, :string
    field :confirmed_at, :utc_datetime_usec
    field :password, :string, virtual: true, redact: true

    timestamps()
  end

  @doc "Registration changeset: validates email + password and hashes it."
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(staff_user, attrs) do
    staff_user
    |> Ecto.Changeset.cast(attrs, [:email, :password])
    |> Ecto.Changeset.validate_required([:email])
    |> validate_email()
    |> Ecto.Changeset.validate_length(:password, min: 12, max: 72)
    |> hash_password()
    |> Ecto.Changeset.unique_constraint(:email)
  end

  @doc "Changeset for a password reset."
  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(staff_user, attrs) do
    staff_user
    |> Ecto.Changeset.cast(attrs, [:password])
    |> Ecto.Changeset.validate_required([:password])
    |> Ecto.Changeset.validate_length(:password, min: 12, max: 72)
    |> hash_password()
  end

  @doc "Marks the account's email as confirmed."
  @spec confirm_changeset(t()) :: Ecto.Changeset.t()
  def confirm_changeset(staff_user), do: Ecto.Changeset.change(staff_user, confirmed_at: now())

  @doc "True when the email has been confirmed."
  @spec confirmed?(t()) :: boolean()
  def confirmed?(%__MODULE__{confirmed_at: nil}), do: false
  def confirmed?(%__MODULE__{}), do: true

  @doc "True when `password` matches the stored hash."
  @spec valid_password?(t(), binary()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hash}, password) when is_binary(password),
    do: Password.verify(password, hash)

  def valid_password?(_staff_user, _password), do: false

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    Ecto.Changeset.put_change(changeset, :hashed_password, Password.hash(password))
  end

  defp hash_password(changeset), do: changeset

  defp validate_email(changeset) do
    changeset
    |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/i,
      message: "must be a valid email address"
    )
    |> Ecto.Changeset.validate_length(:email, max: 160)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
