defmodule SportsCoachBookings.Repo.Migrations.SchedulingAddShowCoaches do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :show_coaches, :boolean, null: false, default: true
    end
  end
end
