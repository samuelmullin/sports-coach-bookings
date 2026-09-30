defmodule SportsCoachBookingsWeb.Staff.Settings.BrandingController do
  @moduledoc "Tenant branding updates and asset upload presigning."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Tenancy.Policy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.TenancyJSON

  tags(["staff"])

  operation(:update,
    summary: "Update branding",
    request_body: {"Branding", "application/json", Api.branding_update_request()},
    responses: [
      ok: {"Branding", "application/json", Api.branding()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/branding"
  def update(conn, params) do
    with :ok <- authorize(conn, :update, :branding),
         {:ok, branding, warnings} <- Tenancy.update_branding(actor(conn), branding_attrs(params)) do
      json(conn, TenancyJSON.branding(branding, warnings))
    end
  end

  operation(:create_upload,
    summary: "Presign a branding asset upload",
    request_body: {"Upload", "application/json", Api.upload_request()},
    responses: [
      created: {"Upload", "application/json", Api.upload_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      unprocessable_entity: {"Invalid upload", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/branding/uploads"
  def create_upload(conn, params) do
    with :ok <- authorize(conn, :upload, :branding),
         {:ok, presigned} <- Tenancy.presign_upload(actor(conn), upload_attrs(params)) do
      body =
        presigned
        |> Map.take([:key, :upload_url, :method, :headers])
        |> Map.put(:expires_at, DateTime.to_iso8601(presigned.expires_at))

      conn
      |> put_status(:created)
      |> json(body)
    end
  end

  defp authorize(conn, action, resource), do: Policy.authorize(actor(conn), action, resource)

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp branding_attrs(%{"branding" => %{} = attrs}), do: attrs
  defp branding_attrs(params), do: Map.drop(params, ["cursor", "limit"])

  defp upload_attrs(%{"upload" => %{} = attrs}), do: attrs
  defp upload_attrs(params), do: Map.drop(params, ["cursor", "limit"])
end
