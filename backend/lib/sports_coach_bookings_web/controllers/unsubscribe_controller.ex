defmodule SportsCoachBookingsWeb.UnsubscribeController do
  @moduledoc """
  Public one-click unsubscribe endpoint (RFC 8058). The signed token is the
  credential; the tenant is resolved from the host.
  """

  use SportsCoachBookingsWeb, :controller

  alias SportsCoachBookings.Notifications

  # The confirmation page is built from constant strings only (the token is
  # validated by `Notifications.unsubscribe/1` and never interpolated), so there
  # is no XSS sink. Accepted by Sobelow as a false positive.
  @doc "GET /unsubscribe/:token — confirmation page shown to a person."
  # sobelow_skip ["XSS.SendResp"]
  def show(conn, %{"token" => token}) do
    case Notifications.unsubscribe(token) do
      {:ok, :unsubscribed} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          200,
          page("You have been unsubscribed", "You will no longer receive these emails.")
        )

      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(
          400,
          page("Invalid link", "This unsubscribe link is invalid or has expired.")
        )
    end
  end

  @doc "POST /unsubscribe/:token — List-Unsubscribe-Post one-click target."
  def create(conn, %{"token" => token}) do
    case Notifications.unsubscribe(token) do
      {:ok, :unsubscribed} ->
        json(conn, %{unsubscribed: true})

      {:error, reason} ->
        json(conn |> put_status(:unprocessable_entity), %{error: to_string(reason)})
    end
  end

  defp page(title, message) do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head><meta charset="utf-8" /><title>#{title}</title></head>
      <body style="font-family:Arial,Helvetica,sans-serif;padding:40px;">
        <h1 style="font-size:22px;">#{title}</h1>
        <p style="color:#374151;">#{message}</p>
      </body>
    </html>
    """
  end
end
