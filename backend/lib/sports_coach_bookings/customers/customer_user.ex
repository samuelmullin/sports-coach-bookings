defmodule SportsCoachBookings.Customers.CustomerUser do
  @moduledoc """
  A customer identity, scoped to a single tenant. The same email may register at
  several tenants as independent accounts. Tenant-owned (RLS).

  Email + password with optional email confirmation. Confirmation is required
  before purchase/booking (see `SportsCoachBookings.Customers.require_confirmed/1`)
  but **not** before login. Password hashing reuses the PBKDF2 implementation
  introduced by WP-01 for staff; `mix phx.gen.auth` cannot run in this JSON-only
  app. See `docs/rfcs/20260928-customers-json-auth.md`.
  """

  use SportsCoachBookings.Core.TenantSchema

  alias SportsCoachBookings.Customers.Phone
  alias SportsCoachBookings.Staff.Password

  @type t :: %__MODULE__{}

  @terms_version "2026-09-28"
  @privacy_version "2026-09-28"
  @phone_error "Enter a valid phone number for the selected country."

  schema "customer_users" do
    field :tenant_id, :binary_id
    field :email, :string
    field :hashed_password, :string
    field :first_name, :string
    field :last_name, :string
    field :phone, :string
    field :phone_country, :string, virtual: true
    field :terms_version, :string
    field :terms_accepted_at, :utc_datetime_usec
    field :privacy_version, :string
    field :privacy_accepted_at, :utc_datetime_usec
    field :confirmed_at, :utc_datetime_usec
    field :active, :boolean, default: true

    field :password, :string, virtual: true, redact: true
    field :accept_terms, :boolean, virtual: true
    field :accept_privacy, :boolean, virtual: true

    has_many :tokens, SportsCoachBookings.Customers.CustomerUserToken,
      foreign_key: :customer_user_id

    timestamps()
  end

  @doc "The current accepted terms-of-service version."
  @spec terms_version() :: String.t()
  def terms_version, do: @terms_version

  @doc "The current accepted privacy-policy version."
  @spec privacy_version() :: String.t()
  def privacy_version, do: @privacy_version

  @doc """
  Registration changeset.

  Requires `accept_terms` and `accept_privacy` to be `true` and records the
  current terms/privacy version and acceptance timestamp.
  """
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(customer_user, attrs) do
    now = now()

    customer_user
    |> Ecto.Changeset.cast(attrs, [
      :email,
      :password,
      :first_name,
      :last_name,
      :phone,
      :phone_country,
      :accept_terms,
      :accept_privacy
    ])
    |> Ecto.Changeset.validate_required([
      :email,
      :password,
      :first_name,
      :last_name
    ])
    |> validate_email()
    |> validate_phone()
    |> validate_password()
    |> validate_acceptance(:accept_terms, "you must accept the terms of service")
    |> validate_acceptance(:accept_privacy, "you must accept the privacy policy")
    |> Ecto.Changeset.put_change(:terms_version, @terms_version)
    |> Ecto.Changeset.put_change(:terms_accepted_at, now)
    |> Ecto.Changeset.put_change(:privacy_version, @privacy_version)
    |> Ecto.Changeset.put_change(:privacy_accepted_at, now)
    |> hash_password()
    |> Ecto.Changeset.unique_constraint([:tenant_id, :email])
  end

  @doc "Changeset for self-service profile edits (name + phone)."
  @spec profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(customer_user, attrs) do
    customer_user
    |> Ecto.Changeset.cast(attrs, [:first_name, :last_name, :phone, :phone_country])
    |> Ecto.Changeset.validate_required([:first_name, :last_name])
    |> Ecto.Changeset.validate_length(:first_name, min: 1, max: 100)
    |> Ecto.Changeset.validate_length(:last_name, min: 1, max: 100)
    |> validate_phone()
  end

  @doc "Changeset for an email change; clears confirmation so the new address is re-confirmed."
  @spec email_changeset(t(), map()) :: Ecto.Changeset.t()
  def email_changeset(customer_user, attrs) do
    customer_user
    |> Ecto.Changeset.cast(attrs, [:email])
    |> Ecto.Changeset.validate_required([:email])
    |> validate_email()
    |> Ecto.Changeset.put_change(:confirmed_at, nil)
    |> Ecto.Changeset.unique_constraint([:tenant_id, :email])
  end

  @doc "Changeset for a password reset or self-service password change."
  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(customer_user, attrs) do
    customer_user
    |> Ecto.Changeset.cast(attrs, [:password])
    |> Ecto.Changeset.validate_required([:password])
    |> validate_password()
    |> hash_password()
  end

  @doc "Marks the email as confirmed."
  @spec confirm_changeset(t()) :: Ecto.Changeset.t()
  def confirm_changeset(customer_user),
    do: Ecto.Changeset.change(customer_user, confirmed_at: now())

  @doc "Activates or deactivates the account. Deactivation blocks login; data is retained."
  @spec activation_changeset(t(), boolean()) :: Ecto.Changeset.t()
  def activation_changeset(customer_user, active) when is_boolean(active),
    do: Ecto.Changeset.change(customer_user, active: active)

  @doc "True when the email has been confirmed."
  @spec confirmed?(t()) :: boolean()
  def confirmed?(%__MODULE__{confirmed_at: nil}), do: false
  def confirmed?(%__MODULE__{}), do: true

  @doc "True when the account is active."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{active: active}), do: active == true

  @doc "True when `password` matches the stored hash."
  @spec valid_password?(t(), binary()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hash}, password) when is_binary(password),
    do: Password.verify(password, hash)

  def valid_password?(_customer_user, _password), do: false

  @doc "The customer's full name."
  @spec full_name(t()) :: String.t()
  def full_name(%__MODULE__{first_name: first, last_name: last}), do: "#{first} #{last}"

  defp validate_email(changeset) do
    changeset
    |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/i,
      message: "must be a valid email address"
    )
    |> Ecto.Changeset.validate_length(:email, max: 160)
  end

  defp validate_phone(changeset) do
    if Map.has_key?(changeset.changes, :phone) or
         Map.has_key?(changeset.changes, :phone_country) do
      country = Ecto.Changeset.get_field(changeset, :phone_country)
      phone = Ecto.Changeset.get_field(changeset, :phone)

      case Phone.normalize(country, phone) do
        {:ok, nil} ->
          changeset

        {:ok, e164} ->
          Ecto.Changeset.put_change(changeset, :phone, e164)

        {:error, :invalid} ->
          Ecto.Changeset.add_error(changeset, :phone, @phone_error)
      end
    else
      changeset
    end
  end

  defp validate_password(changeset) do
    Ecto.Changeset.validate_length(changeset, :password, min: 12, max: 72)
  end

  defp validate_acceptance(changeset, field, message) do
    Ecto.Changeset.validate_acceptance(changeset, field, message: message)
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    Ecto.Changeset.put_change(changeset, :hashed_password, Password.hash(password))
  end

  defp hash_password(changeset), do: changeset

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
