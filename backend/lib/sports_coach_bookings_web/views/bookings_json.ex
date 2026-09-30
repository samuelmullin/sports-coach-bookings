defmodule SportsCoachBookingsWeb.BookingsJSON do
  @moduledoc "Serialises bookings, rosters, cancel previews, and rebook options."

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Catalog.Offering
  alias SportsCoachBookingsWeb.SchedulingJSON

  @doc "Serialises a booking."
  @spec booking(Booking.t()) :: map()
  def booking(%Booking{} = booking) do
    %{
      id: booking.id,
      session_id: booking.session_id,
      player_id: booking.player_id,
      household_id: booking.household_id,
      status: to_string(booking.status),
      payment_method: to_string(booking.payment_method),
      credits_used: booking.credits_used,
      order_line_id: booking.order_line_id,
      rebook_count: booking.rebook_count,
      rebooked_from_id: booking.rebooked_from_id,
      rebooked_to_id: booking.rebooked_to_id,
      hold_expires_at: datetime(booking.hold_expires_at),
      cancelled_at: datetime(booking.cancelled_at),
      free_change_until: datetime(booking.free_change_until),
      cancel_outcome: booking.cancel_outcome,
      paid_amount: booking.paid_amount,
      currency: booking.currency,
      policy_snapshot: booking.policy_snapshot,
      inserted_at: datetime(booking.inserted_at),
      updated_at: datetime(booking.updated_at)
    }
  end

  @doc "Serialises an enriched `%{booking:, session:, offering:}` entry."
  @spec entry(map()) :: map()
  def entry(%{booking: booking} = entry) do
    %{
      booking: booking(booking),
      session: entry.session && SchedulingJSON.session(entry.session),
      offering: offering(entry.offering)
    }
  end

  @doc "Wraps a list in the pagination envelope."
  @spec collection([map()], String.t() | nil) :: map()
  def collection(data, next_cursor \\ nil), do: %{data: data, next_cursor: next_cursor}

  @doc "Serialises the result of `Bookings.cancel_preview/2`."
  @spec cancel_preview(map()) :: map()
  def cancel_preview(%{booking: booking} = result) do
    %{
      booking: booking(booking),
      already_cancelled: Map.get(result, :already_cancelled, false),
      outcome: Map.get(result, :outcome, %{})
    }
  end

  @doc "Serialises the result of `Bookings.rebook_options/2`."
  @spec rebook_options(map()) :: map()
  def rebook_options(%{sessions: sessions} = result) do
    %{
      allowed: Map.get(result, :allowed, false),
      reason: Map.get(result, :reason),
      sessions:
        Enum.map(sessions, fn %{session: session, offering: offering} ->
          %{session: SchedulingJSON.session(session), offering: offering(offering)}
        end)
    }
  end

  @doc "Serialises a booking history event."
  @spec event(map()) :: map()
  def event(event) do
    %{
      id: event.id,
      kind: event.kind,
      actor_type: event.actor_type,
      actor_id: event.actor_id,
      data: event.data,
      inserted_at: datetime(event.inserted_at)
    }
  end

  @doc "Wraps roster rows in a `data` envelope."
  @spec roster([map()]) :: map()
  def roster(rows), do: %{data: rows}

  defp offering(nil), do: nil

  defp offering(%Offering{} = offering) do
    %{
      id: offering.id,
      name: offering.name,
      slug: offering.slug,
      format: to_string(offering.format),
      duration_minutes: offering.duration_minutes,
      credit_cost: offering.credit_cost,
      drop_in_price: offering.drop_in_price,
      min_age: offering.min_age,
      max_age: offering.max_age
    }
  end

  defp datetime(nil), do: nil
  defp datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
