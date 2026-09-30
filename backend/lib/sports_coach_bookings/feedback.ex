defmodule SportsCoachBookings.Feedback do
  @moduledoc """
  Coach feedback on players and sessions, plus the coach-facing reads. Owned by
  WP-15.

  Coaches see only the sessions they are assigned to (checked against
  `Scheduling.session_detail/1`) and only the players visible through
  `Bookings.CoachAccess`. Attendance marking delegates to
  `SportsCoachBookings.Bookings` so the same window rules apply. Sharing a
  feedback row publishes `feedback.submitted` exactly once inside the write
  transaction; edits snapshot the previous state into `feedback_revisions` and
  never re-publish unless `notify: true` is passed.
  """

  import Ecto.Query

  alias SportsCoachBookings.Bookings
  alias SportsCoachBookings.Core.Pagination
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Core.TenantContext
  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Feedback.Policy
  alias SportsCoachBookings.Feedback.Revision
  alias SportsCoachBookings.Feedback.SessionFeedback
  alias SportsCoachBookings.Feedback.SkillTag
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Players.Player
  alias SportsCoachBookings.Repo
  alias SportsCoachBookings.Scheduling
  alias SportsCoachBookings.Staff

  @default_skill_tags [
    {"First touch", "first_touch"},
    {"Passing", "passing"},
    {"Shooting", "shooting"},
    {"1v1 defending", "one_v_one_defending"},
    {"Positioning", "positioning"},
    {"Work rate", "work_rate"},
    {"Communication", "communication"}
  ]

  @feedback_window_days 14
  @edit_window_hours 48

  ## Skill tags

  @doc "Lists the tenant's skill tags, ordered."
  @spec list_skill_tags() :: [SkillTag.t()]
  def list_skill_tags do
    read(fn ->
      Repo.all(from t in SkillTag, order_by: [asc: t.position, asc: t.name])
    end)
  end

  @doc """
  Seeds the default skill tags for the current tenant if it has none.

  Idempotent: a tenant with at least one tag is left untouched. Uses
  `on_conflict: :nothing` so concurrent callers do not race.
  """
  @spec ensure_default_skill_tags() :: :ok | {:error, term()}
  def ensure_default_skill_tags do
    write(fn ->
      tenant_id = TenantContext.get_tenant_id()

      Enum.with_index(@default_skill_tags)
      |> Enum.each(fn {{name, slug}, position} ->
        %SkillTag{}
        |> SkillTag.changeset(%{
          tenant_id: tenant_id,
          name: name,
          slug: slug,
          position: position,
          active: true
        })
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:tenant_id, :slug])
      end)

      :ok
    end)
  end

  @doc "Creates a tenant skill tag."
  @spec create_skill_tag(Policy.actor(), map() | keyword()) ::
          {:ok, SkillTag.t()} | {:error, term()}
  def create_skill_tag(_actor, attrs) do
    attrs = normalize(attrs)

    params = %{
      tenant_id: TenantContext.get_tenant_id(),
      name: fetch(attrs, :name),
      slug: fetch(attrs, :slug),
      position: fetch(attrs, :position) || 0,
      active: if(has_key?(attrs, :active), do: truthy?(fetch(attrs, :active)), else: true)
    }

    write(fn ->
      %SkillTag{}
      |> SkillTag.changeset(params)
      |> Repo.insert()
    end)
  end

  ## Coach sessions / roster / player

  @doc """
  Lists sessions for the coach's dashboard.

  Owners and admins see the whole tenant calendar; a coach sees only the
  sessions they are assigned to.
  """
  @spec list_coach_sessions(Policy.actor(), map() | keyword()) :: [map()]
  def list_coach_sessions(actor, filters \\ %{}) do
    filters = Map.take(normalize(filters), ["from", "to"])

    case actor do
      %StaffActor{role: role} when role in [:owner, :admin] ->
        Scheduling.calendar(filters, include_hidden: true)

      %StaffActor{role: :coach} = actor ->
        case membership_id(actor) do
          nil -> []
          membership_id -> Scheduling.my_sessions(membership_id, filters)
        end

      _ ->
        []
    end
  end

  @doc """
  The roster for a session: bookings (delegated to `Bookings`), player
  summaries (`Players.summary_for_roster/1`), attendance status, and the
  feedback rows recorded for each player.

  Returns `{:error, :forbidden}` when a coach is not assigned to the session.
  """
  @spec roster(Policy.actor(), binary()) :: {:ok, [map()]} | {:error, term()}
  def roster(actor, session_id) do
    with {:ok, _entry} <- load_session(actor, session_id) do
      {:ok, build_roster(session_id)}
    end
  end

  @doc """
  A player's profile for a coach: profile, contacts, and recent feedback from
  the tenant's coaches. 403 unless the actor may see the player.

  Medical values are **not** included; use the wp-06 medical endpoint, which is
  audited.
  """
  @spec coach_player(Policy.actor(), binary()) :: {:ok, map()} | {:error, term()}
  def coach_player(actor, player_id) do
    with {:ok, player} <- Players.fetch_player_detail(player_id),
         :ok <- Policy.authorize(actor, :get, player) do
      {:ok, %{player: player, feedback: list_for_player(player_id)}}
    end
  end

  ## Attendance

  @doc """
  Bulk-marks attendance for bookings in `session_id`, delegating each change to
  `Bookings.mark_attendance/3` so the same authorization and window rules
  apply.

  Returns `{:ok, results}` where each result is `%{booking_id, status, ok, error}`.
  """
  @spec mark_attendance(Policy.actor(), binary(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def mark_attendance(actor, session_id, entries) when is_list(entries) do
    with {:ok, _entry} <- load_session(actor, session_id) do
      {:ok, Enum.map(entries, &mark_one(actor, session_id, &1))}
    end
  end

  def mark_attendance(_actor, _session_id, _entries),
    do: {:error, {:invalid_entries, "attendance must be a list"}}

  ## Feedback writes

  @doc """
  Creates feedback for a player in a session.

  `attrs` includes `session_id`, `player_id`, `body`, optional `skill_ratings`
  (map of skill-tag slug to 1..5), optional `focus_next`, and optional
  `visibility` (`internal` default, or `shared`). Creating with
  `visibility: "shared"` shares immediately and publishes `feedback.submitted`
  once.
  """
  @spec create_feedback(Policy.actor(), map() | keyword()) ::
          {:ok, SessionFeedback.t()} | {:error, term()}
  def create_feedback(actor, attrs) do
    attrs = normalize(attrs)
    session_id = fetch(attrs, :session_id)
    player_id = fetch(attrs, :player_id)
    coach_id = resolve_coach_id(actor, fetch(attrs, :coach_id))

    with :ok <- Policy.authorize(actor, :create, :feedback),
         :ok <- load_session_ok(actor, session_id),
         :ok <- ensure_player_visible(actor, player_id),
         :ok <- ensure_player_booked(session_id, player_id),
         :ok <- ensure_feedback_window(actor, session_id),
         :ok <- ensure_membership(coach_id),
         :ok <- ensure_default_skill_tags(),
         {:ok, ratings} <- validate_skill_ratings(fetch(attrs, :skill_ratings)) do
      params = %{
        tenant_id: TenantContext.get_tenant_id(),
        session_id: session_id,
        player_id: player_id,
        coach_id: coach_id,
        body: fetch(attrs, :body),
        skill_ratings: ratings,
        focus_next: fetch(attrs, :focus_next),
        visibility: fetch(attrs, :visibility) || :internal
      }

      write(fn -> insert_feedback(params) end)
    end
  end

  defp insert_feedback(params) do
    changeset = %SessionFeedback{} |> SessionFeedback.create_changeset(params)
    shared? = Ecto.Changeset.get_field(changeset, :visibility) == :shared

    changeset =
      if shared?, do: Ecto.Changeset.put_change(changeset, :shared_at, now()), else: changeset

    with {:ok, feedback} <- Repo.insert(changeset),
         {:ok, _job} <- maybe_publish(feedback, shared?, false) do
      {:ok, feedback}
    end
  end

  @doc """
  Shares a feedback row with the household.

  Sets `visibility: shared` and `shared_at`, and publishes `feedback.submitted`
  exactly once. Sharing an already-shared row is a no-op (no event).
  """
  @spec share_feedback(Policy.actor(), binary()) ::
          {:ok, SessionFeedback.t()} | {:error, term()}
  def share_feedback(actor, feedback_id) do
    with {:ok, feedback} <- fetch_feedback(feedback_id),
         :ok <- authorize_author(actor, feedback, :share),
         :ok <- load_session_ok(actor, feedback.session_id) do
      write(fn -> share_tx(feedback) end)
    end
  end

  defp share_tx(%SessionFeedback{visibility: :shared} = feedback), do: {:ok, feedback}

  defp share_tx(feedback) do
    with {:ok, updated} <-
           feedback
           |> Ecto.Changeset.change(visibility: :shared, shared_at: now())
           |> Repo.update(),
         {:ok, _job} <- Events.publish("feedback.submitted", event_payload(updated, false)) do
      {:ok, updated}
    end
  end

  @doc """
  Edits a feedback row, snapshotting the previous state into
  `feedback_revisions`.

  Only the author (or an owner/admin) may edit. The author may edit a shared row
  for #{@edit_window_hours} hours after it was shared; an internal draft is
  editable any time. Passing `notify: true` on a shared row publishes a
  `feedback.submitted` update (wp-16 may send an "updated" email); otherwise
  editing never re-publishes.
  """
  @spec edit_feedback(Policy.actor(), binary(), map() | keyword()) ::
          {:ok, SessionFeedback.t()} | {:error, term()}
  def edit_feedback(actor, feedback_id, attrs) do
    attrs = normalize(attrs)

    with {:ok, feedback} <- fetch_feedback(feedback_id),
         :ok <- authorize_author(actor, feedback, :edit),
         :ok <- check_edit_window(actor, feedback),
         {:ok, ratings} <- edit_ratings(attrs, feedback) do
      notify = truthy?(fetch(attrs, :notify))
      write(fn -> edit_tx(feedback, actor, attrs, ratings, notify) end)
    end
  end

  defp edit_tx(feedback, actor, attrs, ratings, notify) do
    params =
      %{
        body: fetch(attrs, :body) || feedback.body,
        skill_ratings: ratings,
        visibility: fetch(attrs, :visibility) || feedback.visibility
      }
      |> put_if_present(attrs, :focus_next)

    with {:ok, _revision} <- insert_revision(feedback, actor, notify),
         {:ok, updated} <-
           feedback
           |> SessionFeedback.edit_changeset(params)
           |> Ecto.Changeset.put_change(:edited_at, now())
           |> Repo.update(),
         {:ok, _job} <- maybe_publish(updated, notify and updated.visibility == :shared, true) do
      {:ok, updated}
    end
  end

  ## Feedback reads

  @doc "Fetches a feedback row by id, or `{:error, :not_found}`."
  @spec fetch_feedback(binary()) :: {:ok, SessionFeedback.t()} | {:error, :not_found}
  def fetch_feedback(id) do
    read(fn ->
      case Repo.get(SessionFeedback, id) do
        nil -> {:error, :not_found}
        feedback -> {:ok, feedback}
      end
    end)
  end

  @doc """
  Fetches a feedback row if `actor` may read it.

  Owners and admins read any row. A coach may read feedback about players visible
  to them (via `Bookings.CoachAccess`).
  """
  @spec get_feedback(Policy.actor(), binary()) :: {:ok, SessionFeedback.t()} | {:error, term()}
  def get_feedback(actor, feedback_id) do
    with {:ok, feedback} <- fetch_feedback(feedback_id),
         :ok <- Policy.authorize(actor, :get, :feedback),
         :ok <- ensure_player_visible(actor, feedback.player_id) do
      {:ok, feedback}
    end
  end

  @doc "Lists every feedback row for a player, newest first (staff view)."
  @spec list_for_player(binary()) :: [SessionFeedback.t()]
  def list_for_player(player_id) do
    read(fn ->
      Repo.all(
        from f in SessionFeedback,
          where: f.player_id == ^player_id,
          order_by: [desc: f.inserted_at, desc: f.id]
      )
    end)
  end

  @doc "Lists the shared feedback for a player, newest first (portal view)."
  @spec shared_for_player(binary()) :: [SessionFeedback.t()]
  def shared_for_player(player_id) do
    read(fn ->
      Repo.all(
        from f in SessionFeedback,
          where: f.player_id == ^player_id and f.visibility == :shared,
          order_by: [desc: f.shared_at, desc: f.id]
      )
    end)
  end

  @doc """
  Paginates feedback for staff review.

  Filters: `:coach_id`, `:player_id`, `:session_id`, `:from`, `:to`.

  Owners and admins review every row. A coach only lists the feedback they
  authored; when a `player_id` filter is present the player must be visible to
  them.
  """
  @spec page_feedback(Policy.actor(), map() | keyword(), map() | keyword()) ::
          %{data: [SessionFeedback.t()], next_cursor: binary() | nil}
  def page_feedback(actor, filters \\ %{}, params \\ %{}) do
    filters = normalize(filters)

    case actor do
      %StaffActor{role: role} when role in [:owner, :admin] ->
        read(fn ->
          {rows, cursor} = Pagination.paginate(feedback_query(filters), params)
          %{data: rows, next_cursor: cursor}
        end)

      %StaffActor{role: :coach} = actor ->
        coach_page(actor, filters, params)

      _ ->
        %{data: [], next_cursor: nil}
    end
  end

  @doc "Lists the revisions of a feedback row, oldest first."
  @spec list_revisions(binary()) :: [Revision.t()]
  def list_revisions(feedback_id) do
    read(fn ->
      Repo.all(
        from r in Revision,
          where: r.feedback_id == ^feedback_id,
          order_by: [asc: r.revision, asc: r.inserted_at]
      )
    end)
  end

  ## Implementation

  defp coach_page(actor, filters, params) do
    membership_id = membership_id(actor)

    cond do
      is_nil(membership_id) ->
        empty_page()

      player_id = fetch(filters, :player_id) ->
        visible_coach_page(actor, filters, params, player_id)

      true ->
        paginate_feedback(Map.put(filters, :coach_id, membership_id), params)
    end
  end

  defp visible_coach_page(actor, filters, params, player_id) do
    case ensure_player_visible(actor, player_id) do
      :ok -> paginate_feedback(filters, params)
      {:error, _reason} -> empty_page()
    end
  end

  defp paginate_feedback(filters, params) do
    read(fn ->
      {rows, cursor} = Pagination.paginate(feedback_query(filters), params)
      %{data: rows, next_cursor: cursor}
    end)
  end

  defp empty_page, do: %{data: [], next_cursor: nil}

  defp feedback_query(filters) do
    SessionFeedback
    |> filter_coach(fetch(filters, :coach_id))
    |> filter_player(fetch(filters, :player_id))
    |> filter_session(fetch(filters, :session_id))
    |> filter_inserted_from(fetch(filters, :from))
    |> filter_inserted_to(fetch(filters, :to))
  end

  defp filter_coach(query, nil), do: query
  defp filter_coach(query, id), do: where(query, [f], f.coach_id == ^id)

  defp filter_player(query, nil), do: query
  defp filter_player(query, id), do: where(query, [f], f.player_id == ^id)

  defp filter_session(query, nil), do: query
  defp filter_session(query, id), do: where(query, [f], f.session_id == ^id)

  defp filter_inserted_from(query, nil), do: query
  defp filter_inserted_from(query, %DateTime{} = dt), do: where(query, [f], f.inserted_at >= ^dt)

  defp filter_inserted_to(query, nil), do: query
  defp filter_inserted_to(query, %DateTime{} = dt), do: where(query, [f], f.inserted_at <= ^dt)

  defp build_roster(session_id) do
    rows = Bookings.session_roster(session_id)
    player_ids = Enum.map(rows, & &1.player_id)
    summaries = Players.summary_for_roster(player_ids) |> Map.new(&{&1.id, &1})
    by_player = list_for_session(session_id) |> Enum.group_by(& &1.player_id)

    Enum.map(rows, fn row ->
      %{
        booking_id: row.booking_id,
        player_id: row.player_id,
        player: Map.get(summaries, row.player_id),
        status: row.status,
        payment_method: row.payment_method,
        credits_used: row.credits_used,
        hold_expires_at: row.hold_expires_at,
        feedback: Map.get(by_player, row.player_id, [])
      }
    end)
  end

  defp list_for_session(session_id) do
    read(fn ->
      Repo.all(
        from f in SessionFeedback,
          where: f.session_id == ^session_id,
          order_by: [desc: f.inserted_at, desc: f.id]
      )
    end)
  end

  defp mark_one(actor, session_id, entry) do
    entry = normalize(entry)
    booking_id = fetch(entry, :booking_id)
    status = status_atom(fetch(entry, :status))

    result =
      with true <- is_binary(booking_id) or {:error, :not_found},
           {:ok, booking} <- Bookings.fetch_booking(booking_id),
           :ok <- ensure_same_session(booking, session_id),
           {:ok, updated} <- Bookings.mark_attendance(actor, booking_id, status) do
        %{booking_id: updated.id, status: to_string(updated.status), ok: true, error: nil}
      else
        {:error, reason} ->
          %{
            booking_id: booking_id,
            status: to_string(status),
            ok: false,
            error: error_code(reason)
          }
      end

    result
  end

  defp ensure_same_session(%{session_id: session_id}, session_id), do: :ok

  defp ensure_same_session(_booking, _session_id),
    do: {:error, {:not_in_session, "The booking is not in this session"}}

  defp status_atom("attended"), do: :attended
  defp status_atom("no_show"), do: :no_show
  defp status_atom(status) when status in [:attended, :no_show], do: status
  defp status_atom(_status), do: :invalid

  defp error_code(:forbidden), do: "forbidden"
  defp error_code(:not_found), do: "not_found"

  defp error_code({code, _message}) when is_atom(code), do: to_string(code)
  defp error_code({code, _message, _details}) when is_atom(code), do: to_string(code)
  defp error_code(_reason), do: "error"

  ## Session scope

  defp load_session_ok(actor, session_id) do
    with {:ok, _entry} <- load_session(actor, session_id), do: :ok
  end

  defp load_session(actor, session_id) when is_binary(session_id) do
    case Scheduling.session_detail(session_id) do
      {:ok, %{coaches: coaches} = entry} ->
        case scope_ok?(actor, coaches) do
          :ok -> {:ok, entry}
          error -> error
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp load_session(_actor, _session_id), do: {:error, :not_found}

  defp scope_ok?(%StaffActor{role: role}, _coaches) when role in [:owner, :admin], do: :ok

  defp scope_ok?(%StaffActor{role: :coach} = actor, coaches) do
    case membership_id(actor) do
      nil ->
        {:error, :forbidden}

      membership_id ->
        if Enum.any?(coaches, &(&1.id == membership_id)), do: :ok, else: {:error, :forbidden}
    end
  end

  defp scope_ok?(_actor, _coaches), do: {:error, :forbidden}

  ## Authorisation helpers

  defp authorize_author(actor, feedback, action) do
    with :ok <- Policy.authorize(actor, action, :feedback) do
      if author_or_manager?(actor, feedback), do: :ok, else: {:error, :forbidden}
    end
  end

  defp author_or_manager?(%StaffActor{role: role}, _feedback) when role in [:owner, :admin],
    do: true

  defp author_or_manager?(%StaffActor{role: :coach} = actor, feedback) do
    membership_id(actor) == feedback.coach_id
  end

  defp author_or_manager?(_actor, _feedback), do: false

  defp ensure_player_visible(%StaffActor{role: role}, _player_id) when role in [:owner, :admin],
    do: :ok

  defp ensure_player_visible(%StaffActor{role: :coach} = actor, player_id) do
    if is_binary(player_id) and coach_access().player_visible?(actor, player_id),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp ensure_player_visible(_actor, _player_id), do: {:error, :forbidden}

  defp ensure_player_booked(session_id, player_id) do
    if is_binary(player_id) and Bookings.player_booked_in_session?(player_id, session_id),
      do: :ok,
      else: {:error, {:not_in_session, "The player is not booked into this session"}}
  end

  defp ensure_feedback_window(%StaffActor{role: role}, _session_id) when role in [:owner, :admin],
    do: :ok

  defp ensure_feedback_window(_actor, session_id) do
    session = Scheduling.get_session!(session_id)
    reference = now()
    opens_at = session.starts_at
    closes_at = DateTime.add(opens_at, @feedback_window_days * 86_400, :second)

    cond do
      DateTime.compare(reference, opens_at) == :lt ->
        {:error, {:too_early, "Feedback opens when the session starts"}}

      DateTime.compare(reference, closes_at) == :gt ->
        {:error, {:feedback_closed, "The feedback window has closed"}}

      true ->
        :ok
    end
  end

  defp ensure_membership(nil),
    do: {:error, {:invalid_coach, "A coach membership is required"}}

  defp ensure_membership(coach_id) do
    if Enum.any?(Staff.list_team(), &(&1.id == coach_id)),
      do: :ok,
      else: {:error, {:invalid_coach, "No such membership"}}
  end

  defp resolve_coach_id(%StaffActor{role: :coach} = actor, _requested), do: membership_id(actor)
  defp resolve_coach_id(actor, nil), do: membership_id(actor)
  defp resolve_coach_id(_actor, requested), do: requested

  defp check_edit_window(%StaffActor{role: role}, _feedback) when role in [:owner, :admin],
    do: :ok

  defp check_edit_window(_actor, %SessionFeedback{visibility: :internal}), do: :ok

  defp check_edit_window(_actor, %SessionFeedback{shared_at: %DateTime{} = shared_at}) do
    deadline = DateTime.add(shared_at, @edit_window_hours * 3_600, :second)

    if DateTime.compare(now(), deadline) == :gt,
      do: {:error, {:edit_window_closed, "Feedback can no longer be edited"}},
      else: :ok
  end

  defp check_edit_window(_actor, _feedback),
    do: {:error, {:edit_window_closed, "Feedback can no longer be edited"}}

  ## Revisions / events

  defp insert_revision(feedback, actor, notify) do
    revision = revision_count(feedback.id) + 1
    {editor_type, editor_id} = editor_fields(actor)

    %Revision{}
    |> Revision.changeset(%{
      tenant_id: feedback.tenant_id,
      feedback_id: feedback.id,
      revision: revision,
      body: feedback.body,
      skill_ratings: feedback.skill_ratings,
      focus_next: feedback.focus_next,
      visibility: to_string(feedback.visibility),
      shared_at: feedback.shared_at,
      notify: notify,
      editor_type: editor_type,
      editor_id: editor_id
    })
    |> Repo.insert()
  end

  defp revision_count(feedback_id) do
    Repo.one(from r in Revision, where: r.feedback_id == ^feedback_id, select: count(r.id))
  end

  defp editor_fields(%StaffActor{staff_user_id: id}), do: {"StaffActor", id}
  defp editor_fields(_actor), do: {nil, nil}

  defp maybe_publish(_feedback, false, _updated), do: {:ok, :noop}

  defp maybe_publish(feedback, true, updated),
    do: Events.publish("feedback.submitted", event_payload(feedback, updated))

  defp event_payload(feedback, updated) do
    %{
      feedback_id: feedback.id,
      tenant_id: feedback.tenant_id,
      session_id: feedback.session_id,
      player_id: feedback.player_id,
      coach_id: feedback.coach_id,
      household_id: household_for(feedback.player_id),
      updated: updated
    }
  end

  defp household_for(player_id) do
    case Players.fetch_player(player_id) do
      {:ok, %Player{household_id: household_id}} -> household_id
      _ -> nil
    end
  end

  ## Skill ratings

  defp validate_skill_ratings(nil), do: {:ok, %{}}

  defp validate_skill_ratings(ratings) when is_map(ratings) do
    tags = list_skill_tags() |> Map.new(&{&1.slug, &1})

    Enum.reduce_while(ratings, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      slug = to_string(key)

      cond do
        not Map.has_key?(tags, slug) -> {:halt, {:error, {:unknown_skill_tag, slug}}}
        not valid_rating?(value) -> {:halt, {:error, {:invalid_skill_rating, slug}}}
        true -> {:cont, {:ok, Map.put(acc, slug, value)}}
      end
    end)
  end

  defp validate_skill_ratings(_ratings),
    do: {:error, {:invalid_skill_ratings, "must be a map of skill tag to 1..5"}}

  defp valid_rating?(value), do: is_integer(value) and value in 1..5

  defp edit_ratings(attrs, feedback) do
    if has_key?(attrs, :skill_ratings),
      do: validate_skill_ratings(fetch(attrs, :skill_ratings)),
      else: {:ok, feedback.skill_ratings}
  end

  ## Shared helpers

  defp membership_id(%StaffActor{membership: %{id: id}}) when is_binary(id), do: id

  defp membership_id(%StaffActor{staff_user_id: staff_user_id}) when is_binary(staff_user_id) do
    case Staff.get_active_membership(staff_user_id) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp membership_id(_actor), do: nil

  defp coach_access do
    Application.get_env(
      :sports_coach_bookings,
      :coach_access,
      SportsCoachBookings.Bookings.CoachAccess
    )
  end

  defp normalize(attrs) when is_list(attrs), do: Enum.into(attrs, %{})
  defp normalize(attrs) when is_map(attrs), do: attrs
  defp normalize(_attrs), do: %{}

  defp fetch(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  defp has_key?(attrs, key) do
    Map.has_key?(attrs, key) or Map.has_key?(attrs, to_string(key))
  end

  defp put_if_present(map, attrs, key) do
    if has_key?(attrs, key), do: Map.put(map, key, fetch(attrs, key)), else: map
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp read(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp write(fun) do
    case Repo.with_tenant_tx(fun) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
