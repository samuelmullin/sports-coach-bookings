defmodule SportsCoachBookingsWeb.Platform.PasswordResetController do
  @moduledoc "Staff password reset (platform host)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Staff
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.StaffJSON

  tags(["platform"])

  operation(:create,
    summary: "Request a password reset",
    request_body: {"Email", "application/json", Api.password_reset_request()},
    responses: [accepted: {"Accepted", "application/json", Api.message()}]
  )

  @doc "POST /api/platform/password_reset"
  def create(conn, %{"email" => email}) do
    Staff.deliver_reset_password_instructions(email)

    conn
    |> put_status(:accepted)
    |> json(%{message: "If the address exists, a reset email has been sent."})
  end

  def create(_conn, _params), do: {:error, {:validation_error, "email is required"}}

  operation(:update,
    summary: "Apply a password reset",
    request_body: {"Reset", "application/json", Api.password_reset_update_request()},
    responses: [
      ok: {"Reset", "application/json", Api.session_response()},
      not_found: {"Invalid token", "application/json", ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "PUT /api/platform/password_reset"
  def update(conn, %{"token" => token} = params) do
    case Staff.reset_password(token, %{"password" => params["password"]}) do
      {:ok, staff_user} -> json(conn, %{staff_user: StaffJSON.staff_user(staff_user)})
      {:error, :invalid_token} -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def update(_conn, _params), do: {:error, {:validation_error, "token and password are required"}}
end
