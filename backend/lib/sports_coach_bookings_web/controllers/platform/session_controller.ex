defmodule SportsCoachBookingsWeb.Platform.SessionController do
  @moduledoc "Staff session login/logout (platform host)."

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
    summary: "Log in a staff user",
    request_body: {"Credentials", "application/json", Api.session_request()},
    responses: [
      created: {"Session", "application/json", Api.session_response()},
      unauthorized: {"Invalid credentials", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/platform/session"
  def create(conn, params) do
    with {:ok, email} <- fetch(params, "email"),
         {:ok, password} <- fetch(params, "password"),
         {:ok, staff_user} <- Staff.authenticate(email, password) do
      conn
      |> Auth.log_in_staff(staff_user)
      |> put_status(:created)
      |> json(%{staff_user: StaffJSON.staff_user(staff_user)})
    else
      {:error, :invalid_credentials} -> {:error, :invalid_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  operation(:delete,
    summary: "Log out the current staff user",
    responses: [no_content: {"Logged out", "application/json", Api.message()}]
  )

  @doc "DELETE /api/platform/session"
  def delete(conn, _params) do
    conn |> Auth.log_out_staff() |> send_resp(:no_content, "")
  end

  defp fetch(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:validation_error, "#{key} is required"}}
    end
  end
end
