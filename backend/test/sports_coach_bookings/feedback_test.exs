defmodule SportsCoachBookings.FeedbackTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Bookings.CoachAccess
  alias SportsCoachBookings.Core.StaffActor
  alias SportsCoachBookings.Feedback
  alias SportsCoachBookings.Feedback.SessionFeedback
  alias SportsCoachBookings.ObanHelpers
  alias SportsCoachBookings.Players
  alias SportsCoachBookings.Staff

  setup do
    CoachAccess.reset_cache()
    tenant = insert(:tenant)
    put_tenant(tenant)
    venue = insert(:venue)
    %{tenant: tenant, venue: venue}
  end

  describe "skill tags" do
    test "seeds the default tags once" do
      assert :ok = Feedback.ensure_default_skill_tags()
      tags = Feedback.list_skill_tags()
      assert length(tags) == 7
      assert Enum.any?(tags, &(&1.slug == "first_touch"))

      assert :ok = Feedback.ensure_default_skill_tags()
      assert length(Feedback.list_skill_tags()) == 7
    end
  end

  describe "session scoping" do
    test "a coach creates feedback for an assigned session but not another coach's", %{
      tenant: tenant,
      venue: venue
    } do
      membership = coach(tenant)
      actor = coach_actor(tenant, membership)
      offering = insert(:offering)

      {mine, player} = booked_session(venue, offering, membership, -1)
      _other = booked_session(venue, offering, nil, -1)

      assert {:ok, feedback} =
               Feedback.create_feedback(actor, %{
                 session_id: mine.id,
                 player_id: player.id,
                 body: "Great work on the first touch."
               })

      assert feedback.visibility == :internal
      assert feedback.coach_id == membership.id

      {other_session, other_player} = booked_session(venue, offering, nil, -1)

      assert {:error, :forbidden} =
               Feedback.create_feedback(actor, %{
                 session_id: other_session.id,
                 player_id: other_player.id,
                 body: "Should not be allowed"
               })
    end

    test "the roster is 403 for a session the coach is not assigned to", %{
      tenant: tenant,
      venue: venue
    } do
      membership = coach(tenant)
      actor = coach_actor(tenant, membership)
      offering = insert(:offering)
      {session, _player} = booked_session(venue, offering, nil, -1)

      assert {:error, :forbidden} = Feedback.roster(actor, session.id)
    end

    test "the roster includes player summaries and feedback status", %{
      tenant: tenant,
      venue: venue
    } do
      membership = coach(tenant)
      actor = coach_actor(tenant, membership)
      offering = insert(:offering)
      {session, player} = booked_session(venue, offering, membership, -1)

      {:ok, _feedback} =
        Feedback.create_feedback(actor, %{
          session_id: session.id,
          player_id: player.id,
          body: "Solid."
        })

      assert {:ok, [row]} = Feedback.roster(actor, session.id)
      assert row.player_id == player.id
      assert row.player.name == player.first_name
      assert row.status == "confirmed"
      assert [%SessionFeedback{}] = row.feedback
    end
  end

  describe "feedback window" do
    test "a coach cannot submit feedback before the session starts", %{
      tenant: tenant,
      venue: venue
    } do
      membership = coach(tenant)
      actor = coach_actor(tenant, membership)
      offering = insert(:offering)
      {session, player} = booked_session(venue, offering, membership, 3)

      assert {:error, {:too_early, _message}} =
               Feedback.create_feedback(actor, %{
                 session_id: session.id,
                 player_id: player.id,
                 body: "Too soon"
               })
    end

    test "a coach cannot submit feedback once the window has closed", %{
      tenant: tenant,
      venue: venue
    } do
      membership = coach(tenant)
      actor = coach_actor(tenant, membership)
      offering = insert(:offering)
      {session, player} = booked_session(venue, offering, membership, -20)

      assert {:error, {:feedback_closed, _message}} =
               Feedback.create_feedback(actor, %{
                 session_id: session.id,
                 player_id: player.id,
                 body: "Too late"
               })
    end

    test "an owner may backfill feedback outside the window", %{tenant: tenant, venue: venue} do
      membership = coach(tenant)
      actor = owner_actor(tenant)
      offering = insert(:offering)
      {session, player} = booked_session(venue, offering, membership, 5)

      assert {:ok, feedback} =
               Feedback.create_feedback(actor, %{
                 session_id: session.id,
                 player_id: player.id,
                 coach_id: membership.id,
                 body: "Backfilled"
               })

      assert feedback.coach_id == membership.id
    end
  end

  describe "sharing and editing" do
    test "sharing publishes feedback.submitted exactly once", %{tenant: tenant, venue: venue} do
      {actor, session, player} = prepared_coach_feedback(tenant, venue)
      {:ok, feedback} = create_feedback(actor, session, player)
      assert ObanHelpers.event_count("feedback.submitted") == 0

      assert {:ok, shared} = Feedback.share_feedback(actor, feedback.id)
      assert shared.visibility == :shared
      assert shared.shared_at
      assert ObanHelpers.event_count("feedback.submitted") == 1

      assert {:ok, _again} = Feedback.share_feedback(actor, feedback.id)
      assert ObanHelpers.event_count("feedback.submitted") == 1
    end

    test "editing snapshots a revision and does not re-publish unless notify", %{
      tenant: tenant,
      venue: venue
    } do
      {actor, session, player} = prepared_coach_feedback(tenant, venue)
      {:ok, feedback} = create_feedback(actor, session, player)
      {:ok, _shared} = Feedback.share_feedback(actor, feedback.id)
      assert ObanHelpers.event_count("feedback.submitted") == 1

      assert {:ok, edited} = Feedback.edit_feedback(actor, feedback.id, %{body: "Updated body"})
      assert edited.body == "Updated body"
      assert edited.edited_at
      assert ObanHelpers.event_count("feedback.submitted") == 1

      assert [revision] = Feedback.list_revisions(feedback.id)
      assert revision.body == "Strong session; focus on first touch."
      assert revision.revision == 1

      assert {:ok, _notified} =
               Feedback.edit_feedback(actor, feedback.id, %{body: "Again", notify: true})

      assert ObanHelpers.event_count("feedback.submitted") == 2
    end

    test "a shared row cannot be edited after the 48h window", %{tenant: tenant, venue: venue} do
      {actor, session, player} = prepared_coach_feedback(tenant, venue)
      {:ok, feedback} = create_feedback(actor, session, player)
      {:ok, shared} = Feedback.share_feedback(actor, feedback.id)

      old = DateTime.add(DateTime.utc_now(), -49 * 3_600, :second)

      shared
      |> Ecto.Changeset.change(shared_at: DateTime.truncate(old, :microsecond))
      |> Repo.update!()

      assert {:error, {:edit_window_closed, _message}} =
               Feedback.edit_feedback(actor, feedback.id, %{body: "Too late"})
    end

    test "internal feedback never appears in the portal view", %{tenant: tenant, venue: venue} do
      {actor, session, player} = prepared_coach_feedback(tenant, venue)
      {:ok, feedback} = create_feedback(actor, session, player)

      assert Feedback.shared_for_player(player.id) == []
      assert [%SessionFeedback{visibility: :internal}] = Feedback.list_for_player(player.id)

      {:ok, _shared} = Feedback.share_feedback(actor, feedback.id)
      assert [%SessionFeedback{visibility: :shared}] = Feedback.shared_for_player(player.id)
    end
  end

  describe "player visibility" do
    test "a coach cannot read a player with no booking in their sessions", %{
      tenant: tenant,
      venue: venue
    } do
      membership = coach(tenant)
      actor = coach_actor(tenant, membership)
      offering = insert(:offering)
      _session = booked_session(venue, offering, membership, -1)
      stranger = create_player(insert(:household).id)

      assert {:error, :forbidden} = Feedback.coach_player(actor, stranger.id)
    end

    test "a coach reads a visible player with recent feedback", %{tenant: tenant, venue: venue} do
      {actor, session, player} = prepared_coach_feedback(tenant, venue)
      {:ok, _feedback} = create_feedback(actor, session, player)

      assert {:ok, %{player: %{id: id}, feedback: [feedback]}} =
               Feedback.coach_player(actor, player.id)

      assert id == player.id
      assert feedback.body == "Strong session; focus on first touch."
    end
  end

  ## Helpers

  defp create_feedback(actor, session, player) do
    Feedback.create_feedback(actor, %{
      session_id: session.id,
      player_id: player.id,
      body: "Strong session; focus on first touch."
    })
  end

  defp prepared_coach_feedback(tenant, venue) do
    membership = coach(tenant)
    actor = coach_actor(tenant, membership)
    offering = insert(:offering)
    {session, player} = booked_session(venue, offering, membership, -1)
    {actor, session, player}
  end

  defp coach(tenant) do
    email = "coach-#{System.unique_integer([:positive])}@example.com"
    {:ok, staff_user} = Staff.register_staff_user(%{email: email, password: "password1234"})
    {:ok, membership} = Staff.upsert_membership(tenant.id, staff_user.id, :coach)
    membership
  end

  defp coach_actor(tenant, membership) do
    StaffActor.new(
      staff_user_id: membership.staff_user_id,
      membership: membership,
      tenant_id: tenant.id,
      role: :coach
    )
  end

  defp owner_actor(tenant) do
    StaffActor.new(
      staff_user_id: Ecto.UUID.generate(),
      tenant_id: tenant.id,
      role: :owner
    )
  end

  defp booked_session(venue, offering, membership, days_offset) do
    starts_at =
      DateTime.utc_now()
      |> DateTime.add(trunc(days_offset * 86_400), :second)
      |> DateTime.truncate(:microsecond)

    session =
      insert(:session,
        offering_id: offering.id,
        venue_id: venue.id,
        capacity: 5,
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, 3600, :second)
      )

    if membership do
      insert(:session_coach, session: session, membership_id: membership.id)
    end

    player = create_player(insert(:household).id)

    insert(:booking,
      session_id: session.id,
      player_id: player.id,
      household_id: player.household_id
    )

    {session, player}
  end

  defp create_player(household_id) do
    {:ok, player} =
      Players.create_player(nil, %{
        household_id: household_id,
        first_name: "Test",
        last_name: "Player #{System.unique_integer([:positive])}",
        date_of_birth: ~D[2015-05-01]
      })

    player
  end
end
