defmodule SportsCoachBookings.ObanHelpers do
  @moduledoc """
  Deterministic Oban queue draining for tests.

  Tests run Oban in `:manual` mode, so jobs are inserted into `oban_jobs` but
  never executed. These helpers run the pending jobs for a queue synchronously
  (invoking `perform/1` directly, which restores tenant context for
  `TenantWorker`s), then delete them. `drain_all/0` loops the `:payments` and
  `:events` queues until no new jobs remain, so cascaded events
  (`payment.succeeded` → `order.paid`) are fully processed.
  """

  import Ecto.Query

  alias SportsCoachBookings.Repo

  @doc "Runs every pending job on `queue`, then removes it."
  @spec drain(atom()) :: non_neg_integer()
  def drain(queue) do
    jobs =
      Repo.all(
        from j in Oban.Job,
          where: j.queue == ^to_string(queue),
          order_by: [asc: j.id]
      )

    Enum.each(jobs, &run/1)
    ids = Enum.map(jobs, & &1.id)
    if ids != [], do: Repo.delete_all(from j in Oban.Job, where: j.id in ^ids)
    length(jobs)
  end

  @doc "Repeatedly drains `:payments` then `:events` until both are empty."
  @spec drain_all() :: :ok
  def drain_all do
    drain_until_empty(:payments)
    drain_until_empty(:events)
  end

  @doc "Names of the pending event jobs (the `:events` queue)."
  @spec event_names() :: [String.t()]
  def event_names do
    Repo.all(
      from j in Oban.Job,
        where: j.queue == "events",
        select: j.args["name"]
    )
  end

  @doc "Counts the pending event jobs named `name`."
  @spec event_count(String.t()) :: non_neg_integer()
  def event_count(name) do
    Repo.one(
      from j in Oban.Job,
        where: j.queue == "events" and j.args["name"] == ^name,
        select: count(j.id)
    )
  end

  defp drain_until_empty(queue) do
    case drain(queue) do
      0 -> :ok
      _count -> drain_until_empty(queue)
    end
  end

  defp run(%Oban.Job{worker: worker} = job) do
    module = worker |> String.split(".") |> Module.concat()
    module.perform(job)
  end
end
