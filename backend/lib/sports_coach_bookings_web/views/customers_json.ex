defmodule SportsCoachBookingsWeb.CustomersJSON do
  @moduledoc "Serialises customer users, households, members, and invites."

  alias SportsCoachBookings.Customers.CustomerUser
  alias SportsCoachBookings.Customers.Household
  alias SportsCoachBookings.Customers.HouseholdInvite
  alias SportsCoachBookings.Customers.HouseholdMember

  @doc "Serialises a customer user."
  @spec customer_user(CustomerUser.t()) :: map()
  def customer_user(%CustomerUser{} = user) do
    %{
      id: user.id,
      tenant_id: user.tenant_id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      phone: user.phone,
      confirmed: not is_nil(user.confirmed_at),
      confirmed_at: datetime(user.confirmed_at),
      active: user.active,
      terms_version: user.terms_version,
      privacy_version: user.privacy_version,
      inserted_at: datetime(user.inserted_at)
    }
  end

  @doc "Serialises a household."
  @spec household(Household.t()) :: map()
  def household(%Household{} = household) do
    %{
      id: household.id,
      tenant_id: household.tenant_id,
      name: household.name,
      inserted_at: datetime(household.inserted_at)
    }
  end

  @doc "Serialises a household with its members."
  @spec household_detail(Household.t()) :: map()
  def household_detail(%Household{members: members} = household) do
    Map.put(household(household), :members, Enum.map(members, &member/1))
  end

  @doc "Serialises a household member, including the customer user when preloaded."
  @spec member(HouseholdMember.t()) :: map()
  def member(%HouseholdMember{} = member) do
    base = %{
      id: member.id,
      tenant_id: member.tenant_id,
      household_id: member.household_id,
      customer_user_id: member.customer_user_id,
      role: member.role,
      relationship: member.relationship,
      inserted_at: datetime(member.inserted_at)
    }

    case member do
      %{customer_user: %CustomerUser{} = user} ->
        Map.put(base, :customer_user, customer_user(user))

      _ ->
        base
    end
  end

  @doc "Serialises a pending invite (never the token)."
  @spec invite(HouseholdInvite.t()) :: map()
  def invite(%HouseholdInvite{} = invite) do
    %{
      id: invite.id,
      email: invite.email,
      relationship: invite.relationship,
      expires_at: datetime(invite.expires_at),
      inserted_at: datetime(invite.inserted_at)
    }
  end

  @doc "Wraps a list of serialised rows in the paginated collection envelope."
  @spec collection([map()], binary() | nil) :: map()
  def collection(data, cursor), do: %{data: data, next_cursor: cursor}

  defp datetime(nil), do: nil
  defp datetime(value), do: DateTime.to_iso8601(value)
end
