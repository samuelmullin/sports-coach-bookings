defmodule SportsCoachBookings.Staff.StaffUserToken do
  @moduledoc """
  Opaque, single-use tokens for global staff users: sessions, email
  confirmation, and password reset.

  The plaintext token is handed to the user (cookie or emailed link); only its
  SHA-256 hash is stored. Lookups hash the presented token and match exactly.
  """

  use SportsCoachBookings.Core.Schema

  alias SportsCoachBookings.Staff.StaffUser

  @type t :: %__MODULE__{}

  @session_validity_days 60
  @confirm_validity_minutes 60 * 24 * 7
  @reset_validity_minutes 60
  @contexts ~w(session confirm reset_password change_email)

  schema "staff_users_tokens" do
    field :token, :string
    field :context, :string
    field :sent_to, :string

    belongs_to :staff_user, StaffUser

    timestamps(updated_at: false)
  end

  @doc """
  Builds a token for `staff_user` in `context`.

  Returns `{plaintext_token, changeset}` — insert the changeset, give the
  plaintext to the user.
  """
  @spec build(StaffUser.t(), atom() | String.t(), keyword()) ::
          {binary(), Ecto.Changeset.t()}
  def build(staff_user, context, opts \\ []) do
    context = to_string(context)

    unless context in @contexts do
      raise ArgumentError, "unknown token context: #{inspect(context)}"
    end

    plaintext = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    changeset =
      Ecto.Changeset.change(%__MODULE__{
        staff_user_id: staff_user.id,
        context: context,
        sent_to: opts[:sent_to],
        token: hash(plaintext)
      })

    {plaintext, changeset}
  end

  @doc "Hashes a plaintext token for storage or lookup."
  @spec hash(binary()) :: binary()
  def hash(plaintext) when is_binary(plaintext) do
    :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
  end

  @doc "True when the token is past its lifetime for its context."
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{context: "session", inserted_at: inserted_at}) do
    not within?(inserted_at, @session_validity_days * 24 * 60, :minute)
  end

  def expired?(%__MODULE__{context: "confirm", inserted_at: inserted_at}) do
    not within?(inserted_at, @confirm_validity_minutes, :minute)
  end

  def expired?(%__MODULE__{context: "reset_password", inserted_at: inserted_at}) do
    not within?(inserted_at, @reset_validity_minutes, :minute)
  end

  def expired?(%__MODULE__{}), do: false

  defp within?(nil, _amount, _unit), do: false

  defp within?(inserted_at, amount, unit) do
    DateTime.diff(DateTime.utc_now(), inserted_at, unit) < amount
  end
end
