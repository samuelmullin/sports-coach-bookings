defmodule SportsCoachBookingsWeb.StaffJSON do
  @moduledoc "Serialises staff users, memberships, and invites."

  alias SportsCoachBookings.Staff.Membership
  alias SportsCoachBookings.Staff.StaffInvite
  alias SportsCoachBookings.Staff.StaffUser

  @doc "Serialises a global staff user."
  @spec staff_user(StaffUser.t()) :: map()
  def staff_user(%StaffUser{} = user) do
    %{
      id: user.id,
      email: user.email,
      confirmed: not is_nil(user.confirmed_at),
      confirmed_at: datetime(user.confirmed_at),
      inserted_at: datetime(user.inserted_at)
    }
  end

  @doc "Serialises a membership."
  @spec membership(Membership.t()) :: map()
  def membership(%Membership{} = membership) do
    %{
      id: membership.id,
      tenant_id: membership.tenant_id,
      staff_user_id: membership.staff_user_id,
      role: membership.role,
      status: membership.status,
      display_name: membership.display_name,
      bio: membership.bio,
      photo_key: membership.photo_key,
      inserted_at: datetime(membership.inserted_at)
    }
  end

  @doc "Serialises a membership with its embedded staff user."
  @spec membership_with_user(Membership.t()) :: map()
  def membership_with_user(%Membership{} = membership) do
    Map.put(membership(membership), :staff_user, staff_user(membership.staff_user))
  end

  @doc "Serialises the `/api/platform/me` payload."
  @spec me(StaffUser.t(), [Membership.t()]) :: map()
  def me(%StaffUser{} = user, memberships) do
    %{staff_user: staff_user(user), memberships: Enum.map(memberships, &membership/1)}
  end

  @doc "Serialises a pending invite (never the token)."
  @spec invite(StaffInvite.t()) :: map()
  def invite(%StaffInvite{} = invite) do
    %{
      id: invite.id,
      email: invite.email,
      role: invite.role,
      expires_at: datetime(invite.expires_at),
      inserted_at: datetime(invite.inserted_at)
    }
  end

  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
