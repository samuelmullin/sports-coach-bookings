defmodule SportsCoachBookings.Players do
  @moduledoc """
  Player profiles, contacts, pickups, and encrypted medical info. Owned by WP-06.

  All functions are tenant-scoped: callers place the tenant in context (via
  `SportsCoachBookingsWeb.Plugs.ResolveTenant` in requests or
  `SportsCoachBookings.DataCase.put_tenant/1` in tests) and every function runs
  inside `SportsCoachBookings.Repo.with_tenant_tx/2` so the RLS GUC is set.

  Medical data is served only through `read_medical_info/2` (a separate endpoint
  in the web layer), which audits every read. Medical fields are never included
  in `list_for_household/1`, `search/1`, or `summary_for_roster/1` payloads.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias SportsCoachBookings.Core.Audit
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.Policy
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Players.AuthorizedPickup
  alias SportsCoachBookings.Players.EmergencyContact
  alias SportsCoachBookings.Players.MedicalInfo
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Players.PlayerPositionOption
  alias SportsCoachBookings.Players.PlayerProfile
  alias SportsCoachBookings.Repo

  @default_positions [
    {"GK", "Goalkeeper"},
    {"CB", "Centre Back"},
    {"FB", "Full Back"},
    {"DM", "Defensive Midfielder"},
    {"CM", "Centre Midfielder"},
    {"AM", "Attacking Midfielder"},
    {"W", "Winger"},
    {"ST", "Striker"}
  ]

  ## Players

  @doc "Fetches a player by id, raising if it does not exist for this tenant."
  @spec get_player!(binary()) :: Player.t()
  def get_player!(id), do: read(fn -> Repo.get!(Player, id) end)

  @doc "Fetches a player by id, returning `{:error, :not_found}` when absent."
  @spec fetch_player(binary()) :: {:ok, Player.t()} | {:error, :not_found}
  def fetch_player(id), do: read(fn -> fetch_record(Player, id) end)

  @doc """
  Fetches a player with profile, contacts, pickups, and the medical *row*
  (whose clinical values are only rendered by the medical endpoint).
  """
  @spec fetch_player_detail(binary()) :: {:ok, Player.t()} | {:error, :not_found}
  def fetch_player_detail(id) do
    read(fn ->
      case Repo.get(Player, id) do
        nil ->
          {:error, :not_found}

        player ->
          {:ok,
           Repo.preload(player, [
             :profile,
             :emergency_contacts,
             :authorized_pickups,
             :medical_info
           ])}
      end
    end)
  end

  @doc "Lists a household's players, oldest surname first."
  @spec list_for_household(binary()) :: [Player.t()]
  def list_for_household(household_id) do
    read(fn ->
      Repo.all(
        from p in Player,
          where: p.household_id == ^household_id,
          order_by: [asc: p.last_name, asc: p.first_name]
      )
    end)
  end

  @doc """
  Paginates a household's players. Returns `%{data: [...], next_cursor: ...}`.

  Options: `:preload` — associations to load on each player (e.g.
  `[:emergency_contacts]`), so list views need no per-player requests.
  """
  @spec page_for_household(binary(), map() | keyword(), keyword()) ::
          %{data: [Player.t()], next_cursor: binary() | nil}
  def page_for_household(household_id, params \\ %{}, opts \\ []) do
    read(fn ->
      query =
        from p in Player,
          where: p.household_id == ^household_id,
          preload: ^Keyword.get(opts, :preload, [])

      {rows, cursor} = Pagination.paginate(query, params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc """
  Searches players by name (staff). `nil`/`""` returns every player; pass
  `include_inactive: true` to include archived players.
  """
  @spec search(binary() | nil) :: [Player.t()]
  def search(term), do: read(fn -> Repo.all(search_query(term, %{})) end)

  @doc "Paginates the staff player search."
  @spec page_search(binary() | nil, map() | keyword()) ::
          %{data: [Player.t()], next_cursor: binary() | nil}
  def page_search(term, params \\ %{}) do
    read(fn ->
      {rows, cursor} = Pagination.paginate(search_query(term, params), params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  @doc """
  Creates a player and publishes `player.created` in the same transaction.
  """
  @spec create_player(Policy.actor(), map() | keyword()) ::
          {:ok, Player.t()} | {:error, Ecto.Changeset.t()}
  def create_player(actor, attrs) do
    Multi.new()
    |> Multi.insert(:player, Player.changeset(%Player{}, tenant_attrs(attrs)))
    |> Multi.run(:event, fn _repo, %{player: player} ->
      Events.publish("player.created", %{player_id: player.id, tenant_id: player.tenant_id})
    end)
    |> Multi.run(:audit, fn _repo, %{player: player} ->
      Audit.record(actor, "player.created", player, %{})
    end)
    |> run_multi(:player)
  end

  @doc """
  Updates a player and publishes `player.updated` in the same transaction.
  """
  @spec update_player(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, Player.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_player(actor, id, attrs) do
    with_player(id, fn player ->
      Multi.new()
      |> Multi.update(:player, Player.changeset(player, attrs))
      |> Multi.run(:event, fn _repo, %{player: player} ->
        Events.publish("player.updated", %{player_id: player.id, tenant_id: player.tenant_id})
      end)
      |> Multi.run(:audit, fn _repo, %{player: player} ->
        Audit.record(actor, "player.updated", player, %{})
      end)
      |> run_multi(:player)
    end)
  end

  @doc "Archives (deactivates) a player and publishes `player.updated`."
  @spec archive_player(Policy.actor(), binary()) ::
          {:ok, Player.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def archive_player(actor, id), do: update_player(actor, id, %{active: false})

  @doc """
  The age in whole years of `player` on `date`.

  A Feb-29 birthday ages on Mar 1 in non-leap years (born 2000-02-29 is 23 on
  2024-02-28 and 24 on 2024-03-01).
  """
  @spec age_on(Player.t(), Date.t()) :: integer()
  def age_on(%Player{date_of_birth: %Date{} = dob}, %Date{} = date) do
    years = date.year - dob.year
    if {date.month, date.day} < {dob.month, dob.day}, do: years - 1, else: years
  end

  @doc """
  Whether a player can be booked, with reasons when they cannot.

  Returns `:ok` or `{:error, [:emergency_contact_required | :inactive_player]}`.
  """
  @spec bookable?(Player.t()) :: :ok | {:error, [atom()]}
  def bookable?(%Player{} = player) do
    read(fn ->
      reasons =
        []
        |> add_reason(not player.active, :inactive_player)
        |> add_reason(not has_emergency_contact?(player.id), :emergency_contact_required)

      case Enum.reverse(reasons) do
        [] -> :ok
        reasons -> {:error, reasons}
      end
    end)
  end

  @doc """
  A compact per-player summary for a coach roster (used by WP-15).

  Includes name, age, preferred positions, `has_medical_info` (a boolean only),
  and the primary emergency contact. Never includes medical values.
  """
  @spec summary_for_roster([binary()]) :: [map()]
  def summary_for_roster(player_ids) when is_list(player_ids) do
    read(fn ->
      from(p in Player, where: p.id in ^player_ids)
      |> Repo.all()
      |> Repo.preload([:profile, :medical_info, :emergency_contacts])
      |> Enum.map(&summary/1)
    end)
  end

  ## Profiles

  @doc "Returns a player's profile, or `nil`."
  @spec get_profile(binary()) :: PlayerProfile.t() | nil
  def get_profile(player_id) do
    read(fn -> Repo.one(from p in PlayerProfile, where: p.player_id == ^player_id) end)
  end

  @doc """
  Creates or updates a player's profile.

  Preferred positions are validated against the tenant's
  `player_position_options`; the default soccer positions are seeded first when
  the tenant has none.
  """
  @spec upsert_profile(Policy.actor(), Player.t(), map() | keyword()) ::
          {:ok, PlayerProfile.t()} | {:error, Ecto.Changeset.t()}
  def upsert_profile(actor, %Player{} = player, attrs) do
    read(fn ->
      :ok = ensure_default_position_options()
      allowed = active_position_codes()
      attrs = attrs |> tenant_attrs() |> Map.put("player_id", player.id)

      player
      |> build_profile_changeset(attrs)
      |> validate_positions(allowed)
      |> Repo.insert_or_update()
      |> case do
        {:ok, profile} ->
          {:ok, _} = Audit.record(actor, "player.profile.updated", player, %{})
          {:ok, profile}

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  ## Position options

  @doc "Lists a tenant's position options, ordered."
  @spec list_position_options() :: [PlayerPositionOption.t()]
  def list_position_options do
    read(fn ->
      Repo.all(from o in PlayerPositionOption, order_by: [asc: o.position, asc: o.code])
    end)
  end

  @doc """
  Seeds the default soccer positions (`GK, CB, FB, DM, CM, AM, W, ST`) for the
  current tenant if it has no position options yet. Idempotent.
  """
  @spec ensure_default_position_options() :: :ok | {:error, term()}
  def ensure_default_position_options do
    read(fn ->
      if Repo.exists?(from(o in PlayerPositionOption)) do
        :ok
      else
        insert_default_positions()
      end
    end)
  end

  @doc "The default soccer position codes and labels."
  @spec default_positions() :: [{String.t(), String.t()}]
  def default_positions, do: @default_positions

  @doc "Creates a position option."
  @spec create_position_option(Policy.actor(), map() | keyword()) ::
          {:ok, PlayerPositionOption.t()} | {:error, Ecto.Changeset.t()}
  def create_position_option(actor, attrs) do
    Multi.new()
    |> Multi.insert(
      :position_option,
      PlayerPositionOption.changeset(%PlayerPositionOption{}, tenant_attrs(attrs))
    )
    |> Multi.run(:audit, fn _repo, %{position_option: option} ->
      Audit.record(actor, "player.position_option.created", option, %{})
    end)
    |> run_multi(:position_option)
  end

  @doc "Updates a position option."
  @spec update_position_option(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, PlayerPositionOption.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
  def update_position_option(actor, id, attrs) do
    read(fn ->
      case Repo.get(PlayerPositionOption, id) do
        nil -> {:error, :not_found}
        option -> do_update_position_option(actor, option, attrs)
      end
    end)
  end

  defp do_update_position_option(actor, option, attrs) do
    Multi.new()
    |> Multi.update(:position_option, PlayerPositionOption.changeset(option, attrs))
    |> Multi.run(:audit, fn _repo, %{position_option: option} ->
      Audit.record(actor, "player.position_option.updated", option, %{})
    end)
    |> run_multi(:position_option)
  end

  ## Emergency contacts

  @doc "Lists a player's emergency contacts, highest priority first."
  @spec list_emergency_contacts(binary()) :: [EmergencyContact.t()]
  def list_emergency_contacts(player_id) do
    read(fn ->
      Repo.all(
        from c in EmergencyContact,
          where: c.player_id == ^player_id,
          order_by: [asc: c.priority, asc: c.inserted_at]
      )
    end)
  end

  @doc "Creates an emergency contact for a player."
  @spec create_emergency_contact(Player.t(), map() | keyword()) ::
          {:ok, EmergencyContact.t()} | {:error, Ecto.Changeset.t()}
  def create_emergency_contact(%Player{} = player, attrs) do
    read(fn ->
      %EmergencyContact{}
      |> EmergencyContact.changeset(child_attrs(attrs, player))
      |> Repo.insert()
    end)
  end

  @doc "Updates an emergency contact belonging to `player`."
  @spec update_emergency_contact(Player.t(), binary(), map() | keyword()) ::
          {:ok, EmergencyContact.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_emergency_contact(%Player{} = player, id, attrs) do
    read(fn ->
      case Repo.get_by(EmergencyContact, id: id, player_id: player.id) do
        nil -> {:error, :not_found}
        contact -> contact |> EmergencyContact.changeset(attrs) |> Repo.update()
      end
    end)
  end

  @doc "Deletes an emergency contact belonging to `player`."
  @spec delete_emergency_contact(Player.t(), binary()) ::
          {:ok, EmergencyContact.t()} | {:error, :not_found}
  def delete_emergency_contact(%Player{} = player, id) do
    read(fn ->
      case Repo.get_by(EmergencyContact, id: id, player_id: player.id) do
        nil -> {:error, :not_found}
        contact -> Repo.delete(contact)
      end
    end)
  end

  ## Authorized pickups

  @doc "Lists a player's authorized pickups."
  @spec list_authorized_pickups(binary()) :: [AuthorizedPickup.t()]
  def list_authorized_pickups(player_id) do
    read(fn ->
      Repo.all(
        from a in AuthorizedPickup,
          where: a.player_id == ^player_id,
          order_by: [asc: a.inserted_at]
      )
    end)
  end

  @doc "Creates an authorized pickup for a player."
  @spec create_authorized_pickup(Player.t(), map() | keyword()) ::
          {:ok, AuthorizedPickup.t()} | {:error, Ecto.Changeset.t()}
  def create_authorized_pickup(%Player{} = player, attrs) do
    read(fn ->
      %AuthorizedPickup{}
      |> AuthorizedPickup.changeset(child_attrs(attrs, player))
      |> Repo.insert()
    end)
  end

  @doc "Updates an authorized pickup belonging to `player`."
  @spec update_authorized_pickup(Player.t(), binary(), map() | keyword()) ::
          {:ok, AuthorizedPickup.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_authorized_pickup(%Player{} = player, id, attrs) do
    read(fn ->
      case Repo.get_by(AuthorizedPickup, id: id, player_id: player.id) do
        nil -> {:error, :not_found}
        pickup -> pickup |> AuthorizedPickup.changeset(attrs) |> Repo.update()
      end
    end)
  end

  @doc "Deletes an authorized pickup belonging to `player`."
  @spec delete_authorized_pickup(Player.t(), binary()) ::
          {:ok, AuthorizedPickup.t()} | {:error, :not_found}
  def delete_authorized_pickup(%Player{} = player, id) do
    read(fn ->
      case Repo.get_by(AuthorizedPickup, id: id, player_id: player.id) do
        nil -> {:error, :not_found}
        pickup -> Repo.delete(pickup)
      end
    end)
  end

  ## Medical info (encrypted; audited reads)

  @doc """
  Reads a player's medical info, recording a `player.medical.read` audit event.

  Returns `{:ok, nil}` when the player has no medical row.
  """
  @spec read_medical_info(Policy.actor(), Player.t()) :: {:ok, MedicalInfo.t() | nil}
  def read_medical_info(actor, %Player{} = player) do
    read(fn ->
      medical = Repo.one(from m in MedicalInfo, where: m.player_id == ^player.id, limit: 1)
      {:ok, _} = Audit.record(actor, "player.medical.read", player, %{})
      {:ok, medical}
    end)
  end

  @doc """
  Creates or updates a player's encrypted medical info.

  Records a `player.medical.updated` audit event. `has_medical_info` is derived
  from the clinical fields.
  """
  @spec upsert_medical_info(Policy.actor(), Player.t(), map() | keyword()) ::
          {:ok, MedicalInfo.t()} | {:error, Ecto.Changeset.t()}
  def upsert_medical_info(actor, %Player{} = player, attrs) do
    read(fn ->
      attrs = attrs |> tenant_attrs() |> Map.put("player_id", player.id)

      medical =
        case Repo.one(from m in MedicalInfo, where: m.player_id == ^player.id) do
          nil -> %MedicalInfo{}
          existing -> existing
        end

      Multi.new()
      |> Multi.insert_or_update(:medical, MedicalInfo.changeset(medical, attrs))
      |> Multi.run(:audit, fn _repo, %{medical: medical} ->
        Audit.record(actor, "player.medical.updated", player, %{})
        {:ok, medical}
      end)
      |> run_multi(:medical)
    end)
  end

  ## Private helpers

  defp search_query(term, params) do
    params = search_params(params)

    from(p in Player)
    |> maybe_household(params.household_id)
    |> maybe_include_inactive(params)
    |> filter_term(term)
  end

  defp maybe_household(query, nil), do: query

  defp maybe_household(query, household_id),
    do: where(query, [p], p.household_id == ^household_id)

  defp search_params(params) when is_map(params) do
    %{
      include_inactive:
        truthy?(Map.get(params, "include_inactive") || Map.get(params, :include_inactive)),
      household_id: Map.get(params, "household_id") || Map.get(params, :household_id)
    }
  end

  defp search_params(params) when is_list(params), do: search_params(Enum.into(params, %{}))

  defp maybe_include_inactive(query, %{include_inactive: true}), do: query
  defp maybe_include_inactive(query, _params), do: where(query, [p], p.active == true)

  defp filter_term(query, nil), do: query
  defp filter_term(query, ""), do: query

  defp filter_term(query, term) when is_binary(term) do
    like = "%" <> String.trim(term) <> "%"

    where(
      query,
      [p],
      ilike(p.first_name, ^like) or ilike(p.last_name, ^like) or
        ilike(p.preferred_name, ^like)
    )
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp summary(player) do
    contact = List.first(player.emergency_contacts)

    %{
      id: player.id,
      name: Player.display_name(player),
      full_name: "#{player.first_name} #{player.last_name}",
      age: age_on(player, Date.utc_today()),
      preferred_positions: (player.profile && player.profile.preferred_positions) || [],
      has_medical_info: !!(player.medical_info && player.medical_info.has_medical_info),
      emergency_contact: contact_summary(contact)
    }
  end

  defp contact_summary(nil), do: nil

  defp contact_summary(contact) do
    %{name: contact.name, relationship: contact.relationship, phone: contact.phone}
  end

  defp has_emergency_contact?(player_id) do
    Repo.exists?(from c in EmergencyContact, where: c.player_id == ^player_id)
  end

  defp build_profile_changeset(player, attrs) do
    case Repo.one(from p in PlayerProfile, where: p.player_id == ^player.id) do
      nil -> PlayerProfile.changeset(%PlayerProfile{}, attrs)
      existing -> PlayerProfile.changeset(existing, attrs)
    end
  end

  defp validate_positions(changeset, allowed) do
    positions = Ecto.Changeset.get_field(changeset, :preferred_positions) || []

    case Enum.reject(positions, &(&1 in allowed)) do
      [] ->
        changeset

      invalid ->
        Ecto.Changeset.add_error(
          changeset,
          :preferred_positions,
          "contains unknown positions: #{Enum.join(invalid, ", ")}"
        )
    end
  end

  defp active_position_codes do
    Repo.all(from o in PlayerPositionOption, where: o.active == true, select: o.code)
  end

  defp insert_default_positions do
    @default_positions
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{code, label}, index}, :ok ->
      attrs =
        tenant_attrs(%{code: code, label: label, position: index, active: true})

      %PlayerPositionOption{}
      |> PlayerPositionOption.changeset(attrs)
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:tenant_id, :code])
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp add_reason(reasons, true, reason), do: [reason | reasons]
  defp add_reason(reasons, _false, _reason), do: reasons

  defp with_player(id, fun) do
    read(fn ->
      case Repo.get(Player, id) do
        nil -> {:error, :not_found}
        player -> fun.(player)
      end
    end)
  end

  defp fetch_record(schema, id) do
    case Repo.get(schema, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp run_multi(multi, key) do
    # `Repo.with_tenant_tx/1`'s `Ecto.Multi` clause is currently unusable (its
    # internal `:__set_tenant__` step returns `:ok` instead of `{:ok, _}`); see
    # docs/rfcs/20260928-core-tenant-tx-multi.md. Run the multi in a nested
    # transaction that already has the tenant GUC set.
    #
    # A failed inner multi (including a DB constraint violation, which poisons
    # the outer transaction) is passed out via `rollback/1` so its changeset
    # survives instead of collapsing to a bare `:rollback`.
    result =
      Repo.with_tenant_tx(fn ->
        case Repo.transaction(multi) do
          {:ok, changes} -> changes
          {:error, _step, _reason, _changes} = failure -> Repo.rollback(failure)
        end
      end)

    case result do
      {:ok, changes} -> {:ok, Map.fetch!(changes, key)}
      {:error, {:error, ^key, %Ecto.Changeset{} = changeset, _changes}} -> {:error, changeset}
      {:error, {:error, _step, reason, _changes}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Privacy erasure

  @doc """
  Permanently deletes every player in a household.

  Profiles, emergency contacts, authorized pickups, and the encrypted medical
  info are removed by the `ON DELETE CASCADE` foreign keys. Returns the deleted
  player ids so other contexts can erase their own player-keyed data. Called by
  `SportsCoachBookings.Privacy`, which supplies the surrounding transaction and
  audit record.
  """
  @spec erase_household_players(binary()) :: [binary()]
  def erase_household_players(household_id) do
    read(fn ->
      ids = Repo.all(from p in Player, where: p.household_id == ^household_id, select: p.id)
      Repo.delete_all(from p in Player, where: p.id in ^ids)
      ids
    end)
  end

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp tenant_attrs(attrs) do
    attrs
    |> Enum.into(%{})
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
    |> Map.drop(["tenant_id", "id"])
    |> Map.put("tenant_id", TenantContext.get_tenant_id())
  end

  defp child_attrs(attrs, %Player{} = player) do
    attrs |> tenant_attrs() |> Map.put("player_id", player.id)
  end
end
