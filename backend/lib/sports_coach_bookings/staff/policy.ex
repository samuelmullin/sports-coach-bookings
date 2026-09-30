defmodule SportsCoachBookings.Staff.Policy do
  @moduledoc """
  Authorization for staff team management. Owned by WP-01.

  Owners may manage any team action. Admins may manage admins and coaches but
  never owners. Coaches, customers, and anonymous callers are forbidden from
  team management. `:me` is available to any authenticated staff actor.
  """

  use SportsCoachBookings.Core.Policy

  alias SportsCoachBookings.Core.StaffActor

  @impl SportsCoachBookings.Core.Policy
  def authorize(%StaffActor{}, :me, :staff_user), do: :ok

  def authorize(%StaffActor{role: :owner}, action, :team)
      when action in [:list, :change_role, :remove],
      do: :ok

  def authorize(%StaffActor{role: :owner}, {:invite, role}, :team)
      when role in [:owner, :admin, :coach],
      do: :ok

  def authorize(%StaffActor{role: :owner}, {:change_role, role}, :team)
      when role in [:owner, :admin, :coach],
      do: :ok

  def authorize(%StaffActor{role: :owner}, {:remove, role}, :team)
      when role in [:owner, :admin, :coach],
      do: :ok

  def authorize(%StaffActor{role: :admin}, {:invite, role}, :team)
      when role in [:admin, :coach],
      do: :ok

  def authorize(%StaffActor{role: :admin}, {:change_role, role}, :team)
      when role in [:admin, :coach],
      do: :ok

  def authorize(%StaffActor{role: :admin}, {:remove, role}, :team)
      when role in [:admin, :coach],
      do: :ok

  def authorize(%StaffActor{role: :admin}, :list, :team), do: :ok

  def authorize(%StaffActor{role: :owner}, :transfer_ownership, :tenant), do: :ok

  def authorize(_actor, _action, _resource), do: {:error, :forbidden}
end
