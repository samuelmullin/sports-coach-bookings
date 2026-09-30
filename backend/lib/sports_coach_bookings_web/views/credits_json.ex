defmodule SportsCoachBookingsWeb.CreditsJSON do
  @moduledoc "Serialises credit lots, ledger entries, and balances. Owned by WP-12."

  alias SportsCoachBookings.Credits.CreditLedgerEntry
  alias SportsCoachBookings.Credits.CreditLot

  @doc "Serialises a balance list (`balance/1`)."
  @spec balance([map()]) :: [map()]
  def balance(entries), do: Enum.map(entries, &balance_entry/1)

  @doc "Serialises one balance group."
  @spec balance_entry(map()) :: map()
  def balance_entry(%{offering_id: offering_id, amount: amount} = entry) do
    %{
      offering_id: encode_scope(offering_id),
      amount: amount,
      nearest_expiry: datetime(Map.get(entry, :nearest_expiry))
    }
  end

  @doc "Serialises a credit lot."
  @spec lot(CreditLot.t()) :: map()
  def lot(%CreditLot{} = lot) do
    %{
      id: lot.id,
      household_id: lot.household_id,
      source: lot.source,
      order_line_id: lot.order_line_id,
      package_id: lot.package_id,
      eligible_offering_ids: lot.eligible_offering_ids || [],
      quantity_granted: lot.quantity_granted,
      remaining: lot.remaining,
      expires_at: datetime(lot.expires_at),
      granted_at: datetime(lot.granted_at),
      inserted_at: datetime(lot.inserted_at)
    }
  end

  @doc "Serialises a ledger entry."
  @spec entry(CreditLedgerEntry.t()) :: map()
  def entry(%CreditLedgerEntry{} = entry) do
    %{
      id: entry.id,
      household_id: entry.household_id,
      credit_lot_id: entry.credit_lot_id,
      delta: entry.delta,
      reason: entry.reason,
      booking_id: entry.booking_id,
      reverses_entry_id: entry.reverses_entry_id,
      actor_type: entry.actor_type,
      actor_id: entry.actor_id,
      note: entry.note,
      inserted_at: datetime(entry.inserted_at)
    }
  end

  @doc "Wraps a balance list in the standard envelope."
  @spec balance_response([map()]) :: map()
  def balance_response(entries), do: %{data: balance(entries)}

  @doc "Wraps a list of serialised rows in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  defp encode_scope(:any), do: "any"
  defp encode_scope(id), do: id

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
