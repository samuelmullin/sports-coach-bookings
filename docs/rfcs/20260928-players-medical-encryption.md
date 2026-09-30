# RFC 20260928 — Players: `cloak_ecto` medical-field encryption

**Owner:** wp-06 (Players). **Status:** adopted.

## Context

`docs/erd.md` marks the `medical_info` text columns as ciphertext encrypted at
rest with `cloak_ecto`, and the WP-06 brief requires a raw-SQL test proving the
stored values are ciphertext. `cloak_ecto` was already in `mix.exs`; this RFC
records the wiring choices.

## Decisions

1. **Vault.** `SportsCoachBookings.Players.Vault` (`lib/sports_coach_bookings/players/vault.ex`)
   is a `Cloak.Vault` (`otp_app: :sports_coach_bookings`) started in the
   application supervision tree, immediately after the Repo.
2. **Cipher.** AES-256-GCM (`Cloak.Ciphers.AES.GCM`, tag `"AES.GCM.V1"`, the
   `cloak_ecto` default). A random IV per value means ciphertext is not
   searchable, which is acceptable: medical fields are never queried by value.
3. **Key management.** The 32-byte key is read at runtime from the
   `PLAYER_MEDICAL_ENCRYPTION_KEY` environment variable (base64-encoded). When
   the variable is unset (dev/test), a deterministic key is derived from a
   non-secret seed so `mix test` and `mix setup` work out of the box.
   Production must set the variable (for example via the platform secret
   manager); the value is never committed.
4. **Type + storage.** `SportsCoachBookings.Players.Encrypted.Binary`
   (`Cloak.Ecto.Binary`) is used for `allergies`, `conditions`, `medications`,
   and `notes`. `cloak_ecto` requires the migration column type `:binary`
   (`bytea`); this is what is used. `docs/erd.md` labels these columns `text
   (ciphertext)`; `bytea` is the correct physical type for AES-GCM output and is
   the `cloak_ecto` contract. `has_medical_info` is a plain `boolean` (never a
   secret).
5. **Rotation.** Add a new labelled cipher to the vault and run
   `mix cloak.migrate` to re-encrypt. Not required for MVP.

## Access + audit

- `has_medical_info` may appear in list/rosters; the clinical values never do.
- Medical values are served only by `Players.read_medical_info/2` via
  `GET …/players/:id/medical`, and every read calls
  `Core.Audit.record(actor, "player.medical.read", player, %{})` in the same
  transaction. Writes record `player.medical.updated`. Audit metadata never
  contains medical values.

## Not changed

- No other context, `core/*`, or `docs/erd.md` is edited by wp-06.
