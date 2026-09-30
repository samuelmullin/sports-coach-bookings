defmodule SportsCoachBookings.Players.Encrypted.Binary do
  @moduledoc """
  An encrypted text field stored as `bytea`, transparently decrypted on load.

  Used for every clinical field on `SportsCoachBookings.Players.MedicalInfo`.
  The ciphertext is not searchable and is never logged (see
  `docs/rfcs/20260928-players-medical-encryption.md`).
  """

  use Cloak.Ecto.Binary, vault: SportsCoachBookings.Players.Vault
end
