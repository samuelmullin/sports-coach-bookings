defmodule SportsCoachBookingsWeb.Platform.SignupController do
  @moduledoc "Tenant signup and slug availability (platform host)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.Staff.Auth
  alias SportsCoachBookingsWeb.StaffJSON
  alias SportsCoachBookingsWeb.TenancyJSON

  tags(["platform"])

  operation(:create,
    summary: "Create a tenant with an owner",
    request_body: {"Signup", "application/json", Api.signup_request()},
    responses: [
      created: {"Signup result", "application/json", Api.signup_response()},
      unprocessable_entity: {"Validation error", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/platform/signup"
  def create(conn, params) do
    case Tenancy.signup(signup_attrs(params), signup_opts(conn)) do
      {:ok, %{tenant: tenant, staff_user: staff_user, membership: membership}} ->
        conn
        |> Auth.log_in_staff(staff_user)
        |> put_status(:created)
        |> json(%{
          tenant: TenancyJSON.tenant(tenant),
          staff_user: StaffJSON.staff_user(staff_user),
          membership: StaffJSON.membership(membership)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} when is_atom(reason) ->
        {:error, reason}
    end
  end

  operation(:slug_available,
    summary: "Check whether a slug is available",
    parameters: [slug: [in: :query, type: :string, required: true]],
    responses: [
      ok: {"Slug availability", "application/json", Api.slug_response()}
    ]
  )

  @doc "GET /api/platform/slug_available?slug="
  def slug_available(conn, %{"slug" => slug}) do
    case Tenancy.validate_slug(slug) do
      :ok -> json(conn, %{slug: slug, available: true, reason: nil})
      {:error, reason} -> json(conn, %{slug: slug, available: false, reason: to_string(reason)})
    end
  end

  def slug_available(_conn, _params), do: {:error, {:invalid_slug, "slug is required"}}

  defp signup_attrs(%{"tenant" => %{} = attrs}), do: attrs
  defp signup_attrs(params), do: Map.drop(params, ["cursor", "limit"])

  defp signup_opts(conn) do
    case conn.assigns[:current_staff_user] do
      %{__struct__: _} = staff_user -> [staff_user: staff_user]
      _ -> []
    end
  end
end
