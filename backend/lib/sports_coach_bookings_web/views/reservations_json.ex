defmodule SportsCoachBookingsWeb.ReservationsJSON do
  @moduledoc "Serialises guest reservations and their conversion result."

  alias SportsCoachBookings.Reservations
  alias SportsCoachBookings.Reservations.Reservation
  alias SportsCoachBookingsWeb.BookingsJSON

  @doc "Serialises a reservation (see `Reservations.serialize/1`)."
  @spec reservation(Reservation.t()) :: map()
  def reservation(%Reservation{} = reservation), do: Reservations.serialize(reservation)

  @doc "Serialises the create result, adding the one-time bearer token."
  @spec created(%{reservation: Reservation.t(), token: binary()}) :: map()
  def created(%{reservation: reservation, token: token}) do
    reservation
    |> reservation()
    |> Map.put(:token, token)
  end

  @doc "Serialises the result of `Reservations.convert/5`."
  @spec convert(map()) :: map()
  def convert(%{bookings: bookings}) do
    %{bookings: Enum.map(bookings, &BookingsJSON.booking/1)}
  end

  @doc "Serialises the `extend` result."
  @spec extend(Reservation.t()) :: map()
  def extend(%Reservation{} = reservation) do
    %{
      expires_at: reservation.expires_at,
      last_activity_at: reservation.last_activity_at
    }
  end
end
