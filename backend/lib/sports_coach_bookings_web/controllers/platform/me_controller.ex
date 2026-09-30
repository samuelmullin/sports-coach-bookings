defmodule SportsCoachBookingsWeb.Platform.MeController do
  @moduledoc "The current staff user and their memberships (tenant picker)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.StaffJSON
  alias SportsCoachBookingsWeb.TenancyJSON

  tags(["platform"])

  operation(:show,
    summary: "Get the current staff user and memberships",
    responses: [
      ok: {"Current staff user", "application/json", Api.me()},
      unauthorized: {"Not logged in", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/platform/me"
  def show(conn, _params) do
    staff_user = conn.assigns.current_staff_user

    memberships =
      staff_user
      |> Staff.list_memberships()
      |> Enum.map(fn membership ->
        Map.put(
          StaffJSON.membership(membership),
          :tenant,
          TenancyJSON.tenant(Tenancy.get_tenant!(membership.tenant_id))
        )
      end)

    json(conn, %{staff_user: StaffJSON.staff_user(staff_user), memberships: memberships})
  end
end
