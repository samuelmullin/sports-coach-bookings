defmodule SportsCoachBookingsWeb.Dev.EmailPreviewController do
  @moduledoc "Development-only preview of registered email templates."

  use SportsCoachBookingsWeb, :controller

  alias SportsCoachBookings.Notifications
  alias SportsCoachBookings.Notifications.Templates

  @doc "GET /dev/emails — list registered templates."
  def index(conn, _params) do
    links =
      Enum.map_join(Templates.keys(), "", fn key ->
        ~s(<li><a href="/dev/emails/#{key}">#{key}</a></li>)
      end)

    send_html(conn, 200, "<h1>Email templates</h1><ul>#{links}</ul>")
  end

  @doc "GET /dev/emails/:template_key — render one template with sample assigns."
  def show(conn, %{"template_key" => key}) do
    case Notifications.preview(key) do
      {:ok, %{subject: subject, html: html}} ->
        send_html(conn, 200, "<p><strong>Subject:</strong> #{subject}</p><hr />#{html}")

      {:error, {:unknown_template, _}} ->
        send_html(conn, 404, "<h1>Unknown template</h1>")

      {:error, reason} ->
        send_html(conn, 422, "<h1>Could not render template</h1><pre>#{inspect(reason)}</pre>")
    end
  end

  # Development-only route (compiled out of production; see `dev_routes` in the
  # router). Bodies are developer-authored templates rendered with sample
  # assigns, never end-user input.
  # sobelow_skip ["XSS.SendResp"]
  defp send_html(conn, status, body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end
end
