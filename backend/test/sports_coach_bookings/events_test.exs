defmodule SportsCoachBookings.EventsTest do
  use SportsCoachBookings.DataCase, async: false

  alias SportsCoachBookings.Events
  alias SportsCoachBookings.Events.EventWorker
  alias SportsCoachBookings.Repo

  defmodule Sink do
    @moduledoc false
    use Agent

    def start_link(_), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(entry), do: Agent.update(__MODULE__, &[entry | &1])
    def list, do: Agent.get(__MODULE__, & &1)
  end

  defmodule TestSubscriber do
    @moduledoc false
    alias SportsCoachBookings.Core.TenantContext

    def handle_event(name, payload) do
      Sink.record(%{
        name: name,
        payload: payload,
        tenant: TenantContext.get_tenant_id()
      })

      :ok
    end
  end

  setup do
    start_supervised!(Sink)

    previous = Application.get_env(:sports_coach_bookings, :event_subscribers)

    Application.put_env(:sports_coach_bookings, :event_subscribers, %{
      "thing.happened" => [TestSubscriber]
    })

    on_exit(fn ->
      Application.put_env(:sports_coach_bookings, :event_subscribers, previous)
    end)

    :ok
  end

  test "publish inserts an outbox job in the same transaction" do
    tenant = insert(:tenant)
    put_tenant(tenant)

    {:ok, {:ok, %Oban.Job{}}} =
      Repo.with_tenant_tx(fn -> Events.publish("thing.happened", %{id: "abc"}) end)

    assert [job] = Repo.all(Oban.Job)
    assert job.args["name"] == "thing.happened"
    assert job.args["tenant_id"] == tenant.id
    assert job.args["payload"]["id"] == "abc"
  end

  test "the worker restores tenant context and dispatches to subscribers" do
    tenant = insert(:tenant)
    put_tenant(tenant)

    {:ok, {:ok, %Oban.Job{} = job}} =
      Repo.with_tenant_tx(fn -> Events.publish("thing.happened", %{id: "abc"}) end)

    assert :ok = EventWorker.perform(job)

    assert [%{name: "thing.happened", tenant: tenant_id, payload: %{"id" => "abc"}}] = Sink.list()
    assert tenant_id == tenant.id
  end

  test "publishing rolls back with the transaction" do
    tenant = insert(:tenant)
    put_tenant(tenant)

    Repo.transaction(fn ->
      {:ok, _} = Events.publish("thing.happened", %{id: "rolled-back"})
      Repo.rollback(:nope)
    end)

    assert Repo.all(Oban.Job) == []
  end
end
