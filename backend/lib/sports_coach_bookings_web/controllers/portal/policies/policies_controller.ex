defmodule SportsCoachBookingsWeb.Portal.Policies.PoliciesController do
  @moduledoc "Portal read endpoint for an offering's cancellation-policy summary."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Catalog
  alias SportsCoachBookings.Policies
  alias SportsCoachBookingsWeb.Policies.Helpers
  alias SportsCoachBookingsWeb.PoliciesJSON
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Schemas.Policies.PolicySummaryResponse

  tags(["portal"])

  operation(:show,
    summary: "Get the cancellation policy summary for an offering",
    parameters: [offering_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Policy summary", "application/json", PolicySummaryResponse},
      not_found: {"Not found", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/portal/policies/offerings/:offering_id"
  def show(conn, %{"offering_id" => offering_id}) do
    with :ok <- Helpers.authorize(conn, :summary, :offering_policy),
         {:ok, _offering} <- Catalog.fetch_offering(offering_id) do
      json(conn, PoliciesJSON.summary(Policies.summary_for_offering(offering_id)))
    end
  end
end
