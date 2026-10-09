defmodule SportsCoachBookings.Bookings.CoachAccess do
  @moduledoc """
  Answers whether a staff actor may see a given player.

  Owners and admins always see players. A coach sees a player only when the
  player has a non-cancelled booking in a session the coach is assigned to,
  within the window **30 days before to 90 days after** that session. The
  answer is cached per request process.

      player_visible?(staff_actor, player_id) :: boolean()
  """

  import Ecto.Query

  alias SportsCoachBookings.Bookings.Booking
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookings.Staff

  @before_days 30
  @after_days 90
  @cache_key :bookings_coach_access_cache

  @doc "Whether `staff_actor` may see `player_id`."
  @spec player_visible?(StaffActor.t() | nil, binary()) :: boolean()
  def player_visible?(%StaffActor{role: role}, _player_id) when role in [:owner, :admin], do: true

  def player_visible?(%StaffActor{role: :coach} = actor, player_id) when is_binary(player_id) do
    key = {actor.tenant_id, actor.staff_user_id, player_id}
    cache = Process.get(@cache_key, %{})

    case Map.fetch(cache, key) do
      {:ok, value} ->
        value

      :error ->
        value = compute(actor, player_id)
        Process.put(@cache_key, Map.put(cache, key, value))
        value
    end
  end

  def player_visible?(_actor, _player_id), do: false

  @doc "Clears the per-process visibility cache (used by tests)."
  @spec reset_cache() :: :ok
  def reset_cache do
    Process.delete(@cache_key)
    :ok
  end

  defp compute(actor, player_id) do
    case membership_id_for(actor) do
      nil -> false
      membership_id -> visible_through_sessions?(membership_id, player_id)
    end
  end

  defp visible_through_sessions?(membership_id, player_id) do
    now = DateTime.utc_now()
    from = DateTime.add(now, -@after_days * 86_400)
    to = DateTime.add(now, @before_days * 86_400)

    coach_session_ids =
      membership_id
      |> coach_sessions(from, to)
      |> MapSet.new(& &1.id)

    if MapSet.size(coach_session_ids) == 0 do
      false
    else
      booked_session_ids(player_id)
      |> Enum.any?(&MapSet.member?(coach_session_ids, &1))
    end
  end

  # Runs in a tenant transaction: this is called from controllers/contexts that are
  # not themselves inside one, and without the tenant GUC row-level security hides
  # every booking, which made coaches invisible to their own players.
  defp booked_session_ids(player_id) do
    {:ok, ids} =
      Repo.with_tenant_tx(fn ->
        Repo.all(
          from b in Booking,
            where: b.player_id == ^player_id and b.status in [:held, :confirmed, :attended],
            select: b.session_id
        )
      end)

    ids
  end

  defp coach_sessions(membership_id, from, to) do
    Scheduling.list_sessions(%{coach_id: membership_id, from: from, to: to})
  end

  defp membership_id_for(%StaffActor{membership: %{id: id}}), do: id

  defp membership_id_for(%StaffActor{staff_user_id: staff_user_id})
       when is_binary(staff_user_id) do
    case Staff.get_active_membership(staff_user_id) do
      %{id: membership_id} -> membership_id
      _ -> nil
    end
  end

  defp membership_id_for(_actor), do: nil
end
