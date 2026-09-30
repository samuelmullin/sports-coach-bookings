defmodule SportsCoachBookings.Catalog.Policy do
  @moduledoc """
  Authorization for catalog management. Owned by WP-03.

  Staff (owner/admin) may manage every catalog resource. Coaches have read-only
  access to venues and offerings. The portal's public listing endpoints are open
  to everyone (anonymous, customer, coach, staff).
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor

  @manageable [:venue, :offering, :package, :discount, :tax_rate]
  @portal_resources [:venue, :offering, :package]

  @impl SportsCoachBookings.Core.Policy
  def authorize(%StaffActor{role: role}, _action, _resource) when role in [:owner, :admin],
    do: :ok

  def authorize(%StaffActor{role: :coach}, action, resource)
      when action in [:list, :get] and resource in [:venue, :offering],
      do: :ok

  def authorize(_actor, :list_public, resource) when resource in @portal_resources, do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}

  @doc "Every staff-manageable resource."
  @spec manageable() :: [atom()]
  def manageable, do: @manageable

  @doc "Resources exposed publicly in the portal."
  @spec portal_resources() :: [atom()]
  def portal_resources, do: @portal_resources
end
