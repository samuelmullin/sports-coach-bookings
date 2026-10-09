defmodule SportsCoachBookingsWeb.Staff.Websites.SiteController do
  @moduledoc "Staff editing, publishing, and media uploads for the hosted website."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Websites
  alias SportsCoachBookings.Websites.Policy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Websites, as: Schemas
  alias SportsCoachBookingsWeb.WebsitesJSON

  tags(["staff"])

  operation(:show,
    summary: "Get hosted website draft and published content",
    responses: [ok: {"Website", "application/json", Schemas.site()}]
  )

  def show(conn, _params) do
    with :ok <- Policy.authorize(actor(conn), :get, :site) do
      json(conn, WebsitesJSON.site(Websites.get_site()))
    end
  end

  operation(:update,
    summary: "Update hosted website draft",
    request_body: {"Website draft", "application/json", Schemas.site_update()},
    responses: [
      ok: {"Website", "application/json", Schemas.site()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  def update(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :update, :site),
         {:ok, site} <- Websites.update_draft(actor(conn), body(params, "site")) do
      json(conn, WebsitesJSON.site(site))
    end
  end

  operation(:publish,
    summary: "Publish the hosted website draft",
    responses: [
      ok: {"Website", "application/json", Schemas.site()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  def publish(conn, _params) do
    with :ok <- Policy.authorize(actor(conn), :publish, :site),
         {:ok, site} <- Websites.publish(actor(conn)) do
      json(conn, WebsitesJSON.site(site))
    end
  end

  operation(:create_upload,
    summary: "Presign a hosted website image upload",
    request_body: {"Upload", "application/json", Api.upload_request()},
    responses: [
      created: {"Upload", "application/json", Api.upload_response()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  def create_upload(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :upload, :site),
         {:ok, upload} <- Websites.presign_upload(body(params, "upload")) do
      response =
        upload
        |> Map.take([:key, :upload_url, :method, :headers])
        |> Map.put(:expires_at, DateTime.to_iso8601(upload.expires_at))

      conn |> put_status(:created) |> json(response)
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp body(params, key) do
    case Map.get(params, key) do
      %{} = attrs -> attrs
      _value -> Map.drop(params, [key, "id", "cursor", "limit"])
    end
  end
end
