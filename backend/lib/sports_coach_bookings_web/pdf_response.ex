defmodule SportsCoachBookingsWeb.PdfResponse do
  @moduledoc "Sends a waiver PDF as a private, non-cacheable attachment."

  import Plug.Conn

  alias OpenApiSpex.Schema

  @doc "OpenAPI schema for a binary PDF body."
  @spec schema() :: Schema.t()
  def schema, do: %Schema{type: :string, format: :binary, description: "A PDF document"}

  @doc "Sends `pdf` as `filename` with `private, no-store` caching."
  @spec send_pdf(Plug.Conn.t(), binary(), String.t()) :: Plug.Conn.t()
  def send_pdf(conn, pdf, filename) when is_binary(pdf) do
    conn
    |> put_resp_content_type("application/pdf", nil)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(200, pdf)
  end
end
