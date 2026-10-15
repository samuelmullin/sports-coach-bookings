defmodule SportsCoachBookingsWeb.Staff.Websites.ContactSubmissionsController do
  @moduledoc "Staff inbox for hosted website inquiries."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Websites
  alias SportsCoachBookings.Websites.Policy
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Websites, as: Schemas
  alias SportsCoachBookingsWeb.WebsitesJSON

  tags(["staff"])

  operation(:index,
    summary: "List hosted website contact submissions",
    parameters: [
      status: [in: :query, type: :string, required: false],
      cursor: [in: :query, type: :string, required: false],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Contact submissions", "application/json", Schemas.contact_list()}]
  )

  def index(conn, params) do
    with :ok <- Policy.authorize(actor(conn), :list, :contact_submission) do
      %{data: rows, next_cursor: cursor} = Websites.page_contact_submissions(params)
      json(conn, WebsitesJSON.collection(rows, cursor))
    end
  end

  operation(:update,
    summary: "Update a hosted website contact submission",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Contact status", "application/json", Schemas.contact_update()},
    responses: [
      ok: {"Contact submission", "application/json", Schemas.contact_submission()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "contact_submission", Map.drop(params, ["id"]))

    with :ok <- Policy.authorize(actor(conn), :review, :contact_submission),
         {:ok, submission} <- Websites.update_contact_submission(actor(conn), id, attrs) do
      json(conn, WebsitesJSON.contact_submission(submission))
    end
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]
end
