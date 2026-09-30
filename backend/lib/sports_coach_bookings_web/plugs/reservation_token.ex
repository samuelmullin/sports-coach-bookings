defmodule SportsCoachBookingsWeb.Plugs.ReservationToken do
  @moduledoc """
  Reads the guest reservation bearer token from the `x-reservation-token` header.

  Halts with `401` when the header is absent. When the route carries a
  reservation id, the reservation is loaded and assigned as
  `:current_reservation`; a bad token or unknown id halts with `404` so a caller
  cannot tell the two apart. The raw token is assigned as `:reservation_token`
  for the controller to pass back to the context.
  """

  @behaviour Plug

  import Plug.Conn

  alias SportsCoachBookings.Reservations

  @header "x-reservation-token"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, @header) do
      [token | _] when token != "" ->
        conn
        |> assign(:reservation_token, token)
        |> load_reservation(token)

      _ ->
        error(conn, 401, "unauthorized", "A reservation token is required")
    end
  end

  defp load_reservation(conn, token) do
    case conn.path_params["id"] do
      nil ->
        conn

      id ->
        case Reservations.fetch(id, token) do
          {:ok, reservation} -> assign(conn, :current_reservation, reservation)
          {:error, _reason} -> error(conn, 404, "not_found", "Reservation not found")
        end
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code, message: message, details: %{}}}))
    |> halt()
  end
end
