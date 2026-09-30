defmodule SportsCoachBookings.Staff.Password do
  @moduledoc """
  Password hashing for global staff identities.

  Uses PBKDF2-HMAC-SHA256 from OTP's `:crypto` (no external dependency) and
  stores a self-describing string:

      pbkdf2_sha256$<iterations>$<base64 salt>$<base64 digest>

  `mix phx.gen.auth` is unusable in this JSON-only app (it requires
  `phoenix_html`), so this module provides the equivalent password behaviour
  that the generated `StaffUser` schema would have used. See
  `docs/rfcs/20260928-tenancy-staff-json-auth.md`.
  """

  @algo :sha256
  @salt_bytes 16
  @digest_bytes 32
  @default_iterations 120_000

  @doc "Hashes `password`, returning a self-describing stored string."
  @spec hash(binary()) :: binary()
  def hash(password) when is_binary(password) do
    iterations = iterations()
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    digest = :crypto.pbkdf2_hmac(@algo, password, salt, iterations, @digest_bytes)

    "pbkdf2_sha256$#{iterations}$#{Base.encode64(salt)}$#{Base.encode64(digest)}"
  end

  @doc "Constant-time verification of `password` against a stored hash."
  @spec verify(binary(), binary() | nil) :: boolean()
  def verify(password, stored) when is_binary(password) and is_binary(stored) do
    with ["pbkdf2_sha256", iterations, salt_b64, digest_b64] <- String.split(stored, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.decode64(salt_b64),
         {:ok, digest} <- Base.decode64(digest_b64) do
      computed = :crypto.pbkdf2_hmac(@algo, password, salt, iterations, byte_size(digest))
      Plug.Crypto.secure_compare(computed, digest)
    else
      _ -> false
    end
  end

  def verify(_password, _stored), do: false

  defp iterations do
    Application.get_env(:sports_coach_bookings, :password_hashing_iterations, @default_iterations)
  end
end
