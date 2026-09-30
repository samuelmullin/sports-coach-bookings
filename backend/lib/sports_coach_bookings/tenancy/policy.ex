defmodule SportsCoachBookings.Tenancy.Policy do
  @moduledoc """
  Authorization for tenant settings and branding. Owned by WP-01.

  Settings and branding writes are owner/admin; coaches are forbidden from
  settings (and may only read branding). Tenant deletion and ownership transfer
  are owner-only. The public portal branding and slug-availability checks are
  open to everyone.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor

  @impl SportsCoachBookings.Core.Policy
  def authorize(%StaffActor{role: role}, action, :settings)
      when action in [:get, :list, :update] and role in [:owner, :admin],
      do: :ok

  def authorize(%StaffActor{}, action, :branding) when action in [:get, :list], do: :ok

  def authorize(%StaffActor{role: role}, action, :branding)
      when action in [:update, :upload] and role in [:owner, :admin],
      do: :ok

  def authorize(%StaffActor{role: :owner}, action, :tenant)
      when action in [:transfer_ownership, :delete],
      do: :ok

  def authorize(_actor, :view, :public_branding), do: :ok
  def authorize(_actor, :view, :slug), do: :ok
  def authorize(_actor, :signup, :tenant), do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}
end
