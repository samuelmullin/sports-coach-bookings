defmodule SportsCoachBookingsWeb.Staff.Settings.SettingsController do
  @moduledoc "Tenant settings and ownership (owner/admin, owner-only for destructive)."

  use SportsCoachBookingsWeb, :controller
  use OpenApiSpex.ControllerSpecs

  action_fallback SportsCoachBookingsWeb.FallbackController

  alias SportsCoachBookings.Staff
  alias SportsCoachBookings.Staff.Policy, as: StaffPolicy
  alias SportsCoachBookings.Tenancy
  alias SportsCoachBookings.Tenancy.Policy, as: TenancyPolicy
  alias SportsCoachBookingsWeb.Schemas.Api
  alias SportsCoachBookingsWeb.Schemas.ErrorResponse
  alias SportsCoachBookingsWeb.StaffJSON
  alias SportsCoachBookingsWeb.TenancyJSON

  tags(["staff"])

  operation(:show,
    summary: "Get tenant settings",
    responses: [
      ok: {"Settings", "application/json", Api.settings()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "GET /api/staff/settings"
  def show(conn, _params) do
    with :ok <- authorize(conn, TenancyPolicy, :get, :settings) do
      settings = Tenancy.tenant_settings(conn.assigns.tenant)
      json(conn, TenancyJSON.settings(settings))
    end
  end

  operation(:update,
    summary: "Update tenant settings",
    request_body: {"Settings", "application/json", Api.settings_update_request()},
    responses: [
      ok: {"Settings", "application/json", Api.settings()},
      forbidden: {"Forbidden", "application/json", ErrorResponse},
      conflict: {"Currency locked", "application/json", ErrorResponse}
    ]
  )

  @doc "PATCH /api/staff/settings"
  def update(conn, params) do
    with :ok <- authorize(conn, TenancyPolicy, :update, :settings),
         {:ok, tenant} <- Tenancy.update_settings(actor(conn), settings_attrs(params)) do
      json(
        conn,
        TenancyJSON.settings(%{
          tenant: tenant,
          currency_locked: Tenancy.tenant_settings(tenant).currency_locked
        })
      )
    end
  end

  operation(:transfer_ownership,
    summary: "Transfer tenant ownership to another member",
    request_body: {"Target", "application/json", Api.transfer_ownership_request()},
    responses: [
      ok: {"Membership", "application/json", Api.membership()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "POST /api/staff/settings/transfer_ownership"
  def transfer_ownership(conn, %{"membership_id" => membership_id}) do
    with :ok <- authorize(conn, StaffPolicy, :transfer_ownership, :tenant),
         {:ok, membership} <- Staff.transfer_ownership(actor(conn), membership_id) do
      json(conn, StaffJSON.membership(membership))
    end
  end

  def transfer_ownership(_conn, _params),
    do: {:error, {:validation_error, "membership_id is required"}}

  operation(:delete,
    summary: "Soft-delete the tenant",
    responses: [
      ok: {"Tenant", "application/json", Api.tenant()},
      forbidden: {"Forbidden", "application/json", ErrorResponse}
    ]
  )

  @doc "DELETE /api/staff/settings"
  def delete(conn, _params) do
    with :ok <- authorize(conn, TenancyPolicy, :delete, :tenant),
         {:ok, tenant} <- Tenancy.delete_tenant(actor(conn)) do
      json(conn, TenancyJSON.tenant(tenant))
    end
  end

  defp authorize(conn, policy, action, resource) do
    policy.authorize(actor(conn), action, resource)
  end

  defp actor(conn), do: conn.assigns[:current_staff_actor]

  defp settings_attrs(%{"settings" => %{} = attrs}), do: attrs
  defp settings_attrs(params), do: Map.drop(params, ["cursor", "limit"])
end
