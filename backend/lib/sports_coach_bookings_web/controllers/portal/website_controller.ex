defmodule SportsCoachBookingsWeb.Portal.WebsiteController do
  @moduledoc "Public hosted website content and contact intake."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Websites
  alias SportsCoachBookings.Websites.Policy
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Websites, as: Schemas

  tags(["portal"])

  operation(:show,
    summary: "Get published hosted website content",
    responses: [
      ok: {"Published website", "application/json", Schemas.published_site()},
      not_found: {"Not published", "application/json", ErrorResponse}
    ]
  )

  def show(conn, _params) do
    with :ok <- Policy.authorize(nil, :view, :published_site),
         %{} = site <- Websites.published_site() do
      json(conn, site)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  operation(:contact,
    summary: "Submit a hosted website inquiry",
    request_body: {"Contact inquiry", "application/json", Schemas.contact_request()},
    responses: [
      created: {"Contact submission", "application/json", Schemas.contact_submission()},
      unprocessable_entity: {"Invalid inquiry", "application/json", ErrorResponse}
    ]
  )

  def contact(conn, params) do
    attrs = Map.get(params, "contact", params)

    with :ok <- Policy.authorize(nil, :create, :contact_submission) do
      create_contact(conn, attrs, honeypot_filled?(attrs))
    end
  end

  # Bots fill every field. Pretend success without storing or notifying.
  defp create_contact(conn, _attrs, true) do
    conn |> put_status(:created) |> json(%{accepted: true})
  end

  defp create_contact(conn, attrs, false) do
    with {:ok, submission} <- Websites.create_contact_submission(attrs) do
      conn
      |> put_status(:created)
      |> json(SportsCoachBookingsWeb.WebsitesJSON.contact_submission(submission))
    end
  end

  defp honeypot_filled?(attrs) do
    case Map.get(attrs, "website") do
      value when is_binary(value) -> String.trim(value) != ""
      _value -> false
    end
  end
end
