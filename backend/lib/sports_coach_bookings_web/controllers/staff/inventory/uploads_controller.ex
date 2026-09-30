defmodule SportsCoachBookingsWeb.Staff.Inventory.UploadsController do
  @moduledoc "Presigns product image uploads (reusing the tenancy storage behaviour)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Inventory
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Staff.Inventory.Helpers

  tags(["staff"])

  operation(:create,
    summary: "Presign a product image upload",
    request_body: {"Upload", "application/json", Api.upload_request()},
    responses: [
      created: {"Upload", "application/json", Api.upload_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid upload", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/inventory/uploads"
  def create(conn, params) do
    with :ok <- Helpers.authorize(conn, :upload, :product),
         {:ok, presigned} <- Inventory.presign_upload(Helpers.actor(conn), upload_attrs(params)) do
      body =
        presigned
        |> Map.take([:key, :upload_url, :method, :headers])
        |> Map.put(:expires_at, DateTime.to_iso8601(presigned.expires_at))

      conn
      |> put_status(:created)
      |> json(body)
    end
  end

  defp upload_attrs(%{"upload" => %{} = attrs}), do: attrs
  defp upload_attrs(params), do: Map.drop(params, ["cursor", "limit"])
end
