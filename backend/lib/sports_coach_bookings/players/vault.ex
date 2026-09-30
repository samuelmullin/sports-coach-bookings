defmodule SportsCoachBookings.Players.Vault do
  @moduledoc """
  Cloak vault for player medical data (owned by WP-06).

  Medical fields are encrypted with AES-256-GCM. The 32-byte key is read at
  runtime from the `PLAYER_MEDICAL_ENCRYPTION_KEY` environment variable (base64
  encoded). In dev/test a deterministic, non-secret key is derived when the
  variable is unset so that `mix test` and `mix setup` work out of the box.

  Rotation: add a new labelled cipher and re-encrypt with `mix cloak.migrate`
  (see `docs/rfcs/20260928-players-medical-encryption.md`).
  """

  use Cloak.Vault, otp_app: :sports_coach_bookings

  @env_key "PLAYER_MEDICAL_ENCRYPTION_KEY"
  @dev_key_seed "sports_coach_bookings:dev-only-player-medical-key"

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key()}
      )

    {:ok, config}
  end

  defp key do
    case System.get_env(@env_key) do
      nil -> :crypto.hash(:sha256, @dev_key_seed)
      encoded -> Base.decode64!(encoded)
    end
  end
end
