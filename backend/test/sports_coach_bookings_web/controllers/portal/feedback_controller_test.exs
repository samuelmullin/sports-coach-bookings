defmodule SportsCoachBookingsWeb.Portal.FeedbackControllerTest do
  use SportsCoachBookingsWeb.ConnCase, async: false

  alias SportsCoachBookings.Core.CustomerActor
  alias SportsCoachBookings.Players

  setup do
    tenant = insert(:tenant, slug: "portal-feedback-#{System.unique_integer([:positive])}")
    SportsCoachBookings.DataCase.put_tenant(tenant)
    %{tenant: tenant}
  end

  test "a customer sees only shared feedback for their own player", %{conn: conn, tenant: tenant} do
    household = insert(:household).id
    player = create_player(household)

    insert(:session_feedback,
      player_id: player.id,
      visibility: :shared,
      body: "Shared progress note",
      shared_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    )

    insert(:session_feedback,
      player_id: player.id,
      visibility: :internal,
      body: "Internal only"
    )

    body =
      conn
      |> customer_conn(tenant, household)
      |> get("/api/portal/players/#{player.id}/feedback")
      |> json_response(200)

    assert [entry] = body["data"]
    assert entry["body"] == "Shared progress note"
    assert entry["visibility"] == "shared"
  end

  test "a customer cannot read another household's player feedback", %{
    conn: conn,
    tenant: tenant
  } do
    other = create_player(insert(:household).id)

    resp =
      conn
      |> customer_conn(tenant, Ecto.UUID.generate())
      |> get("/api/portal/players/#{other.id}/feedback")
      |> json_response(403)

    assert resp["error"]["code"] == "forbidden"
  end

  ## Helpers

  defp customer_conn(conn, tenant, household_id) do
    actor =
      CustomerActor.new(
        customer_user_id: Ecto.UUID.generate(),
        household_id: household_id,
        tenant_id: tenant.id
      )

    conn
    |> with_host(tenant.slug)
    |> Plug.Conn.assign(:current_customer_actor, actor)
    |> Plug.Conn.assign(:tenant, tenant)
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
