defmodule SportsCoachBookings.Release do
  @moduledoc """
  Tasks that run inside a built release.

  These exist so a release image can migrate and (optionally) seed without the
  full Mix toolchain. They are invoked by the release overlays:

    * `rel/overlays/bin/migrate` → `SportsCoachBookings.Release.migrate/0`
    * `rel/overlays/bin/server`  → `SportsCoachBookings.Release.migrate/0` then start
    * `fly.toml` `release_command = "/app/bin/migrate"` (runs before traffic shift)

  See `docs/ops.md` for the deploy/rollback runbook.
  """

  @app :sports_coach_bookings

  @doc "Run all pending migrations for every configured repo."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Roll a repo back to a given migration version.

  Used by the rollback procedure in `docs/ops.md`; prefer rolling forward with a
  new migration for schema fixes.
  """
  @spec rollback(module(), non_neg_integer()) :: :ok
  def rollback(repo, version) when is_atom(repo) and is_integer(version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc """
  Load `priv/repo/seeds.exs` inside the release.

  Only for standing up a demo/staging environment; never run against production
  data (see `docs/ops.md`).
  """
  @spec seeds() :: :ok
  # `seeds_file` is the fixed path to `priv/repo/seeds.exs` inside our own
  # release, never user input. Accepted false positive for RCE.CodeModule.
  # sobelow_skip ["RCE.CodeModule"]
  def seeds do
    load_app()
    seeds_file = Application.app_dir(@app, "priv/repo/seeds.exs")

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn _repo -> Code.eval_file(seeds_file) end)
    end

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.ensure_all_started(@app)
end
