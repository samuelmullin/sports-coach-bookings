defmodule SportsCoachBookingsWeb.Platform.RegistrationController do
  @moduledoc "Staff account registration and email confirmation (platform host)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Staff
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Staff.Auth
  alias SportsCoachBookingsWeb.StaffJSON

  tags(["platform"])

  operation(:create,
    summary: "Register a global staff user",
    request_body: {"Registration", "application/json", Api.registration_request()},
    responses: [
      created: {"Registered", "application/json", Api.session_response()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/platform/staff_users"
  def create(conn, params) do
    case Staff.register_staff_user(params) do
      {:ok, staff_user} ->
        Staff.deliver_confirmation_instructions(staff_user)

        conn
        |> Auth.log_in_staff(staff_user)
        |> put_status(:created)
        |> json(%{staff_user: StaffJSON.staff_user(staff_user)})

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  operation(:confirm,
    summary: "Confirm a staff email",
    request_body: {"Token", "application/json", Api.token_request()},
    responses: [
      ok: {"Confirmed", "application/json", Api.session_response()},
      not_found: {"Invalid token", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/platform/confirmation"
  def confirm(conn, %{"token" => token}) do
    case Staff.confirm_staff_user(token) do
      {:ok, staff_user} -> json(conn, %{staff_user: StaffJSON.staff_user(staff_user)})
      {:error, :invalid_token} -> {:error, :not_found}
    end
  end

  def confirm(_conn, _params), do: {:error, {:validation_error, "token is required"}}

  operation(:resend,
    summary: "Resend a confirmation email",
    request_body: {"Email", "application/json", Api.password_reset_request()},
    responses: [accepted: {"Accepted", "application/json", Api.message()}]
  )

  @doc "POST /api/platform/confirmation/resend"
  def resend(conn, %{"email" => email}) do
    case Staff.get_staff_user_by_email(email) do
      nil -> :ok
      staff_user -> Staff.deliver_confirmation_instructions(staff_user)
    end

    conn
    |> put_status(:accepted)
    |> json(%{message: "If the address exists, a confirmation email has been sent."})
  end
end
